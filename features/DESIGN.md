# DESIGN — menubar-meter

The orienting document for the agent that builds this. It sits at the
altitude where a statement survives its mechanism being swapped; anything
lower belongs in the builder's own notes. The feature files in this
directory bind; this document explains and bounds. A conflict between the
two is raised as a question, never resolved by editing one side alone.

**Edit doctrine.** Nobody edits this file outside a discussion: the human
and the agent iterate, the agent holds the pen, and every change appends
one Changelog line naming the ruling that sanctioned it. Changing a
`ruled` constraint is a reversal only the visionary can make; a `chosen`
one still takes a discussion, at a lower bar.

The visionary declined the design electives ("make it so"), so every
technology choice below is the agent's own and tagged `chosen`.

## Principles

- The meter is a glance first: one line of labeled text in the menu bar near Control Center, whole-number percentages, then the chip temperature. [ruled: N3]
- Ending a task is always the visionary's own act; the meter never ends a task on its own [ruled: D2], and never colours, highlights, warns or prompts about one, its only row words being the plain `GPU`, `RAM` and `system` tags [ruled: D110].
- A macOS update asks nothing of the visionary; a reading that stops arriving shows as a dash, never as a wrong or frozen number. [ruled: D81]
- Every number has a far-side witness wherever macOS offers one: CPU, RAM, network and disk agree with Activity Monitor; GPU is macOS's own utilization reading; per-task GPU is Activity Monitor's `% GPU`. Temperature alone has none, by construction. [chosen]
- The meter is cheap by design, because its own cost is part of the contract (own-cost.feature): one sampling pass shared by the menu bar and the panel (the readout composed every half second, the CPU counters read every quarter second, so a change shows within a second, D115), and per-task sampling only while the panel is open. [chosen]
- History lives only in memory, five minutes deep, and is gone on quit, crash or restart; nothing is written to disk. [chosen]
- No network access, no admin password, no helper running as root. [chosen]

## Shape

- A native macOS menu bar app (an agent app with no Dock icon), written in Swift with AppKit for the status item and the panel, SwiftUI where it fits inside the panel. [chosen]
- **Sampler.** Every half second (CPU counters every quarter second) it reads whole-Mac CPU load (User plus System, as Activity Monitor counts it), Memory Used (Activity Monitor's definition, cache excluded), overall GPU utilization (the figure IOKit's accelerator statistics report), chip temperature, and network and disk rates. Each reading carries its own timestamp so a stale one can turn into a dash after three seconds. [chosen]
- **Task sampler.** While the panel is open, per-task CPU (as a share of the whole Mac's cores), resident memory (as a share of physical memory) and GPU, plus each task's user and program path, which decide the `system` mark. [chosen]
- **History.** A fixed five-minute ring of samples for CPU, GPU and RAM, with gaps where no samples exist (before launch, while asleep). [chosen]
- **Status item.** A monospaced-digit line at a fixed width, numbers right-aligned in three-digit slots. [chosen]
- **Panel.** The combined graph and legend, the network and disk lines, the heavy-task list with its End, Ending… and Force Quit states, then `Open Activity Monitor…` and `Quit Meter`. [chosen]
- **Ender.** End sends the normal quit request a Quit menu would (a polite terminate for apps, the terminate signal for windowless tasks); Force Quit kills outright. The ending state is keyed to the task's process id, never to a row. [chosen]
- **Presence.** Registered as a login item; relaunched by the system's own keep-alive after a crash but not after Quit Meter; a global hot key for Control-Option-Command-M. [chosen]
- **Install.** One step: a single installer that puts the app in Applications, registers it to start at login and opens it, so the item appears at once; a newer version installs the same way over the old one. [chosen]

## Constraints the build must not cross

- The ranking, the extra-row bar, the decimals and the rounding are the feature files', not the builder's to tune. [chosen]
- No task whose program lives in `/System`, or which does not run as the visionary, ever gets an End button. [ruled: D99]
- The meter's own CPU, memory and energy lines are acceptance criteria, measured from outside the meter (Activity Monitor, `ps`, the battery menu), never from its own counters. [chosen]
- The design tier (`features/design/`), if the build writes one, holds platform acceptance criteria such as sampling and parsing; it never edits `features/`. [chosen]

## Changelog

- 2026-10-18 — initial draft (scope interview; docket D1–D113, N0–N5; electives offered and declined, so no ruled technology).
- 2026-10-18 — post-draft pass, drafting fixes before the cold read: the no-nudge principle now cites D110 beside D2, which alone did not carry it; the system-task constraint is ruled by D99, not chosen; the install is one installer step, as D83 rules, not a copy and an open.
- 2026-10-19 — P1, chosen: the app builds with Swift Package Manager from the Command Line Tools (Swift 6.3, no Xcode): a `MeterCore` library (arithmetic, formatting, staleness; no AppKit), the `Meter` agent app, bundled and ad-hoc signed by `scripts/build-app.sh` (`npm run build:app`) as `build/Meter.app`; a test build with the test reading source compiled in (`-DMETER_TEST_SOURCE`) goes to `build/test/Meter.app` and is never installed (build plan P1).
- 2026-10-19 — P1, chosen: the workstack's other two legs are unit tests in Swift Testing against `MeterCore` with fixed inputs (`npm run test:unit`, `swift test` with the Command Line Tools' framework paths) and lint by the toolchain's swift-format 6.3 at its default configuration, `--strict` (`npm run lint`), beside `npm run scope` (build plan P1).
- 2026-10-19 — P1, chosen: the reading sources. CPU is the kernel's whole-Mac tick counters (`HOST_CPU_LOAD_INFO`), User (with nice) plus System over the ticks between two reads; Memory Used is the kernel's page counts (`HOST_VM_INFO64`), anonymous less purgeable plus wired plus compressor, over `hw.memsize`; GPU is the `IOAccelerator` service's `PerformanceStatistics` "Device Utilization %"; the chip temperature is the hottest of the `PMU… tdie` die sensors macOS publishes as HID temperature services, read as the signed-in user without an admin password, so the D87 assumption holds on this Mac (D47, D48, D49, D87).
- 2026-10-19 — P1, chosen, raised as a question with the phase report: the readout is composed every half second and the CPU counters read every quarter second, because a once-a-second pass cannot show every change within a second (D115): a change waits up to one pass to be read, and CPU, a load over an interval, one interval more. The principle's "one sampling pass a second" is not reworded here; the visionary decides (D115).
- 2026-10-19 — P1, chosen, ruled by the visionary: the sampling cadence is a 0.5 s readout and 0.25 s CPU counters, so every change shows within a second (D115); the principle (line 24) and the Sampler (line 31) are reworded to say so, replacing the question raised in the entry above. P7 holds the cadence to under 1% CPU closed and may slow it only if D115 still passes with margin.
- 2026-10-19 — P2, chosen: readings are kept as exact shares (busy ticks of all ticks, bytes of physical memory, the GPU's percent), so the menu bar's whole number and the panel's one decimal are each rounded once from the same exact value, never one from the other (D46, D19).
- 2026-10-19 — P2, chosen: the meter's clock is the system's continuous monotonic clock (`CLOCK_MONOTONIC`, which counts on while the Mac sleeps), for the history and for staleness alike; the history is an in-memory list of one sample per pass, trimmed every pass to samples at most 300 s old; the system's own sleep and wake notifications (`NSWorkspace` will-sleep and did-wake) stop recording and break the lines, which are never joined across the gap; on waking, the next CPU load is measured afresh (D52, D53, D113).
- 2026-10-19 — P2, chosen: the panel is a borderless, non-activating panel that drops down under the item on a click and closes on a second click or a click elsewhere; the graph draws CPU, GPU and RAM in the system red, green and blue on a fixed 0%–100% scale labelled `0%` and `100%` and a fixed time axis labelled `5 min ago` and `now`; the legend's labels carry their lines' colours (D50, D51, D19).
- 2026-10-19 — P2, chosen: the test reading source can also give the meter a past — stretches of readings, and stretches the Mac slept through — which it drives at launch through the meter's own loop on the past's own clock, posting the system's sleep and wake notifications for a sleep, so the history scenarios need no real five-minute wait; like the rest of the test source it is compiled out of the release app (build plan P2).
