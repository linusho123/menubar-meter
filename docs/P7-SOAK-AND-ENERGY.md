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

Start both after P7 is merged, on your word. Nothing has been started yet.

## What runs when

| When | What | Who |
| --- | --- | --- |
| Day 0 | Log in (the meter starts by its login item) and start the soak | you, one command |
| Days 0 to 7 | The soak reads the meter every 10 minutes; use the Mac normally, plugged in or not | the soak, by itself |
| One day in the week | Use the Mac all day on battery, then run the battery-menu check before plugging in | you, one command |
| Day 7 or later | The soak writes its report and stops reading | the soak, by itself |
| After both reports | Stop the soak and run the gate; the two rows bind to the reports | you, then a build session |

**While the soak runs, don't quit or restart the meter, and don't run `npm test`.** The harness
refuses to run beside a meter it didn't start (and quitting the meter for it would restart the
soak's seven days). Restarting the Mac, or a crash that the keep-alive relaunches, also starts
the seven days over: the soak counts from the running meter's own start time and waits for one
process seven days old. Sleep is fine; the meter keeps running through it.

## 1. Start the soak (day 0)

After a log-in, check that the meter is in the menu bar, then:

```sh
cd ~/gitrepos/menubar-meter
sh scripts/checks/soak-start.sh
```

This copies `soak.sh` to `~/Library/Logs/menubar-meter-checks/` and loads a user LaunchAgent,
`~/Library/LaunchAgents/local.menubar-meter.soak.plist`, which runs it now and every ten minutes.
macOS may show a "Background Items Added" notification for it; that is this agent.

Each run appends one line to `~/Library/Logs/menubar-meter-checks/soak.ndjson`: the meter's pid
and start time (`ps -o lstart`), its CPU time (`ps -o time`), and its physical footprint in bytes
(`footprint -f bytes --noCategories`, the `phys_footprint` figure that Activity Monitor's Memory
column shows). To look at it now and then:

```sh
tail -3 ~/Library/Logs/menubar-meter-checks/soak.ndjson
```

A line `{"at":…,"program":null}` means the installed meter wasn't running at that moment.

## 2. The battery-menu check (one day on battery)

Unplug in the morning with the meter running, and use the Mac on battery all day as you normally
would. "All day" is taken as at least **6 hours** on battery (question 1 below). At the end of the
day, **before plugging in**, with the screen unlocked and no menu open:

```sh
cd ~/gitrepos/menubar-meter
swift build -c release --product meter-ax
node scripts/checks/energy-check.js
```

It checks that the Mac is on battery and the installed meter is running, opens the battery menu
in the menu bar (an Accessibility press, as an assistive app presses it; the pointer doesn't
move), reads every text in it, closes it, and writes
`~/Library/Logs/menubar-meter-checks/energy-report.json`. You will see the battery menu open and
close. It prints what the menu listed. If it says the Mac is not on battery, it wrote nothing.

The terminal you run it from needs Accessibility permission (the same one the test harness uses).

The day can fall inside the soak week: being on battery doesn't restart the meter.

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

1. click **Quit Meter** in the installed meter's panel (the harness refuses to run beside it),
   then run the gate (`caffeinate -i npm test`, plugged in, lid open);
2. with the reports present, the 7-day row and the energy scenario bind and run: the 7-day Then
   reads the soak's reading at seven days or later in Activity Monitor's units (megabytes of
   1,048,576 bytes, one decimal, under 50.0 MB); the energy Then reads the battery menu's texts
   and fails if `Meter` is listed under *Apps Using Significant Energy*;
3. if both pass, the suite then fails once on purpose with a "wip entry fully bound" message: that
   is the ratchet asking for the `own-cost` entry to be removed from the register in
   `test/features.test.js`. Removing it leaves the register empty;
4. log out and in (or open `/Applications/Meter.app`) to bring your meter back.

If either report fails its row, the gate shows the readings: the soak's footprint at seven days,
or the apps the battery menu listed.

## Questions put to you

1. Is "all day" on battery at least 6 hours, read from `pmset`'s log of the switch to battery?
2. The soak's seven days count from the running meter's own start time (`ps`), not from when the
   soak started, so a meter running since a log-in two days before the soak starts reports after
   five more days. Is that what you want, or should the week be counted from the soak's start?
