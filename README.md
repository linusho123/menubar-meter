# Meter

A small macOS menu bar meter. It shows how hard the Mac is working as one line of text near
Control Center, and opens a panel with five minutes of history and the tasks using the most.

```
CPU  43%  GPU   4%  RAM  56%   61°C
```

Meter is a native Swift agent app (no Dock icon, no window of its own). It needs no network
access, no admin password once installed, and no helper running as root. Its numbers match
Activity Monitor wherever Activity Monitor shows them, and it is built to cost the Mac almost
nothing.

- **Version:** 0.7.0 (`app/Info.plist`)
- **Platform:** macOS 14 or later, Apple silicon. Developed and tested on an M5 MacBook Air
  running macOS 27.2.
- **Status:** all seven build phases are merged. 80 of 82 acceptance scenarios pass. The other
  two can only be checked on the installed meter over real time (see [Status](#status)).

---

## Contents

- [What it does](#what-it-does)
- [What it deliberately does not do](#what-it-deliberately-does-not-do)
- [Install](#install)
- [Using it](#using-it)
- [Where the numbers come from](#where-the-numbers-come-from)
- [The meter's own cost](#the-meters-own-cost)
- [Building from source](#building-from-source)
- [Testing](#testing)
- [How this project is specified and built](#how-this-project-is-specified-and-built)
- [Repository layout](#repository-layout)
- [Known limitations](#known-limitations)
- [Status](#status)
- [Related: Notch Island](#related-notch-island)

---

## What it does

### The menu bar readout

One line of labelled text, refreshed every second:

| Field | What it is | Format |
| --- | --- | --- |
| `CPU` | Whole-Mac CPU load, User + System, as in Activity Monitor's CPU tab | whole percent |
| `GPU` | macOS's own overall GPU utilization | whole percent |
| `RAM` | Activity Monitor's *Memory Used* (reusable cache excluded), as a share of physical memory | whole percent |
| `°C` | The chip temperature (the hottest die sensor) | whole degrees Celsius |

- **One fixed width.** Numbers are right-aligned in three-digit slots with monospaced digits, so
  the item never changes width and the icons beside it never move.
- **Rounded once, to the nearest whole number.** `7.5%` shows as `8%`, `0.4%` as `0%`. The
  panel's one-decimal values are rounded from the same exact reading, never from the menu bar's.
- **Fast.** A change shows within a second. The readout is composed every half second and the CPU
  counters are read every quarter second.
- **A stale value becomes a dash.** If a reading stops arriving for 3 seconds (after a macOS
  update, for example), that field shows `–` (`CPU   –%`, `–°C`) while the others keep updating.
  The meter never shows a wrong or frozen number.

### The panel

Click the menu bar item, or press **⌃⌥⌘M** from any app, and a panel drops down. It is as wide
as the menu bar item and hangs from its left edge. From top to bottom:

1. **A five-minute graph.** One combined graph with a line each for CPU (red), GPU (green) and
   RAM (blue). The scale is fixed at 0–100% and the time axis runs from `5 min ago` to `now`.
   Under it, a legend gives the current values to one decimal place:
   `CPU 100.0%  GPU 0.0%  RAM 93.0%`.
   - Anything older than five minutes is not shown and not kept.
   - If the meter has run less than five minutes, the left of the graph stays empty. The axis
     does not stretch.
   - Time the Mac slept is a gap in the lines. The lines are not joined across it.
2. **Network and disk.** The whole Mac's current rates, as Activity Monitor's Network and Disk
   tabs show them:
   ```
   Net ↓ 112.4 MB/s ↑ 300.0 KB/s
   Disk R 210.0 MB/s W 1.2 GB/s
   ```
   Units are decimal bytes (1 KB = 1000 bytes) and step up at 1000, as Activity Monitor's do
   (`999.9 KB/s`, then `1.0 MB/s`). These two lines keep no history.
3. **Heavy tasks.** A list with CPU, GPU and RAM columns. Each value is that task's share of the
   *whole Mac* to one decimal place, so one task using every core reads `100.0%`, not
   Activity Monitor's per-core `1000%`.
   - The top **five by CPU**, with ties broken alphabetically.
   - Plus the biggest **GPU** user and the biggest **RAM** user, each only if it is outside the
     five and uses more than a tenth of the GPU or of memory. These extra rows are tagged `GPU`
     or `RAM`.
   - Each task you can end has an **End** button (see below).
   - Tasks that are part of macOS, or that are not yours, are tagged `system` and have no
     button. The meter's own row is one of these.
   - If the pointer rests on a row's End button, that row stays put while the list re-sorts
     around it. A click always acts on the task you were looking at.
4. **`Open Activity Monitor…`** for anything beyond the list.
5. **`Quit Meter`.**

The panel is drawn in Notch Island's style: an always-dark card, soft tiles, white text at a few
opacities, grey pill buttons. Colour appears only on the graph lines and their legend labels.

### Ending a task

Ending a task is always your action. The meter never ends one by itself, and never colours,
highlights, warns about or prompts you about a task, however long it has been hogging the Mac.

- **End** sends the same quit request the app's own Quit menu sends (the `aevt/quit` Apple event
  for apps, `SIGTERM` for windowless tasks). It does not ask you to confirm first, so the app can
  still ask to save.
- The button reads **Ending…** until the task is gone. Clicking it again does nothing.
- If the task is still running **5 seconds** later, the button becomes **Force Quit**, which kills
  it outright (`SIGKILL`). This is sent once and never retried.
- The ending state belongs to the task (process id plus start time), not to the row. If the task
  moves to another row, the state goes with it. It also survives closing and reopening the
  panel.
- Before anything is sent, the meter reads the task afresh from the kernel. If the process id
  now belongs to a different task, nothing is sent.

**Which tasks are `system`.** A task gets no End button if any of these is true:

- it is the meter itself
- it does not run as you
- its program is in `/System`, `/usr/libexec`, `/usr/sbin` or `/sbin`
- the system names no program for it

Folders are matched by whole name, so `/Systems` is not `/System`. The one exception is the
apps in Apple's App cryptex: Safari and the helpers inside `Safari.app` keep their End button.
Programs in `/bin`, `/usr/bin`, `/Applications`, `~/.nvm` and so on keep theirs.

### Presence

- **Starts at every login** by itself.
- **Comes back after a crash** within about 10 seconds, with an empty graph. If it crashes 5
  times within 2 minutes, it stays down until you open it or log in again.
- **`Quit Meter` removes it until the next login.** Quitting from Activity Monitor or with `kill`
  (`SIGTERM`) counts as a quit too, not a crash.
- **⌃⌥⌘M** opens and closes the panel from any app, with no Accessibility or Input Monitoring
  permission needed. **Esc** closes the panel however it was opened.
- **One install step** puts it in the menu bar, with nothing to configure. Installing a newer
  version the same way replaces the old one. The meter never offers to update itself.

---

## What it deliberately does not do

These were considered and declined while the project was scoped. The full list, with reasons, is
in [`features/OUT-OF-SCOPE.md`](features/OUT-OF-SCOPE.md).

- No peak values, alerts or long-term history. Five minutes, in memory only, gone on quit.
- No per-core CPU breakdown.
- No settings: no refresh interval, no units, no start-at-login switch.
- No special behaviour when the menu bar is too crowded beside the notch. The item keeps its
  width, and macOS may hide it.
- No multi-display placement logic. macOS decides.
- No self-update, and no uninstaller ([manual removal](#uninstall) is below).
- No App Store build.

---

## Install

The install step is a standard macOS installer package, built from source (there is no
prebuilt download):

```sh
npm run build:app     # or: sh scripts/build-app.sh — builds build/Meter.app and build/Meter.pkg
open build/Meter.pkg
```

Building needs only the Command Line Tools. `npm install` is not required, because the Node
packages are used only for the tests and lints.

The installer asks for an administrator password. It puts `Meter.app` in `/Applications`, then
opens it as the logged-in user. On its first run the meter writes its login job and appears in
the menu bar straight away.

**Upgrading.** Build and open the newer package. It replaces the app in place and restarts the
running meter into the new version.

### What gets installed

| Path | What |
| --- | --- |
| `/Applications/Meter.app` | The app (bundle id `local.menubar-meter.Meter`), ad-hoc signed |
| `~/Library/LaunchAgents/local.menubar-meter.Meter.plist` | Your login job, written by the meter when it is opened |
| `$TMPDIR` | A small start-time record for the crash back-off, cleared at restart |

Nothing else is written. History lives only in memory.

The login job is a plain user LaunchAgent (`RunAtLoad`, `KeepAlive` unless the exit was
successful, a 5-second throttle, Aqua sessions only). System Settings → General → Login Items
lists it as a legacy agent. `SMAppService` was tried first and dropped: after a reinstall,
launchd refused to start the ad-hoc-signed bundled agent.

### Uninstall

Removal is not a scoped feature. To remove the meter by hand:

```sh
launchctl bootout gui/$(id -u)/local.menubar-meter.Meter     # stops it and unloads the job
rm ~/Library/LaunchAgents/local.menubar-meter.Meter.plist
sudo rm -rf /Applications/Meter.app
sudo pkgutil --forget local.menubar-meter.Meter.pkg
```

---

## Using it

| To | Do |
| --- | --- |
| Read the load | Look at the menu bar |
| See the last five minutes and the heavy tasks | Click the item, or press ⌃⌥⌘M |
| Close the panel | Click the item again, click elsewhere, press ⌃⌥⌘M, or press Esc |
| Ask a task to quit | Click **End** on its row |
| Kill a task that ignored End | Wait for **Force Quit** (5 s), then click it |
| See every task | **Open Activity Monitor…** |
| Remove the meter until next login | **Quit Meter** |

---

## Where the numbers come from

Every number has an independent reference where macOS offers one, and the acceptance tests
check the meter against it.

| Reading | Source in the meter | Checked against |
| --- | --- | --- |
| CPU (whole Mac) | `host_statistics` `HOST_CPU_LOAD_INFO` ticks: user + nice + system over all ticks between two reads | Activity Monitor CPU tab, `top` |
| RAM (Memory Used) | `HOST_VM_INFO64` pages: anonymous − purgeable + wired + compressor, over `hw.memsize` | Activity Monitor Memory Used, `vm_stat` |
| GPU (whole Mac) | The `IOAccelerator` service's `PerformanceStatistics` → *Device Utilization %* | macOS's own reading (Activity Monitor has only a graph with no figure) |
| Chip temperature | The hottest `PMU… tdie` die sensor published as an HID temperature service, readable without admin rights | Nothing. macOS shows no temperature anywhere, so the only check is that it rises under load |
| Network | Every interface's link-level byte counters (`NET_RT_IFLIST2`, as `netstat -ib`), loopback and virtual interfaces **included**, because Activity Monitor counts them | Activity Monitor Network tab |
| Disk | Every block storage driver's `Bytes (Read)` / `Bytes (Write)`. Disk images count twice, as in Activity Monitor | Activity Monitor Disk tab, `iostat` |
| Task CPU | Process CPU time (user + system) over `hw.ncpu` cores | `ps`, Activity Monitor |
| Task RAM | Physical footprint (Activity Monitor's Memory column) over `hw.memsize` | Activity Monitor Memory column |
| Task GPU | The task's share of all GPU clients' time over the refresh, times Device Utilization % | Activity Monitor `% GPU`, which the meter matches within about 2 points with the panel closed. The test allows 20 |

Per-task sampling runs only while the panel is open. The clock is `CLOCK_MONOTONIC`, which keeps
counting while the Mac sleeps, so sleep shows as a gap rather than being squeezed out.

---

## The meter's own cost

The meter is part of the load it shows, so its own cost has fixed limits in the contract. They
are measured from outside the meter, on the release build only, and never from its own counters.

| Limit | Measured with |
| --- | --- |
| CPU **under 1%** of the whole Mac over a minute, panel closed (the mean *and* the busiest second) | `ps -o time=` once a second |
| CPU **under 5%**, panel open | same |
| Memory **under 50 MB** after 1 hour, and after 7 days without a restart | `footprint` (`phys_footprint`, Activity Monitor's Memory column) |
| Never listed under *Apps Using Significant Energy* after a day on battery | The battery menu, read through Accessibility |

Typical figures on the development Mac: about 1.5 ms of CPU per second, about 17 MB of memory
with the panel open. The graph is painted into a reusable bitmap rather than in `draw(_:)`.
Drawing it directly cost about 45 MB of graphics memory and pushed the meter over the line.

---

## Building from source

### Requirements

- macOS 14 or later on Apple silicon
- The **Command Line Tools** (`xcode-select --install`), with Swift 6.x. **Xcode is not
  needed**, and the project has no Xcode project file.
- **Node.js** (a current LTS) and `npm install`, for the acceptance tests and the spec lints.
  The dev dependencies are `gherkin-node-test` and `@bingh/docketry`. If docketry is not on the
  registry yet, `npm link` it from a local checkout.

### Commands

| Command | What it does |
| --- | --- |
| `npm run build:app` | Builds everything with SwiftPM and bundles it (below) |
| `npm test` | `build:app`, then the full acceptance suite |
| `npm run test:unit` | Swift Testing unit tests against `MeterCore`, `MeterClock` and `OwnCost` |
| `npm run lint` | `swift format lint --strict` over `Sources/` and `Tests/` (config in `.swift-format`) |
| `npm run scope` | Strict Gherkin lint of every feature file, plus the strict docket lint |

`npm run build:app` produces:

| Output | What |
| --- | --- |
| `build/Meter.app` | The release app. No test code compiled in |
| `build/Meter.pkg` | The installer for it |
| `build/test/Meter.app` | The test build, with the test reading source compiled in (`-DMETER_TEST_SOURCE`). Never installed |
| `build/check/Meter-0.0.9.pkg` | An older release package for the manual log-in check |
| `build/test/pkg/Meter-0.0.{1,2}.pkg` | The harness's own packages under a separate bundle id, installed only into `~/Applications` |
| `build/test/standins/{Xcode,Front}.app` | Stand-in apps the harness ends and puts in front, so your real apps are never touched |
| `.build/release/meter-*` | The harness helpers |

The build scripts set `umask 022` and normalise file modes before packaging, so the installed
app is world-executable whatever your shell's umask is.

---

## Testing

There are three layers. All of them must exit 0 before a phase merges.

### 1. Acceptance criteria: `npm test`

Every scenario in `features/*.feature` runs as a real test through
[gherkin-node-test](https://www.npmjs.com/package/gherkin-node-test). The steps live in
`test/steps/`, and helpers for reading macOS live in `test/support/`.

- **Then steps read what macOS shows.** The status item's title and the panel's text come from
  the Accessibility tree. The graph is checked from screenshot pixels. The tests use `ps` for
  which tasks are running, and `top`, `vm_stat`, `ioreg`, `netstat -ib`, `iostat` or Activity
  Monitor's own window for the numbers. A Then never reads a value the meter wrote about itself.
- **Givens may inject exact values.** Scenarios like "CPU at 7.5%" need exact readings, so the
  test build has a reading source the harness feeds. It replaces only the sampler's input, no
  Then may read it, and it is compiled out of the release app. Every phase that uses it also
  binds at least one scenario against the real system.
- **The `wip` ratchet.** `test/features.test.js` holds a `wip` register of scenarios not yet
  bound. It can only shrink. A run writes `run-manifest.ndjson`, which is committed with each
  phase.

**Before running:**

- Give your terminal **Accessibility** permission (System Settings → Privacy & Security →
  Accessibility). The harness reads the menu bar and sends ⌃⌥⌘M.
- Keep the Mac **plugged in with the lid open**. A closed lid on battery is clamshell sleep and
  stalls the run. Run it as `caffeinate -i npm test`.
- The harness runs its own meter and refuses to run beside one it did not start. Quit the
  installed meter first, and don't run the suite while the 7-day soak is going.
- The presence scenarios run the real `installer` with the harness's own packages into
  `~/Applications`, and clean up after every scenario.

### 2. Unit tests: `npm run test:unit`

Swift Testing through `swift test`. The script adds the Command Line Tools' framework paths
(without Xcode, `swift test` cannot find the Testing module otherwise). The tests cover the logic
below the UI with fixed inputs: rounding, staleness, history trimming and gaps, the heavy-task
ranking and extra rows, the `system` rule, the ending state machine, the pointer hold, byte-rate
formatting, the graph bitmap's sizing, and the own-cost arithmetic.

### 3. Lint: `npm run lint` and `npm run scope`

`swift format` at strict, plus the spec lints (`gherkin-node-test`'s strict feature lint and
`docketry lint --strict`).

### Checks that run outside the suite

Some rows can only be checked on the installed meter, over real time:

- **`docs/P6-LOGIN-CHECK.md`** covers one real log-out and log-in, done by hand. It confirms
  that install from nothing, upgrade over an older copy, `Quit Meter`, and starting at the next
  login all behave. `scripts/login-check.sh` records what macOS shows at each step and changes
  nothing.
- **`docs/P7-SOAK-AND-ENERGY.md`** covers the 7-day memory soak and the battery-menu check.
  - The soak is a user LaunchAgent (`scripts/checks/soak-start.sh` and `soak-stop.sh`). Every
    10 minutes it appends `ps` and `footprint` readings of `/Applications/Meter.app` to
    `~/Library/Logs/menubar-meter-checks/soak.ndjson`. Once one meter process has been running
    for 7 days, it writes a report and stops.
  - Run `node scripts/checks/energy-check.js` at the end of a day of at least 6 awake hours on
    battery. It reads the battery menu through Accessibility.

---

## How this project is specified and built

Meter was built with an acceptance-driven process (aBDD). The behaviour was agreed in a scoping
interview *before* any code was written. Each phase was then built against that agreement and
reviewed by independent agents. The documents in `features/` are the contract:

| File | Role |
| --- | --- |
| `features/*.feature` | **The contract.** Gherkin scenarios, each tagged with the ruling that decided it (`@D60`). At build time only these bind |
| `features/DOCKET.md` | Every ruling from the interview and since, dated and numbered (`N…` needs, `D…` decisions), in the [docketry](https://www.npmjs.com/package/@bingh/docketry) grammar |
| `features/USER-NEEDS.md` | Why the meter exists, need by need, and which scenarios cover each one |
| `features/OUT-OF-SCOPE.md` | What was declined, deferred or assumed, and the roads not taken |
| `features/DESIGN.md` | The orienting design document: principles, shape, constraints, and a changelog of every design choice with its reason |
| `docs/BUILD-PLAN.md` | The seven phases, one per feature file, with each phase's risk and review brief |

Each phase went through the same steps: a cold builder, two independent reviewers (one checking
contract and test honesty, one checking the phase's named risk), a head reviewer, a
failing-test-first fix round, a verifier, and the three-layer gate. The phases were:

| Phase | Feature | Need |
| --- | --- | --- |
| P1 | `menu-bar-readout.feature` | see the load at a glance |
| P2 | `recent-history.feature` | the five-minute graph |
| P3 | `heavy-tasks.feature` | find what's hogging the Mac |
| P4 | `ending-tasks.feature` | get the machine back |
| P5 | `network-and-disk.feature` | network, disk |
| P6 | `presence.feature` | always there |
| P7 | `own-cost.feature` | costs almost nothing |

**Changing behaviour** means changing the contract first. A feature file, the docket, the fence
or a `[ruled]` design line is never edited to make a test pass. A conflict between code and spec
is raised as a question.

---

## Repository layout

```
Package.swift            SwiftPM manifest (swift-tools 6.0, macOS 14)
app/
  Info.plist             bundle metadata (LSUIElement agent app, version)
  pkg-scripts/postinstall  opens the newly installed copy as the console user
Sources/
  MeterCore/             arithmetic, formatting, staleness, ranking, ending state; no AppKit
  MeterClock/            the meter's clock (CLOCK_MONOTONIC), separate so a test can pin it
  Meter/                 the app: real inputs, status item, panel, hot keys, login job
  OwnCost/               the harness's own-cost arithmetic (never in the app)
  meter-ax/              harness helper: reads the menu bar and panel through Accessibility
  meter-neighbor/        harness helper: a neighbouring status item, to prove the width holds
  meter-gpu-load/        harness helper: a controllable GPU load
  meter-standin/         harness helper: stand-in apps that record the quit they receive
  meter-cost/            harness helper: measures the meter's CPU and memory from outside
Tests/                   Swift Testing unit tests (MeterCore, MeterClock, OwnCost)
features/                the contract (see above)
docs/                    build plan and the manual and long-running check procedures
scripts/
  build-app.sh           build, bundle, sign, package
  build-pkg.sh           pkgbuild + productbuild for the one-step installer
  test-unit.sh           swift test with the Command Line Tools' Testing paths
  lint-scope.js          npm run scope
  login-check.sh         read-only state dump for the manual log-in check
  checks/                the 7-day soak and the battery-menu energy check
test/
  features.test.js       runs every feature file under the wip ratchet
  steps/                 step definitions, one file per feature
  support/               Accessibility, process, rate and pixel readers; stand-ins; probes
  fixtures/              recorded battery-menu trees for the energy check's own tests
  *.test.js              tests of the harness itself (judges, checks, packaging)
run-manifest.ndjson      the last gate run's per-scenario results
```

---

## Known limitations

- **Other users' tasks don't appear in the real list.** An app running as you cannot read
  another user's tasks' CPU or memory. `ps` and `top` do it as setuid root, and Activity Monitor
  through a system service. So `WindowServer`, `kernel_task` and similar never show in the list.
  The `system` rule for them is built and tested through the test reading source.
- **Temperature can't be checked independently.** macOS shows no chip temperature anywhere. The
  value is the hottest die sensor, and the test only checks that it rises under load.
- **The whole-Mac GPU figure can't be matched number for number.** Activity Monitor shows only a
  graph for it. Per-task GPU with the panel open reads up to about 16 points below Activity
  Monitor's `% GPU`.
- **A crowded menu bar can hide the item behind the notch.** The meter assumes there is room for
  its full width (about 294 pt at the standard menu bar font).
- **The project assumes a single-user Mac.** The `system` rule protects other users' tasks, but
  nothing else was designed for shared Macs.
- **The app is ad-hoc signed.** It is not notarized, so it is meant for building and installing
  on your own Mac.

---

## Status

All seven phases are merged into `master`. The last gate's `run-manifest.ndjson` shows:

- **80 scenarios passing**
- **2 in `wip`**, both from `own-cost.feature`, by design:
  - *The meter's memory stays under its line* (the **7 days** row). This binds once the
    background soak reports one meter process that has run 7 days.
  - *The meter is never flagged as an energy hog*. This binds once the battery menu has been read
    after a full day on battery.

Both are waiting on real time, not on code. Their procedures are in
[`docs/P7-SOAK-AND-ENERGY.md`](docs/P7-SOAK-AND-ENERGY.md). The 1-hour memory row runs in the
normal suite and passes.

The most recent change since P7 restyled the panel to match Notch Island and made it exactly as
wide as the menu bar item.

---

## Related: Notch Island

[`notch-island`](../notch-island) is a sibling project by the same author, built the same way. It
turns the MacBook Air's camera notch into a music panel and a shelf. The two are designed to sit
side by side:

- Notch Island keeps everything right of the notch free for this meter.
- Notch Island's tests check that the meter's status item stays clear of the notch.
- Meter's panel uses Notch Island's look.
