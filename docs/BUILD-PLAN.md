# Build plan — menubar-meter

The reviewed contract is `features/` (signed D116). The feature files bind,
`DESIGN.md` bounds, and `USER-NEEDS.md` explains. Each phase binds one
feature file to real tests under the gherkin-node-test ratchet: a feature leaves the `wip` register only
when every one of its steps is bound and green, `wip` only shrinks, and the
run manifest (`run-manifest.ndjson`) is committed with every phase. Every
phase passes the full aBDD workstack before it merges: the acceptance
criteria (the feature suite), unit tests (`npm run test:unit`) and lint
(`npm run lint` and `npm run scope`).

Phases run in need-weight order where dependencies allow: N0's readout first
(it builds the app and the harness every later phase uses), then N0's history,
N1's list and ending, N5's network and disk, N0's presence, and N2's own cost
last, measured over the finished app.

## Process, every phase

1. **Cold builder** (opus) on branch `pN-<name>`, cut from `master` at the
   phase base, with a self-contained brief. It builds the behaviour, binds the
   phase's scenarios, writes the phase's unit tests, runs its mutation probes,
   runs all three workstack legs (step 5), and commits on the branch.
2. **Two independent cold reviewers** (sonnet), read-only. Neither sees the
   other's review or the builder's report.
   - **Reviewer A — contract and test honesty:** every scenario bound as
     written, every Then far-side, every probe real, nothing on the fence
     built, no feature file, docket, fence, ledger or `[ruled]` DESIGN line
     edited; unit tests present for the phase's logic and not standing in
     for a bound scenario; no lint rule disabled or suppressed to pass.
   - **Reviewer B — the phase's named risk** (each phase names it below).
3. **Head reviewer** (opus) reconciles both reviews against the code and the
   contract into one ranked fix list, runs its own mutation probes, and drops
   false findings with their reasons. Questions for the visionary stop the
   run here and are put to them before the fix round; the builder never
   answers them.
4. **Fix round** (sonnet) on the same branch, a failing test before each fix;
   a fresh verifier (opus) confirms each fix's test failed before and passes
   after. Then the gate.
5. **Gate — the aBDD workstack, three legs, all must exit 0:**
   - **Acceptance criteria:** `caffeinate -i npm test` (build, bundle, the
     feature suite under the `wip` ratchet) with the Mac **plugged in and the
     lid open** (lid closed on battery is Clamshell Sleep and stalls the run;
     check `pmset -g log` before blaming code).
   - **Unit tests:** `npm run test:unit` (Swift Testing through `swift
     test`, from the Command Line Tools) — the builder adds unit tests for
     the logic below the menu bar and the panel (each phase names it
     below), alongside the bound scenarios, never instead of them. Unit
     tests run against `MeterCore` with fixed inputs; they never touch the
     real system or the UI.
   - **Lint:** `npm run lint` — `swift format lint --strict` over `Sources/`
     and `Tests/` (the toolchain's own swift-format 6.3, configuration in
     `.swift-format`) — plus `npm run scope` (strict feature and docket
     lints).
   Exit codes of each leg reported.
6. **Integrate:** merge to `master`, commit the run manifest, store a
   treecontext resume pointer that supersedes the last one, report, and
   **stop for the visionary's go-ahead** before the next phase.

Run each phase with `/build-pipeline <phase>`. Models (checked in
`~/.claude/workflows/build-phase.js`, DEFAULT_MODELS): builder opus, both
reviewers sonnet, head reviewer and verifier opus, fixer sonnet; the gate
inherits the session's model.

## Acceptance bars, every phase

- **Far-side assertions.** Then steps read what macOS itself shows or knows:
  the status item's title and the panel's text through the Accessibility
  tree (System Events), screenshot pixels for the graph, `ps` for which
  tasks run, and independent system probes (`top`, `vm_stat`, `ioreg`,
  `netstat -ib`, `iostat`) or Activity Monitor's own window for the numbers
  the contract pins to Activity Monitor. Never a value the meter wrote about
  itself for the test, never its own log.
- **Givens may inject, Thens may not.** Value-spread outlines ("CPU at
  7.5%") need exact readings, so the meter has a test-only reading source
  the harness feeds (fixed values, a gap for sleep). It is compiled out of
  the installed app, it replaces only the sampler's input, and no Then may
  read it. Each phase that binds an outline through it also binds at least
  one scenario against the real system with an independent probe.
- **Mutation-checking.** For every bound scenario, a deliberately broken app
  turns it red. The builder lists its probes; the head reviewer runs its own.
- **Safety in tests.** Tests end only processes the harness itself spawned,
  identified by pid **and** start time; a test never signals a process it
  did not start. Stand-ins (a fake "Xcode" app with a quit handler, busy
  loops, a task that ignores the polite quit) replace real apps.
- **The fence holds.** Nothing on `OUT-OF-SCOPE.md` is built: no peak values,
  no crowded-bar fallback, no multi-display handling, no settings, no
  update checks, no per-core view, no clean-removal tooling.
- **Unit tests and lint are their own legs.** A unit test pins a rule at its
  boundary (rounding at .5, the five-minute edge, 999.9 KB/s) faster and
  more exactly than a scenario can, but it never counts as binding a
  scenario. Lint is `--strict` and clean: no rule switched off in
  `.swift-format` and no ignore comment added to get a phase through.
- **Never edited by a phase:** `features/*.feature`, `features/DOCKET.md`,
  `features/OUT-OF-SCOPE.md`, `features/USER-NEEDS.md`, `[ruled]` lines in
  `features/DESIGN.md`. A `[chosen]` DESIGN change appends a changelog line.

## Prerequisites (the visionary, once, before P1)

- **Accessibility permission** for the terminal that runs the tests (System
  Settings → Privacy & Security → Accessibility), so the harness can read the
  menu bar and send ⌃⌥⌘M. The first P1 run will prompt; the build stops until
  it is granted.
- No Xcode is needed: the app builds with Swift Package Manager from the
  Command Line Tools (Swift 6.3) and is bundled, ad-hoc signed and packaged by
  script (`pkgbuild`). P1 records this as a `[chosen]` DESIGN changelog line.

## Open questions for the visionary (before the phase that needs them)

These scenarios cannot be fully driven by an automated test on this Mac.
Each needs a ruling on how it counts as bound; until then it stays in `wip`.

- **Q1 (P6) — real logins. Ruled 2026-10-21: the registry plus one manual log-in check (the first option).** "appears by itself at login" (D42) and the
  "at the next login" steps of D83, D84 and D104 need a real log-out and
  log-in. Options: bind them to macOS's own login-item registry (it lists
  the meter as enabled) plus one manual log-in check by the visionary
  recorded in the phase report; or keep the login steps manual only.
- **Q2 (P7) — the 7-day memory row** (D76). Ruled 2026-10-22: the background soak (the first option). Options: a background soak on
  this Mac (plugged in, lid open) that reports after seven days while later
  work continues, the row staying in `wip` until it reports; or the visionary
  reads the meter's Memory in Activity Monitor after a normal week of use.
- **Q3 (P7) — "Apps Using Significant Energy"** (D75). Ruled 2026-10-22: the harness reads the battery menu after an all-day run on battery (the first option). The battery menu is
  readable through Accessibility only while it is open; options: the harness
  opens it and reads it after an all-day run on battery, or the visionary
  checks it by eye at the end of a day.

---

## P1 — The menu bar readout

**Contract:** `menu-bar-readout.feature`, 9 scenarios (6 outlines).
**Rulings:** D89/D92 (the text), D90/D93 (fixed width), D115 (each reading
follows a change within a second), D46 (rounding), D47 (RAM = Activity
Monitor's Memory Used), D48 (CPU = User + System), D49 (GPU = macOS's
reading), D114 (dash after three seconds), D112 (temperature rises under
load), D18 (whole numbers in the bar), D81 (a lost reading is a dash, never a
wrong number), D87 (temperature without admin — a named assumption: if the
builder finds it false, stop and raise it).

**Builds:**
- The SwiftPM package, the app bundle (an agent app, no Dock icon), ad-hoc
  signing, and `npm run build:app`.
- The sampler: one pass a second for CPU, Memory Used, GPU utilization and
  chip temperature, each reading timestamped.
- The status item: monospaced digits, fixed width, numbers right-aligned in
  three-digit slots, the dash per reading.
- The test reading source (Givens only), compiled out of release builds.

**Harness (reused by every later phase):**
- `test/features.test.js` with one `runFeatures` call and the `wip` register
  (all seven features at the start; P1 removes its own).
- `steps/` definers; an Accessibility reader for the status item and the
  panel (System Events through `osascript`, or a small Swift helper).
- A launcher that starts the built app with or without the test source, and
  quits it after each scenario.
- Independent probes: `top -l 2` (CPU), `vm_stat` + `sysctl hw.memsize`
  (Memory Used, Activity Monitor's definition), `ioreg` (GPU); a load
  generator with N busy cores.
- The SwiftPM layout every phase extends: a `MeterCore` library (sampling
  arithmetic, formatting, staleness — no AppKit), the `Meter` app target,
  and a `MeterCoreTests` test target using Swift Testing (`import Testing`).
  Without Xcode, plain `swift test` cannot find the `Testing` module: the
  package declares `platforms: [.macOS(.v14)]` and `npm run test:unit` runs
  `swift test` with the Command Line Tools' framework paths (checked on this
  Mac, Swift 6.3.3, 2026-10-19):
  `-Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker
  $F -Xlinker -rpath -Xlinker $L`, where `$F` is
  `/Library/Developer/CommandLineTools/Library/Developer/Frameworks` and `$L`
  is `/Library/Developer/CommandLineTools/Library/Developer/usr/lib`.
- The three workstack commands every later phase runs: `npm test` (build,
  bundle, suite), `npm run test:unit` (unit tests), `npm run lint` (`swift
  format lint --strict --recursive Sources Tests`, with a committed
  `.swift-format` at the toolchain's defaults) and `npm run scope` (strict
  feature and docket lints). `.gitignore` covers `.build/` and the bundle
  output.

**Unit tests:** the rounding rule at its boundaries (0.4, 0.5, 99.5, 100,
never over 100), the fixed-width text (every slot three digits wide for 0,
7, 42 and 100; the dash in a slot keeps the width), CPU as User + System
from tick deltas, Memory Used from page counts (app + wired + compressed,
cache excluded) divided by 32 GB, the staleness rule (a reading older than
three seconds is a dash; exactly three is not), and the label order.

**Reviewer B's risk:** far-side honesty of the numbers — that Memory Used
matches Activity Monitor's definition (app + wired + compressed, cache
excluded), that the test source can never reach a Then, and that a stale
reading cannot show an old number.

**Register after P1:** `menu-bar-readout` leaves `wip` except D114's network and
disk rows ("A value with no fresh reading turns into a dash"), which show their
dash only in the panel's network and disk lines and so wait for P5. That one
scenario-scoped entry stays in `wip`; P5 closes it. The contract is untouched
(visionary's ruling, P1).
**Expected probes:** a label order swapped, left-aligned numbers, width that
follows the text, rounding down, RAM counting cache, CPU without System, a
GPU figure from the wrong source, a refresh every two seconds, a GPU-only
refresh lag, no dash, a dash for the wrong reading, a frozen temperature.
**Exit:** the feature passes; `npm run test:unit` green; `npm run lint` and
`npm run scope` clean; manifest committed; DESIGN gains changelog lines for the
SwiftPM build, the unit-test and lint tooling, and the reading sources.

## P2 — Recent history

**Contract:** `recent-history.feature`, 4 scenarios (1 outline).
**Rulings:** D50 (the panel and its graph), D53/D113 (five minutes, nothing
older kept), D51 (short history leaves the left empty), D52 (sleep is a gap),
D19/D18 (legend to one decimal), D9 (no peak values — fence).

**Builds:** the panel on click; the combined graph with three distinct-colour
lines on a fixed five-minute axis and a 0–100% scale; the legend; the
five-minute ring with gaps; sleep and wake handling from the system's sleep
notifications.
**Far-side checks:** legend text through Accessibility; line presence and
position from screenshot pixels by line colour; the sleep gap driven by the
system's own sleep and wake notifications through the test source, plus one
real sleep checked by the visionary if they wish.
**Reviewer B's risk:** time — off-by-one at the five-minute edge, clock jumps
on wake, flakiness from wall-clock waits (the harness must drive time through
the test source, never sleep five real minutes).
**Unit tests:** the ring at the five-minute edge (a sample at 300 s kept, at
300.001 s dropped), a gap inserted for sleep and never joined, a clock jump
forward or back on wake, legend rounding to one decimal, the axis fixed at
0–100% whatever the data.
**Register:** `recent-history` leaves `wip`.
**Expected probes:** a six-minute window, a stretched axis, a line joined
across sleep, history cleared on wake, a peak value shown, legend rounding.

## P3 — Heavy tasks

**Contract:** `heavy-tasks.feature`, 13 scenarios (5 outlines).
**Rulings:** D108/D106 (top five by CPU plus GPU and RAM hogs), D109 (the
extra row's bar of over a tenth), D54/D20 (CPU as share of the Mac), D107
(RAM share), D80 (counts against the Mac it runs on), D49 (task GPU =
Activity Monitor's % GPU), D99 (`/System` or other-user tasks are `system`,
no End), D57 (the meter in its own list), D58 (ties alphabetical), D100/D101
(the row under End holds), D110 (no nudging; plain tags only), D59 (Open
Activity Monitor…), D10 (the list below the graph).

**Builds:** the task sampler (while the panel is open), ranking, extra rows,
tags, the `system` mark from user and program path, the hold under the
pointer, the Activity Monitor row, `Quit Meter` row placement (its behaviour
is P6's).
**Far-side checks:** spawned busy tasks with known core counts and memory;
`ps` for owner and path; Activity Monitor's own `% GPU` column for the GPU
row, read through Accessibility; the list read through Accessibility.
**Reviewer B's risk:** safety of the `system` rule — no End ever offered for
a `/System` or other-user task (loginwindow!), path checks that a symlink or
a lookalike name cannot fool; and ranking stability under the hold.
**Unit tests:** ranking (top five by whole-Mac CPU share, ties
alphabetical), the extra GPU and RAM rows at 10.0% vs 10.1%, a hog already
in the top five not repeated, the `system` rule over owner and resolved path
(`/System`, a symlink into `/System`, a lookalike `/Systems`, another
user), the meter's own row as `system`, the hold keeping the row under the
pointer in place.
**Register:** `heavy-tasks` leaves `wip`.
**Expected probes:** per-core CPU, ranking by RAM, an extra row at 9.9%, End
on loginwindow, End on WindowServer, ties by pid, a coloured tag, the hold
ignored, Activity Monitor not opened.

## P4 — Ending tasks

**Contract:** `ending-tasks.feature`, 6 scenarios (1 outline).
**Rulings:** D60 (End: the normal quit, no confirmation, `Ending…`, refill),
D62/D64 (Force Quit only after five seconds), D63 (no double fire), D40 (a
task gone while showing Force Quit), D105 (the state follows the task).
**Builds:** the ender (the app's own quit request for apps, the terminate
signal for windowless tasks; outright kill for Force Quit), state keyed to
pid and start time, the five-second timer.
**Far-side checks:** a stand-in app that records receiving a quit request;
a stand-in task that ignores the polite quit; `ps` before and after.
**Reviewer B's risk:** signalling the wrong process — pid reuse, a row that
moved, a stale state after the task exits; and that a test can never end
anything it did not spawn.
**Unit tests:** the End state machine (End → `Ending…` → gone, or →
Force Quit at five seconds, not before), a second click ignored while
`Ending…`, state keyed to pid and start time (a reused pid gets no state),
the task leaving while Force Quit shows.
**Register:** `ending-tasks` leaves `wip`.
**Expected probes:** a confirmation dialog, Force Quit at three seconds, a
second click that re-sends, the state left on the old row, a kill on End.

## P5 — Network and disk

**Contract:** `network-and-disk.feature`, 1 outline (2 rows).
**Rulings:** D117 amending D95 (auto-scaling bytes, one decimal, in
Activity Monitor's decimal steps of a thousand, matched to its Network and
Disk tabs, loopback and virtual interfaces counted as it counts them), D96 (no history), D114 (whole-line dash).
**Builds:** network and disk rates in the sampler; the two panel lines.
**Far-side checks:** Activity Monitor's Network and Disk tab totals read
through Accessibility, or `netstat -ib` and `iostat` deltas computed by the
harness with Activity Monitor's units; a real transfer (a local file copy, a
loopback download) for a non-idle row.
**Reviewer B's risk:** unit boundaries (999.9 KB/s vs 1.0 MB/s, decimal vs
binary prefixes as Activity Monitor uses them) and counting exactly the
interfaces Activity Monitor counts, loopback included (D117), with no
double counting.
**Unit tests:** byte formatting at every unit step (999 bytes/s, 1.0 KB/s,
999.9 KB/s, 1.0 MB/s, GB/s) with Activity Monitor's prefixes, rates from
counter deltas including a counter reset, the interface set (every
interface Activity Monitor counts, loopback included, per D117).
**Register:** `network-and-disk` leaves `wip`, and so does the scenario-scoped
`menu-bar-readout` entry left by P1 (D114's network and disk rows, bound here
against the panel's two lines).
**Expected probes:** binary prefixes, megabits, a missing unit step, loopback
left out, a step at the wrong value, a half-line dash.

## P6 — Presence

**Contract:** `presence.feature`, 8 scenarios (1 outline).
**Rulings:** D42 (starts at login), D65 (Quit Meter), D104 (a quit stays
quit), D77 (back within ten seconds after a crash, history fresh), D98
(⌃⌥⌘M and Esc), D83 (one-step install), D84 (update by reinstalling; no
update offers).
**Needs first:** the visionary's answer to **Q1**.
**Builds:** login-item registration; a keep-alive that relaunches after a
crash and not after Quit Meter; the global hot key; the installer package
(`pkgbuild`) that installs, registers and opens the app; reinstall over an
older version.
**Far-side checks:** macOS's login-item registry; `ps` after a crash signal
and after Quit; the hot key sent through System Events with Safari in front;
the installer run against a scratch install location where the test allows.
**Reviewer B's risk:** crash vs quit confusion, a relaunch loop, a hot key
that steals a combination another app uses, an installer that leaves two
copies.
**Unit tests:** the keep-alive's decision (relaunch after a crash exit,
never after Quit Meter, a back-off that cannot loop), the hot key's
combination (⌃⌥⌘M, not ⌥⌘M), version comparison for reinstall over an
older copy.
**Register:** `presence` leaves `wip` (login steps per Q1).
**Expected probes:** relaunch after Quit, no relaunch after a crash, ⌥⌘M
instead of ⌃⌥⌘M, history kept across a crash, an update prompt.

## P7 — The meter's own cost

**Contract:** `own-cost.feature`, 3 scenarios (2 outlines).
**Rulings:** D73 (under 1% closed, under 5% open), D76 (under 50 MB after an
hour and after seven days), D75 (never an energy hog).
**Needs first:** the visionary's answers to **Q2** and **Q3**.
**Carried in:** a test pinning the sampler's clock across sleep (a reading spanning a sleep comes out low, never huge; deferred from P5's head review), and pruning ending states for tasks gone while the panel is closed (deferred from P4's head review). Also harden the real D49 Activity Monitor GPU check (test/real-tasks.test.js): in P6's final gate Activity Monitor read 0% for the stand-in in 5 of 8 samples, so the check must wait until Activity Monitor attributes GPU to the stand-in before comparing; and the P5 network bound's margin is thin (closest wrong run 2.8 KB/s outside it).
**Builds:** nothing new unless the measurements fail; then optimisation
inside the lines, never by sampling less often than the contract demands.
**Far-side checks:** `top`/`ps` CPU time of the meter's process over a
minute; Activity Monitor's Memory column for the meter; the battery menu.
**Reviewer B's risk:** measurement honesty — averaging that hides spikes,
measuring a debug build, a test reading source left compiled in.
**Unit tests:** the measurement arithmetic (CPU share from CPU-time deltas
over a minute, peak as well as mean, memory in Activity Monitor's units),
and any optimisation this phase makes, pinned at its boundary.
**Refresh cadence (visionary's ruling, P1):** the readout is composed every 0.5 s
and the CPU counters read every 0.25 s (D115). P7 holds this cost to under 1%
CPU with the panel closed, and may slow the cadence only if D115 (a change
shows within a second) still passes with margin.
**Register:** `own-cost` leaves `wip` (the 7-day row and energy per Q2/Q3);
the register is then empty.
**Exit:** the whole contract passes, all three workstack legs green; a
release build installed on this Mac through the one-step installer.
