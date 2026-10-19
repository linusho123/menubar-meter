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
- The meter is cheap by design, because its own cost is part of the contract (own-cost.feature): one sampling pass a second shared by the menu bar and the panel, and per-task sampling only while the panel is open. [chosen]
- History lives only in memory, five minutes deep, and is gone on quit, crash or restart; nothing is written to disk. [chosen]
- No network access, no admin password, no helper running as root. [chosen]

## Shape

- A native macOS menu bar app (an agent app with no Dock icon), written in Swift with AppKit for the status item and the panel, SwiftUI where it fits inside the panel. [chosen]
- **Sampler.** Once a second it reads whole-Mac CPU load (User plus System, as Activity Monitor counts it), Memory Used (Activity Monitor's definition, cache excluded), overall GPU utilization (the figure IOKit's accelerator statistics report), chip temperature, and network and disk rates. Each reading carries its own timestamp so a stale one can turn into a dash after three seconds. [chosen]
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
- 2026-10-19 — P1 build, `chosen`, under the technology choices the visionary left to the agent (electives declined): the app builds with Swift Package Manager from the Command Line Tools (Swift 6.3), no Xcode project, and `npm run build:app` bundles it as an agent app (no Dock icon) and signs it ad hoc; the test-only reading source that Givens feed is compiled in only with `-DMETER_TEST_SOURCE`, never into the installed build, and replaces only the sampler's raw inputs.
- 2026-10-19 — P1 build, `chosen`, the reading sources behind D47, D48, D49 and D87: CPU is the kernel's host CPU-load ticks, User (nice included) plus System over all ticks since the last pass; Memory Used is `vm_statistics64` App Memory (anonymous less purgeable pages) plus Wired plus Compressed plus, on Macs with a memory-tagging region, that region and its tag-holding pages, which Activity Monitor counts in Memory Used on macOS 26 on this M5 though it shows them in none of the three lines (checked against Activity Monitor's own window); GPU is IOAccelerator's `Device Utilization %`; the chip temperature is the hottest `PMU tdie` sensor of macOS's HID event system, read as the user with no admin password, so the named assumption chip-temperature-readable holds on this Mac.
