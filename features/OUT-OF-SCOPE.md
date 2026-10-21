# Out of scope

What was declined, deferred or assumed during the scoping interview for
menubar-meter, so a later reader finds a decision here instead of an open
question. Each entry ends with the docket ids that ruled it and the date it
was ratified.

## Declined

- **peak-values.** The history panel shows no peak number for any metric; the combined graph and the current values are all it shows. Choosing the one combined graph gave that up, knowingly. (D9, 2026-10-18)
- **crowded-menu-bar.** What happens when the built-in screen's menu bar is too crowded for the meter beside the notch is not the meter's problem: it keeps its fixed width and makes no special move. Reaffirmed in the adversarial pass once the item grew to four fields; see the named assumption room-in-the-menu-bar. (D32, D102, 2026-10-18)
- **multiple-displays.** Where the meter appears when more than one display is attached is left to whatever macOS does by default. (D33, 2026-10-18)
- **usability.** No provision beyond what is ruled for readability on light or dark menu bars, keyboard use of the panel, or colour-blind viewing. Checklist category, left unticked. (D67, 2026-10-18)
- **availability.** Nothing beyond starting at login and coming back after a crash about what is acceptable when the meter is missing at the moment it is wanted. Checklist category, left unticked. (D68, 2026-10-18)
- **security.** Nothing beyond the single-user assumption and the system-task rule about who must never use the meter's power to end tasks, or what permissions it asks for. Checklist category, left unticked. (D69, 2026-10-18)
- **ops-burden.** No commitment about how long the meter runs unattended or what upkeep it may ask for. Checklist category, left unticked. (D70, 2026-10-18)
- **diagnosability.** Nothing about what can be found out when the meter shows something odd or breaks, beyond the dash for a stale value. Checklist category, left unticked. (D71, 2026-10-18)
- **compliance.** No outside rules or standards, App Store rules included. Checklist category, left unticked. (D72, 2026-10-18)
- **clean-removal.** Removing the meter so nothing is left behind at login or on disk is not scoped. Lifecycle item, left unticked. (D82, 2026-10-18)
- **per-core-breakdown.** No per-core view of CPU use. Offered from the interviewer's priors at the domain question and left unticked. (D111, 2026-10-18)

## Deferred

None.

## Named assumptions

- **single-user-mac.** Only the visionary uses this Mac; nobody else has a login on it or shares theirs. Reopens if a second person gets a login on this Mac or starts using the visionary's. (D3, 2026-10-18)
- **gpu-history-matches-macos-reading.** Activity Monitor's GPU History graph plots the same overall GPU utilization macOS reports and the meter shows, so the meter's GPU value can be checked by eye against that graph. Reopens if the meter's GPU value and the GPU History graph visibly disagree on this Mac. (D29, 2026-10-18)
- **chip-temperature-readable.** This Mac lets the meter, running as the visionary, read its chip temperature without an admin password. Reopens if the meter cannot read the chip temperature on this Mac without one. (D87, 2026-10-18)
- **room-in-the-menu-bar.** The visionary keeps enough room on the built-in screen's menu bar for the meter's full width. Reopens if the visionary finds the meter missing from the built-in screen's menu bar. (D103, 2026-10-18)

## Out of reach by construction

- **exact-whole-gpu-check.** Activity Monitor shows the whole Mac's GPU only as a graph with no figure, so the menu bar's GPU value cannot be matched to it number for number; it is macOS's own reading, checked by eye. (D49, 2026-10-18)
- **temperature-cross-check.** macOS shows no chip temperature anywhere, so the °C value has no independent witness; rising under load is its whole check. (D112, D87, 2026-10-18)

## Roads not taken

- **tracking.** Rejected: live numbers only; a long history kept over hours or days and surviving restarts; peaks and alerts without history. Recent history won. (D1, D7, D66, D113, 2026-10-18)
- **who-ends.** Rejected: the app flagging a runaway task for the visionary to decide; the app ending tasks itself by a rule. The visionary ends every task. (D2, 2026-10-18)
- **presence.** Rejected: opening it once until quit, gone after a restart; a start-at-login switch. It starts at every login. (D4, D42, 2026-10-18)
- **readout-shape.** Rejected: single-letter labels; stacked tiny label-over-number columns; mini fill bars. Labeled text won. (D5, D31, D43, D89, 2026-10-18)
- **refresh.** Rejected: every two seconds; every five seconds; an interval setting. Every second won. (D6, D45, D79, 2026-10-18)
- **history-look.** Rejected: three stacked graphs with current and peak values; the graphs with the task list in one block. One combined graph won. (D8, D19, D50, 2026-10-18)
- **task-list-place.** Rejected: a separate "Heavy tasks" row opening the list beside the panel; History and Tasks tabs. Below the graph won. (D10, 2026-10-18)
- **task-cpu-count.** Rejected: Activity Monitor's per-core count, up to a thousand percent on this Mac. Share of the whole Mac won. (D11, D20, D54, 2026-10-18)
- **ranking.** Rejected: ranking by each task's highest of CPU, GPU and RAM; a threshold-only list; a column to choose the ranking. Top five by CPU won, later joined by the extra GPU and RAM rows, whose bar of over a quarter or always was rejected for over a tenth. (D12, D55, D106, D108, D109, 2026-10-18)
- **beyond-five.** Rejected: a "Show more" row; both that and the link; neither. The Activity Monitor link won. (D13, D59, 2026-10-18)
- **end-click.** Rejected: a confirmation then quit then Force Quit; a confirmation then quit only; one-click quit with no force step. Quit, then Force Quit, with no confirmation won. (D14, D17, D60, 2026-10-18)
- **force-wait.** Rejected: three seconds; ten seconds. Five won. (D15, D16, D62, 2026-10-18)
- **decimals.** Rejected: one decimal everywhere; one decimal in the menu bar only; whole numbers everywhere. Whole numbers in the bar, one decimal in the panel won. (D18, 2026-10-18)
- **bar-rounding.** Rejected: rounding down; rounding to nearest but never zero while busy. Nearest won. (D21, D46, 2026-10-18)
- **short-history.** Rejected: stretching the graph to the history it has. A fixed axis with an empty left won. (D22, D51, 2026-10-18)
- **sleep-gap.** Rejected: joining the line across the sleep; starting over on wake. A gap won. (D23, D52, 2026-10-18)
- **system-tasks.** Rejected: hiding system tasks; End with a warning and an admin password; a short named list of session-ending tasks; keeping the first not-the-user's-own rule alone. Anything of macOS or not the user's own is listed with no End. (D24, D56, D99, 2026-10-18)
- **live-reorder.** Rejected: freezing the order under the pointer; a snapshot when the panel opens; naming the task after the click. Live, holding only the row whose End is under the pointer, won. (D25, D100, 2026-10-18)
- **ram-meaning.** Rejected: everything not free, cache included; memory pressure. Activity Monitor's Memory Used won. (D26, D47, 2026-10-18)
- **gpu-meaning.** Rejected: the sum of Activity Monitor's per-task % GPU column. macOS's own reading won. (D28, D49, 2026-10-18)
- **width.** Rejected: width following the text; the text as first ruled with slack at the end. Fixed width with right-aligned numbers won. (D30, D31, D44, D90, 2026-10-18)
- **quitting.** Rejected: a start-at-login switch beside Quit; no quit in the panel. A Quit row, back at login, won. (D34, D65, 2026-10-18)
- **self-in-list.** Rejected: an End that quits the meter; leaving itself out. Listed with no End won. (D35, D57, 2026-10-18)
- **ties.** Rejected: keeping the previous order; leaving ties unspecified. Alphabetical won. (D41, D58, 2026-10-18)
- **own-cost.** Rejected: only the closed-panel CPU line and the energy check; other numbers; one day or thirty days for the memory line. All four lines, seven days, won. (D73, D74, D76, 2026-10-18)
- **crash.** Rejected: gone until the next login; out of scope; back within three or sixty seconds. Back within ten seconds won. (D77, 2026-10-18)
- **stale-value.** Rejected: keeping the last value. A dash after three seconds won. (D78, D91, D97, 2026-10-18)
- **evolvability.** Rejected: this Mac only. A new Mac and macOS updates must both be survived. (D80, 2026-10-18)
- **updates.** Rejected: the meter offering updates; silent self-update. The visionary installs them. (D84, 2026-10-18)
- **new-metrics-place.** Rejected: all three in the panel only; all of them in the menu bar. Temperature in the bar, network and disk in the panel, won. (D85, 2026-10-18)
- **temperature.** Rejected: Fahrenheit; following the region setting; macOS's heat level word; dropping temperature. Degrees Celsius, accepted as uncheckable, won. (D86, D88, D112, 2026-10-18)
- **speed-units.** Rejected: the same format unpinned; megabits per second for network; always megabytes per second; stepping up to MB/s at 300 KB to keep a mockup value; leaving loopback and virtual interfaces out of the network value. Auto-scaling bytes matched to Activity Monitor, in its decimal steps of a thousand and counting what it counts, won. (D95 amended by D117, 2026-10-21)
- **new-metrics-history.** Rejected: a second small graph. Current values only won. (D96, 2026-10-18)
- **shortcut.** Rejected: Option-Command-M, macOS's minimize-all; a combination the visionary sets. Control-Option-Command-M won. (D98, 2026-10-18)
- **notch.** Rejected: the fence alone; a compact form when crowded; dropping temperature from the bar. The fence plus a named assumption won. (D102, D103, 2026-10-18)
- **tags.** Rejected: untagged extra rows; dropping the extra rows. Plain reason tags with no colour or icon won. (D110, 2026-10-18)

## Sanctioned changes

- `network-and-disk.feature` — "Network and disk match Activity Monitor" — direction: rewords — the busy row's sent value 0.3 MB becomes 300 KB and its network line `Net ↓ 112.4 MB/s ↑ 0.3 MB/s` becomes `Net ↓ 112.4 MB/s ↑ 300.0 KB/s`; the scenario's tag @D95 becomes @D117. (D117, 2026-10-21)
