# P7: the seven-day memory soak and the battery-menu check

Two rows of `own-cost.feature` can only be checked on the meter you actually use, the release
copy installed at `/Applications/Meter.app`, over real time:

- **D76, 7 days** (Q2, ruled 2026-10-22): "the meter's Memory in Activity Monitor is under 50 MB
  after seven days without a restart." A background soak samples the installed meter every ten
  minutes and writes a report once one meter process has run seven days.
- **D75** (Q3, ruled 2026-10-22): "the meter is never listed under *Apps Using Significant
  Energy*." After a day on battery, the harness opens the battery menu through Accessibility and
  records what it lists.

Both rows stay in `wip` (the register in `test/features.test.js`) until their report exists. The
reports hold only what macOS's own tools read of the installed meter (`ps`, `footprint`,
`pmset`, the battery menu's texts), never anything the meter wrote. Neither check touches the
meter: nothing signals, restarts, moves or reinstalls it.

Both reports are held to **the P7 build**: version `0.7.0` (`app/Info.plist`), the meter you
install in step 0. A report taken with an older meter fails its row ("not the P7 build"). Start
both after P7 is merged, on your word. Nothing has been started yet.

The rulings of 2026-10-22 these checks follow:

- Q2: "the 7-day memory row by a background soak; the row stays wip until it reports."
- Q3: "energy by the harness reading the battery menu through AX after an all-day run on battery."
- "All day" is at least **6 awake hours** on battery with the meter running (sleep taken out, using
  pmset's own sleep and wake lines from the whole log).
- The 7 days count the meter's **own uptime**: one continuous process (same pid and start time); a
  restart resets the count.

## What runs when

| When | What | Who |
| --- | --- | --- |
| Day 0 | Install the P7 package (step 0), check the running meter is the new one, start the soak | you, a few commands |
| Days 0 to 7 | The soak reads the meter every 10 minutes; use the Mac normally, plugged in or not | the soak, by itself |
| One day in the week | Use the Mac all day on battery, then run the battery-menu check before plugging in | you, one command |
| Day 7 or later | The soak writes its report and stops reading | the soak, by itself |
| After both reports | Stop the soak and run the gate; the two rows bind to the reports | you, then a build session |

**While the soak runs, don't quit or restart the meter, and don't run `npm test`.** The harness
refuses to run beside a meter it didn't start (and quitting the meter for it would restart the
soak's seven days). Restarting the Mac, or a crash that the keep-alive relaunches, also starts
the seven days over: the soak counts from the running meter's own start time and waits for one
process seven days old. Sleep is fine: the meter keeps running through it, and the soak measures gaps in time awake, not wall time.

**What makes a soak report pass.** The report holds every reading from the process's first one to
its seven-day one. It must show: one process (pid and start time) throughout, the installed
`0.7.0` meter with one executable (sha) throughout, at least 7 days old by its own start time, every
reading under 50.0 MB (the highest one, not only day 7's), no growth of more than 5 MB from the
first day's highest reading to the last day's, the meter's CPU time advancing while the Mac is
awake and its state never stopped, and **no awake gap over 20 minutes** between readings (each reading records an awake clock, `CLOCK_UPTIME_RAW`, which stops while the Mac sleeps and runs during its brief darkwakes; gaps are differences of that clock, so nights asleep are not gaps; a reboot makes it go back and fails the report). A line saying the meter
wasn't running, or one saying the soak couldn't read it (`{"error": …}`), inside the week shows a
restart or a hole. The share of the week the Mac was awake is reported, not required.

## 0. Install the P7 package first (day 0, before the soak)

The soak must watch the P7 build, so install it before starting. An agent never touches
`/Applications/Meter.app`; you install it:

```sh
cd ~/gitrepos/menubar-meter
npm run build:app             # builds build/Meter.app and build/Meter.pkg
open build/Meter.pkg          # you run the installer
plutil -extract CFBundleShortVersionString raw /Applications/Meter.app/Contents/Info.plist
```

The last command must print `0.7.0`. Then make sure the running meter is the new one: log out and
in, or open `/Applications/Meter.app`. Check that it started after the install:

```sh
ps -o lstart=,comm= -p $(pgrep -f /Applications/Meter.app/Contents/MacOS/Meter)
```

Only then start the soak (step 1). Before any `npm test` later, click **Quit Meter** in the
installed meter's panel (the harness refuses to run beside it).

## 1. Start the soak (day 0)

With the P7 meter in the menu bar (step 0), start the soak. `soak-start.sh` refuses if
`/Applications/Meter.app` is missing or not the P7 version, and running it a second time replaces
the loaded job instead of failing:

```sh
cd ~/gitrepos/menubar-meter
sh scripts/checks/soak-start.sh
```

This copies `soak.sh` to `~/Library/Logs/menubar-meter-checks/` and loads a user LaunchAgent,
`~/Library/LaunchAgents/local.menubar-meter.soak.plist`, which runs it now and every ten minutes.
macOS may show a "Background Items Added" notification for it; that is this agent.

Each run appends one line to `~/Library/Logs/menubar-meter-checks/soak.ndjson`: the meter's pid
and start time (`ps -o lstart`), its state and CPU time (`ps -o stat,time`), its physical footprint
in bytes (`footprint -f bytes --noCategories`, the `phys_footprint` figure that Activity Monitor's
Memory column shows), its version and the sha of its executable, and the Mac's awake clock
(`CLOCK_UPTIME_RAW`, read with the stock `perl`) and last sleep and wake. To look at it now and then:

```sh
tail -3 ~/Library/Logs/menubar-meter-checks/soak.ndjson
```

A line `{"at":…,"program":null}` means the installed meter wasn't running at that moment, and
`{"at":…,"error":"…"}` that the soak couldn't take a reading; neither is silent, and either one
inside the week fails the report.

## 2. The battery-menu check (one day on battery)

Unplug in the morning with the P7 meter running (step 0), and use the Mac on battery all day as you
normally would. "All day" is at least **6 awake hours** on battery: the hours on battery less the
time the Mac slept, read from the whole of `pmset -g log` (the report shows both figures). At the
end of the day, **before plugging in**, with the screen unlocked and no menu open:

```sh
cd ~/gitrepos/menubar-meter
swift build -c release --product meter-ax
node scripts/checks/energy-check.js
```

It checks that the Mac is on battery and the installed meter is running, opens the battery menu in
the menu bar (an Accessibility press, as an assistive app presses it; the pointer doesn't move),
reads every element in it and closes it. It also reads the meter's state, CPU time (twice, 10
seconds apart) and status item. It writes
`~/Library/Logs/menubar-meter-checks/energy-report.json`. You will see the battery menu open and
close once. If it says the Mac is not on battery, it wrote nothing.

**What passes (ruling 2026-10-22):** `Meter` is not listed AND the menu was read properly, proved
by either at least one other app listed under *Using Significant Energy* (for example Ghostty), or
macOS's own "No Apps Using Significant Energy" text. It fails if `Meter` is listed, or if neither
proof is seen (the menu is unreadable: no energy section, or a heading with no rows). No stand-in
app is run by default (`METER_ENERGY_CONTROL=1` adds the optional one).

## 3. When the soak has reported (day 7 or later)

The report appears by itself:

```sh
ls -l ~/Library/Logs/menubar-meter-checks/soak-report.ndjson
```

Then stop the soak (the samples and both reports are kept):

```sh
cd ~/gitrepos/menubar-meter
sh scripts/checks/soak-stop.sh
```

## 4. Hand the results back

Tell a build session that both reports are in `~/Library/Logs/menubar-meter-checks/`. It will:

1. click **Quit Meter** in the installed meter's panel (the harness refuses to run beside it; do
   this before any `npm test`), then run the gate (`caffeinate -i npm test`, plugged in, lid open);
2. with the reports present, the 7-day row and the energy scenario bind and run: the 7-day row
   judges the whole week of one process (above) in Activity Monitor's units (megabytes of
   1,048,576 bytes, one decimal, under 50.0 MB) and shows the highest and the day-7 readings; the
   energy scenario reads the battery menu's elements and fails if the exact name `Meter` is listed
   under *Using Significant Energy*, or if the menu can't be read (above);
3. if both pass, the suite then fails once on purpose with a "wip entry fully bound" message: that
   is the ratchet asking for the `own-cost` entry to be removed from the register in
   `test/features.test.js`. Removing it leaves the register empty;
4. log out and in (or open `/Applications/Meter.app`) to bring your meter back.

If either report fails its row, the gate shows the readings: the soak's footprint at seven days,
or the apps the battery menu listed.
