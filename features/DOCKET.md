docket: 1

# Docket of the /scope interview for menubar-meter, a macOS menu bar usage meter (opened 2026-10-18).
# The machine it is for: an `Apple M5` Mac.
# Need weights are guesses until the Phase 1.5 readback.

N0 2026-10-18 [I>V] visionary 5
  need:  I need a small, always-visible item in my Mac's menu bar, near Control Center, that shows how hard this machine is working, with live CPU, GPU and RAM usage as percentages, and tracks them, so I can check at a glance without opening anything [I>V]

N1 2026-10-18 [I] visionary 4
  need:  I need the chance to kill or end tasks that take up an inordinate amount of compute [V]

D1 2026-10-18 [I>V]
  resp:  tracking means the current CPU, GPU and RAM usage plus a look back over the last {TBD minutes}; nothing is kept once it falls out of that window [I>V]
  ->     need N0
  touches: N0
# roads not taken: live numbers only; long history kept over hours or days surviving restarts; peaks and alerts without history

D2 2026-10-18 [I>V]
  resp:  the app shows which tasks are heavy, and a task ends only when the visionary picks it and tells it to end; the app never ends a task on its own [I>V]
  ->     need N1
  touches: N1
# roads not taken: the app flags a runaway task and the visionary decides; the app ends tasks itself by a rule the visionary sets, telling them after

D3 2026-10-18 [V]
  resp:  only the visionary uses this Mac; nobody else has a login on it or shares theirs [V]
  ->     fence-assumption single-user-mac
  touches: D2
# reopening condition: a second person gets a login on this Mac or starts using the visionary's

N2 2026-10-18 [I>V] visionary 3
  need:  I need the meter itself to cost my Mac almost nothing, so it does not add to the load it is showing me [I>V]
# inferred from "small but effective", put to the visionary at the Phase 1.5 readback and accepted

N3 2026-10-18 [I>V] visionary 5 amends N0
  need:  I need to see at a glance how hard my Mac is working, in CPU, GPU and RAM, without opening anything [I>V]
  means: an item in the menu bar near Control Center that shows the usage as percentages [I>V]
# swap test at Phase 1.5: the menu bar item and the percentages are the chosen means, not the need

N4 2026-10-18 [I>V] visionary 4 amends N1
  need:  when a task is hogging compute, I need to get my machine back [I>V]
  means: ending that task myself [I>V]
# swap test at Phase 1.5: ending the task is the chosen means; weights confirmed at the readback

D4 2026-10-18 [I>V]
  pre:   the visionary has not opened the meter themselves [I>V]
  trig:  they log in to the Mac, including after a restart [I>V]
  resp:  the meter's item appears in the menu bar by itself [I>V]
  serves: N0
  touches: N0
# roads not taken: the visionary opens it once and it stays until quit, gone after a restart; a start-at-login switch the visionary controls

D5 2026-10-18 [I>V]
  pre:   the Mac is running with CPU at {100%}, GPU at {7%} and RAM at {93%} [I>V]
  trig:  the visionary looks at the menu bar [I>V]
  resp:  the item near Control Center reads `CPU 100%  GPU 7%  RAM 93%` as one line of labeled text, CPU first, then GPU, then RAM [I>V]
  why:   the values are the interviewer's stress case for the mockup, the widest reading beside a lopsided spread [I>V]
  serves: N0
  touches: N3 D1
# roads not taken: single-letter labels `C100 G7 R93`; stacked tiny label-over-number columns; three mini fill bars with numbers and no words

D6 2026-10-18 [I>V]
  pre:   the menu bar item reads CPU at {20%} [I>V]
  trig:  the Mac's CPU use rises to {80%} and stays there [I>V]
  resp:  the item reads `CPU 80%` within {1 second} [I>V]
  why:   the visionary picked the refresh from options of one, two and five seconds or a setting; the readings are the interviewer's example [I>V]
  serves: N0
  touches: D5 N2
# roads not taken: every two seconds; every five seconds; an interval setting with a default

D7 2026-10-18 [I>V] amends D1
  resp:  tracking means the current CPU, GPU and RAM usage plus a look back over the last {5 minutes}; nothing is kept once it falls out of that window [I>V]
  why:   the visionary picked the window from options of one, five, fifteen and sixty minutes [I>V]
  ->     need N0
  touches: D1 D6
# roads not taken: one minute; fifteen minutes; sixty minutes

D8 2026-10-18 [I>V]
  pre:   the meter has run for over {5 minutes}; CPU spiked to {100%} about {4.5 minutes} ago and is at {100%} now, GPU has sat at {0%}, RAM has held near {93%} [I>V]
  trig:  the visionary clicks the menu bar item [I>V]
  resp:  a panel drops down with one combined graph of the last {5 minutes}, running from five minutes ago on the left to now on the right on a scale of zero to a hundred percent, one line each for CPU, GPU and RAM, with a legend reading `CPU 100%  GPU 0%  RAM 93%` [I>V]
  why:   the readings are the interviewer's stress case for the mockup, a spike near the far edge of the window; the window is the one D7 sets [I>V]
  serves: N0
  touches: D7 D5
# roads not taken: three stacked graphs each with its current value and its peak; the stacked graphs with the heavy-task list below them in the same panel

D9 2026-10-18 [I>V]
  resp:  the history panel shows no peak value for any metric; the graph and the current values are all it shows [I>V]
  ->     fence-declined peak-values
  touches: D8
# settled at the D8 phrasing check: choosing the combined graph gives up the per-metric peak number, and the visionary accepted that

D10 2026-10-18 [I>V]
  resp:  the heavy tasks are listed in the same panel, below the graph, under the heading `heavy tasks` with columns CPU, GPU and RAM; each row shows the task's name, cut short with an ellipsis when too long, its three usage values, and its own `End` button [I>V]
  ->     need N1
  touches: D2 D8
# roads not taken: a separate `Heavy tasks` row opening the list beside the panel; two tabs, History and Tasks

D11 2026-10-18 [I>V]
  pre:   one task is fully using {4} of the Mac's {10} CPU cores [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  that task's row reads `40%` under CPU, its share of the whole machine; no task's number is ever above {100%} [I>V]
  why:   ten cores is this Mac's count; four busy cores is the interviewer's example [I>V]
  serves: N1
  touches: D10 D5
# roads not taken: Activity Monitor's per-core count, a hundred percent per core, up to a thousand percent on this Mac
# evidence: `sysctl -n hw.ncpu` prints 10 (4 performance, 6 efficiency); `hw.memsize` is 32 GiB

D12 2026-10-18 [I>V]
  pre:   seven tasks are running at CPU {30% | 25% | 20% | 15% | 10% | 5% | 1%}, and the one at {5%} uses the most RAM of all [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the heavy-tasks list shows exactly {5} rows, the tasks at {30%}, {25%}, {20%}, {15%} and {10%} in that order; ranking is by CPU alone, so the high-RAM task at {5%} is not listed [I>V]
  why:   five rows ranked by CPU is the visionary's pick from options; the seven readings are the interviewer's example [I>V]
  serves: N1
  touches: D10 D11
# roads not taken: top five ranked by each task's highest of CPU, GPU and RAM; only tasks over a threshold, empty on a quiet Mac; top five with a column the visionary clicks to choose the ranking

D13 2026-10-18 [I>V]
  pre:   the panel is open [I>V]
  trig:  the visionary clicks `Open Activity Monitor…`, the last row of the panel below the heavy-tasks list [I>V]
  resp:  Activity Monitor opens in front, where every task can be seen, sorted and ended; the panel's own list stays at the top {5} by CPU [I>V]
  why:   five is the count D12 sets [I>V]
  serves: N1
  touches: D12 D10
# the visionary asked for an expandable list or a link and asked for the interviewer's view; the link was offered labeled as the interviewer's pick and chosen
# roads not taken: a `Show more` row expanding the list in place; both the expansion and the link; neither

D14 2026-10-18 [I>V]
  pre:   Xcode is in the heavy-tasks list [I>V]
  trig:  the visionary clicks `End` on Xcode's row [I>V]
  resp:  with no confirmation step, Xcode is asked to quit the normal way, as the app's own Quit would, so it may still ask to save; its button reads `Ending…` until Xcode is gone, and then the row leaves the list [I>V]
  serves: N1
  touches: D2 D10 D12
# the visionary asked for the interviewer's view; the option was offered labeled as the interviewer's pick, with the misclick risk on windowless tasks named, and chosen
# roads not taken: a confirmation before the quit, then Force Quit if needed; a confirmation then a normal quit only; one-click normal quit with no force step

D15 2026-10-18 [I>V]
  pre:   the visionary clicked `End` on a task and its button reads `Ending…` [I>V]
  trig:  the task is still running {TBD seconds} later [I>V]
  resp:  the button turns into `Force Quit`, and clicking it ends the task outright, without asking it [I>V]
  serves: N1
  touches: D14 D2

D16 2026-10-18 [I>V] amends D15
  pre:   the visionary clicked `End` on a task and its button reads `Ending…` [I>V]
  trig:  the task is still running {5 seconds} later [I>V]
  resp:  the button turns into `Force Quit`, and clicking it ends the task outright, without asking it [I>V]
  why:   the visionary picked the wait from options of three, five and ten seconds [I>V]
  serves: N1
  touches: D15 D14
# roads not taken: three seconds; ten seconds

D17 2026-10-18 [I>V] amends D14
  pre:   Xcode is in the heavy-tasks list [I>V]
  trig:  the visionary clicks `End` on Xcode's row [I>V]
  resp:  with no confirmation step, Xcode is asked to quit the normal way, as the app's own Quit would, so it may still ask to save; its button reads `Ending…` until Xcode is gone, and then the row leaves the list and the next-highest CPU task moves up, so the list again shows {5} rows [I>V]
  why:   five is the count D12 sets [I>V]
  serves: N1
  touches: D14 D12
# the refill clause was the interviewer's addition at the phrasing check, derived from D12, and accepted

D18 2026-10-18 [I>V]
  resp:  the menu bar item shows whole-number percentages as D5 rules, while the panel's legend and its task rows show one decimal place, a trailing `.0` included [I>V]
  ->     need N0
  touches: D5 D8 D11 D12
# the visionary first picked one decimal for the readout; that collided with D5's whole numbers and was put back as its own decision point
# roads not taken: one decimal everywhere; one decimal in the menu bar only; whole numbers everywhere after all

D19 2026-10-18 [I>V] amends D8
  pre:   the meter has run for over {5 minutes}; CPU spiked to {100%} about {4.5 minutes} ago and is at {100%} now, GPU has sat at {0%}, RAM has held near {93%} [I>V]
  trig:  the visionary clicks the menu bar item [I>V]
  resp:  a panel drops down with one combined graph of the last {5 minutes}, running from five minutes ago on the left to now on the right on a scale of zero to a hundred percent, one line each for CPU, GPU and RAM, with a legend reading `CPU 100.0%  GPU 0.0%  RAM 93.0%` [I>V]
  why:   the readings are the interviewer's stress case for the mockup, a spike near the far edge of the window; the window is the one D7 sets; one decimal is D18 [I>V]
  serves: N0
  touches: D8 D18

D20 2026-10-18 [I>V] amends D11
  pre:   one task is fully using {4} of the Mac's {10} CPU cores [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  that task's row reads `40.0%` under CPU, its share of the whole machine; no task's number is ever above {100%} [I>V]
  why:   ten cores is this Mac's count; four busy cores is the interviewer's example; one decimal is D18 [I>V]
  serves: N1
  touches: D11 D18

D21 2026-10-18 [I>V]
  pre:   the Mac's CPU use is {0% | 0.4% | 7.5% | 99.6% | 100%} [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  the item shows CPU as {0% | 0% | 8% | 100% | 100%}, rounded to the nearest whole number with a half rounding up; GPU and RAM round the same way [I>V]
  why:   the fractions are the interviewer's spread; the rule is the visionary's pick from options [I>V]
  spread: Rounding the menu bar readout
  serves: N0
  touches: D18 D5
# roads not taken: rounding down so a hundred shows only when truly maxed; rounding to nearest but never showing zero while busy

D22 2026-10-18 [I>V] !
  pre:   the meter has been running for only {30 seconds} [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the graph's axis still runs from five minutes ago to now; the lines cover only the last {30 seconds} at the right edge and the rest of the graph is empty [I>V]
  why:   thirty seconds is the interviewer's example of a history shorter than the window D7 sets [I>V]
  serves: N0
  touches: D19 D7
# roads not taken: the graph stretches to span only the history it has and grows until it reaches five minutes

D23 2026-10-18 [I>V] !
  pre:   the meter was running, then the Mac slept for {2 minutes} and woke within the last {5 minutes} [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the graph shows no line for the stretch the Mac was asleep; the lines stop where it went to sleep and resume where it woke [I>V]
  why:   two minutes is the interviewer's example; the window is the one D7 sets [I>V]
  serves: N0
  touches: D19 D22 D7
# roads not taken: the line joined straight across the sleep; waking clears the history and the graph starts over

D24 2026-10-18 [I>V] !
  pre:   a task that is not running as the visionary's own user, such as `WindowServer`, `kernel_task` or `mds_stores`, is among the top {5} by CPU [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the task is listed in its CPU rank and counts toward the {5} rows, marked `system`, with no `End` button; every task running as the visionary keeps its `End` button, `node`, Finder and Dock included [I>V]
  why:   five is the count D12 sets [I>V]
  serves: N1
  touches: D12 D10 D14 D3
# the visionary asked for the interviewer's view and whether `node` is a system task; the rule "not running as you" was offered labeled as the interviewer's pick and chosen
# evidence: `ps -axo user,comm` shows 518 processes as linus, the rest as root or service accounts; every `node` runs as linus from ~/.nvm; WindowServer runs as _windowserver at 21.2 per-core percent
# roads not taken: system tasks hidden from the list; End offered with a warning and an admin password

D25 2026-10-18 [I>V]
  resp:  while the panel is open, the heavy-tasks list re-ranks by CPU on every refresh, even under the pointer; the visionary times the click [I>V]
  ->     need N1
  touches: D6 D12 D17
# the interviewer named the risk of ending the wrong task when rows swap at the click; carried to the adversarial pass beside D17's missing confirmation
# roads not taken: the order freezes while the pointer is over the list; the order is a snapshot taken when the panel opens

D26 2026-10-18 [I>V]
  pre:   apps are using {18 GB} of the Mac's {32 GB}, macOS holds {11 GB} of reusable cache, and Activity Monitor reads `Memory Used: 18.0 GB` [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  it shows `RAM 56%`, the Memory Used that Activity Monitor reports divided by the Mac's physical memory; reusable cache does not count [I>V]
  why:   thirty-two gigabytes is this Mac's memory per `hw.memsize`; the other figures are the interviewer's illustration [I>V]
  serves: N0
  touches: D5 D21
# roads not taken: everything not free, cache included; memory pressure rather than fullness

D27 2026-10-18 [I>V]
  pre:   Activity Monitor's CPU tab reads System `12.0%` and User `30.5%` at the same moment [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  it shows `CPU 43%`, Activity Monitor's total CPU load, User plus System, rounded as D21 rules [I>V]
  why:   the figures are the interviewer's example, chosen so the sum lands on a half and rounds up [I>V]
  serves: N0
  touches: D21 D26 D5
# the visionary answered that CPU and GPU both match Activity Monitor; the CPU half stands as asked, the GPU half fell to a check and was put back as D28

D28 2026-10-18 [I>V]
  pre:   macOS reports its overall GPU utilization as `4%` [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  it shows `GPU 4%`, macOS's own overall GPU utilization reading; each task's GPU value in the list is the one Activity Monitor shows in its `% GPU` column for that task [I>V]
  why:   four percent is what `ioreg` reported on this Mac when the question was put [I>V]
  serves: N0 N1
  touches: D27 D10 D20
# premise check: Activity Monitor has a per-task `% GPU` column (its ActivityMonitor.loctable carries the string) but shows whole-Mac GPU only as the GPU History graph, with no figure, so an exact whole-GPU match to Activity Monitor is impossible
# evidence: `ioreg -r -d 1 -c IOAccelerator` prints "Device Utilization %"=4
# the visionary asked for the interviewer's honest view; the macOS reading was offered labeled as the interviewer's pick and chosen
# roads not taken: the sum of Activity Monitor's per-task `% GPU` column, exact to check but able to read below the GPU's true load

D29 2026-10-18 [I>V]
  resp:  Activity Monitor's GPU History graph plots the same overall GPU utilization that macOS reports and the meter shows, so the meter's GPU value can be checked by eye against that graph [I>V]
  ->     fence-assumption gpu-history-matches-macos-reading
  touches: D28
# uncheckable from here per rule 6, so named; reopening condition: the meter's GPU value and the GPU History graph visibly disagree on this Mac

D30 2026-10-18 [I>V] !
  pre:   the menu bar item reads CPU {7%}, GPU {0%} and RAM {9%} [I>V]
  trig:  all three rise to {100%} [I>V]
  resp:  the item keeps the same width, which always leaves room for a hundred percent on all three, so the menu bar icons to its left do not move [I>V]
  why:   the readings are the interviewer's extremes, the narrowest and the widest the item can show [I>V]
  serves: N0
  touches: D5 D21
# roads not taken: the item as wide as its text, nudging the icons to its left as digits come and go

D31 2026-10-18 [I>V] amends D5
  pre:   the Mac is running with CPU at {100%}, GPU at {7%} and RAM at {93%} [I>V]
  trig:  the visionary looks at the menu bar [I>V]
  resp:  the item near Control Center reads `CPU 100%  GPU   7%  RAM  93%` as one line of labeled text, CPU first, then GPU, then RAM, each number right-aligned in a slot three digits wide so the labels and percent signs never move [I>V]
  why:   the values are the interviewer's stress case for the mockup, the widest reading beside a lopsided spread [I>V]
  serves: N0
  touches: D5 D30 D6 D21 D26 D27 D28
# the padding is D30's consequence, put to the visionary as its own decision point; entries that name a single value, such as D6's `CPU 80%`, assert the number and its label, with the padding this entry rules between them
# roads not taken: the text exactly as D5 with the spare room blank at the item's right end

D32 2026-10-18 [V]
  resp:  what happens when the menu bar is too crowded for the meter beside the notch is out of scope; the meter keeps its fixed width and makes no special move [V]
  ->     fence-declined crowded-menu-bar
  touches: D30 D31
# evidence: `system_profiler SPHardwareDataType` reads MacBook Air, Mac17,4; the built-in display is 2880 x 1864, the notched panel; an external 1080p display is attached
# roads not taken: macOS decides and the visionary makes room; a compact fallback form when it would not fit

D33 2026-10-18 [V]
  resp:  where the meter appears when more than one display is attached is out of scope; whatever macOS does by default stands [V]
  ->     fence-declined multiple-displays
  touches: D4 D32
# roads not taken: every screen's menu bar with the same numbers; the main screen only

D34 2026-10-18 [I>V]
  pre:   the meter is in the menu bar and its panel is open [I>V]
  trig:  the visionary clicks `Quit Meter`, the very last row of the panel, below `Open Activity Monitor…` [I>V]
  resp:  the meter leaves the menu bar at once, and returns by itself at the next login as D4 rules [I>V]
  serves: N0
  touches: D4 D13
# the visionary asked for the interviewer's view; this option was offered labeled as the interviewer's pick, with the note that a start-at-login switch would reverse a road D4 did not take, and chosen
# roads not taken: a Quit row plus a start-at-login switch, amending D4; no quit in the panel, quitting from Activity Monitor instead

D35 2026-10-18 [I>V] !
  pre:   the meter itself ranks among the top {5} tasks by CPU [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the meter's own row is listed in its CPU rank, marked `system` as D24 marks tasks that cannot be ended there, with no `End` button; `Quit Meter` stays the way to stop it [I>V]
  why:   five is the count D12 sets [I>V]
  serves: N1 N2
  touches: D24 D34 D12
# roads not taken: listed with an End button that does the same as Quit Meter; never listed, the next task filling the fifth row

D36 2026-10-18 [I>V] !
  pre:   `node` has used {95%} of the Mac's CPU for the last {60 minutes}, and the visionary has clicked nothing in the meter [I>V]
  trig:  another minute passes [I>V]
  resp:  `node` is still running, and its row still has an ordinary `End` button with no warning, highlight or prompt urging the visionary to end it [I>V]
  why:   the readings are the interviewer's case, the one most likely to tempt an automatic fix [I>V]
  serves: N1
  touches: D2 D24
# the no-nudge clause is the interviewer's addition, derived from D2's road not taken, and accepted

D37 2026-10-18 [I>V] !
  pre:   CPU spiked to {100%} {5 minutes 10 seconds} ago and has stayed under {10%} since [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the spike is nowhere in the graph; nothing older than {5 minutes} is shown or kept [I>V]
  why:   ten seconds past the window D7 sets is the interviewer's edge [I>V]
  serves: N0
  touches: D7 D19

D38 2026-10-18 [I>V] !
  pre:   the visionary clicked `End` on a task and its button reads `Ending…` [I>V]
  trig:  they click the button again before {5 seconds} have passed [I>V]
  resp:  nothing more happens; the button only becomes clickable again as `Force Quit`, once {5 seconds} have passed [I>V]
  why:   five seconds is the wait D16 sets [I>V]
  serves: N1
  touches: D17 D16

D39 2026-10-18 [I>V] !
  pre:   the visionary clicked `End` on a task [I>V]
  trig:  the task quits {2 seconds} later [I>V]
  resp:  its row leaves the list, and `Force Quit` never appears for it [I>V]
  why:   two seconds is the interviewer's example, inside the wait D16 sets [I>V]
  serves: N1
  touches: D16 D17

D40 2026-10-18 [I>V] !
  pre:   a task's button reads `Force Quit` [I>V]
  trig:  the task exits by itself before the visionary clicks it [I>V]
  resp:  its row leaves the list, and nothing else is ended [I>V]
  serves: N1
  touches: D16 D39

D41 2026-10-18 [I>V]
  pre:   two tasks both sit at exactly {12.0%} CPU, tied for the last of the {5} rows [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the tie is broken by name in alphabetical order, so the task whose name comes first takes the higher row [I>V]
  why:   the tie value is the interviewer's example; five is the count D12 sets [I>V]
  serves: N1
  touches: D12 D25
# roads not taken: the previous order kept, fewer swaps; ties left unspecified

# Phase 3 close, record pass (2026-10-18): every wanted triggered entry gains its sib line, and every braced quantity either gains a spread line naming the outline that varies it or is restated as a backticked example reading. The outline rows were put to the visionary as one table and accepted. Content otherwise unchanged.

D42 2026-10-18 [I>V] amends D4
  pre:   the visionary has not opened the meter themselves [I>V]
  trig:  they log in to the Mac, including after a restart [I>V]
  resp:  the meter's item appears in the menu bar by itself [I>V]
  sib:   none -- quitting and coming back at login is the case D34 rules
  serves: N0
  touches: D4 D34

D43 2026-10-18 [I>V] amends D31
  pre:   the Mac is running with CPU, GPU and RAM at {100%, 7%, 93% | 7%, 100%, 9% | 0%, 0%, 0%} [I>V]
  trig:  the visionary looks at the menu bar [I>V]
  resp:  the item near Control Center reads {`CPU 100%  GPU   7%  RAM  93%` | `CPU   7%  GPU 100%  RAM   9%` | `CPU   0%  GPU   0%  RAM   0%`} as one line of labeled text, CPU first, then GPU, then RAM, each number right-aligned in a slot three digits wide so the labels and percent signs never move [I>V]
  why:   the rows are the interviewer's spread, the widest reading beside a lopsided one and the all-idle floor, accepted as a table [I>V]
  spread: Reading the three values in the menu bar
  sib:   D30
  serves: N0
  touches: D31 D30

D44 2026-10-18 [I>V] ! amends D30
  pre:   the menu bar item has been showing CPU `7%`, GPU `0%` and RAM `9%` [I>V]
  trig:  the readings change to CPU, GPU and RAM at {7%, 0%, 9% | 100%, 100%, 100% | 0%, 100%, 0%} [I>V]
  resp:  the item keeps the same width, which always leaves room for a hundred percent on all three, so the menu bar icons to its left do not move [I>V]
  why:   the rows are the interviewer's extremes, the narrowest, the widest and a mix, accepted as a table [I>V]
  spread: The menu bar item keeps one width
  serves: N0
  touches: D30 D43

D45 2026-10-18 [I>V] amends D6
  pre:   the menu bar item reads CPU at {20% | 80% | 0%} [I>V]
  trig:  the Mac's CPU use moves to {80% | 20% | 100%} and stays there [I>V]
  resp:  the item shows the new CPU value within {1 second} [I>V]
  why:   the visionary picked the one-second refresh from options; the rows are the interviewer's spread, accepted as a table [I>V]
  spread: The readout follows a change within a second
  sib:   none -- no failure case for the refresh was ruled
  serves: N0
  touches: D6 D43 N2

D46 2026-10-18 [I>V] amends D21
  pre:   the Mac's CPU use is {0% | 0.4% | 7.5% | 99.6% | 100%} [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  the item shows CPU as {0% | 0% | 8% | 100% | 100%}, rounded to the nearest whole number with a half rounding up; GPU and RAM round the same way [I>V]
  why:   the fractions are the interviewer's spread; the rule is the visionary's pick from options [I>V]
  spread: Rounding the menu bar readout
  sib:   none -- the outline rows carry every extreme
  serves: N0
  touches: D21

D47 2026-10-18 [I>V] amends D26
  pre:   Activity Monitor reads Memory Used of {18.0 GB | 0.5 GB | 31.9 GB} on this Mac's `32 GB`, with reusable cache held besides [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  it shows RAM as {56% | 2% | 100%}, the Memory Used that Activity Monitor reports divided by the Mac's physical memory and rounded as D46 rules; reusable cache does not count [I>V]
  why:   thirty-two gigabytes is this Mac's memory per `hw.memsize`; the rows are the interviewer's spread, accepted as a table [I>V]
  spread: RAM matches Activity Monitor's Memory Used
  sib:   none -- the far-side comparison is the check
  serves: N0
  touches: D26 D46

D48 2026-10-18 [I>V] amends D27
  pre:   Activity Monitor's CPU tab reads System `12.0%` and User `30.5%` at the same moment [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  it shows `CPU 43%`, Activity Monitor's total CPU load, User plus System, rounded as D46 rules [I>V]
  sib:   none -- the far-side comparison is the check
  serves: N0
  touches: D27 D46

D49 2026-10-18 [I>V] amends D28
  pre:   macOS reports its overall GPU utilization as `4%` [I>V]
  trig:  the menu bar item refreshes [I>V]
  resp:  it shows `GPU 4%`, macOS's own overall GPU utilization reading; each task's GPU value in the list is the one Activity Monitor shows in its `% GPU` column for that task [I>V]
  sib:   none -- the far-side comparison is the check
  serves: N0 N1
  touches: D28 D29

D50 2026-10-18 [I>V] amends D19
  pre:   the meter has run for over `5 minutes`; CPU spiked to `100%` some {4.5 minutes} ago and is at `100%` now, GPU has sat at `0%`, RAM has held near `93%` [I>V]
  trig:  the visionary clicks the menu bar item [I>V]
  resp:  a panel drops down with one combined graph of the last five minutes, running from five minutes ago on the left to now on the right on a scale of zero to a hundred percent, one line each for CPU, GPU and RAM, the spike showing near the left edge, with a legend reading `CPU 100.0%  GPU 0.0%  RAM 93.0%` [I>V]
  why:   the spike's age is the interviewer's case near the far edge of the window D7 sets, accepted as a table row; one decimal is D18 [I>V]
  spread: A spike stays in the graph only while it is under five minutes old
  sib:   D22
  serves: N0
  touches: D19 D37

D51 2026-10-18 [I>V] ! amends D22
  pre:   the meter has been running for only `30 seconds` [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the graph's axis still runs from five minutes ago to now; the lines cover only the last thirty seconds at the right edge and the rest of the graph is empty [I>V]
  sib:   D23
  serves: N0
  touches: D22 D50

D52 2026-10-18 [I>V] ! amends D23
  pre:   the meter was running, then the Mac slept for `2 minutes` and woke within the last five minutes [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the graph shows no line for the stretch the Mac was asleep; the lines stop where it went to sleep and resume where it woke [I>V]
  sib:   D37
  serves: N0
  touches: D23 D51

D53 2026-10-18 [I>V] ! amends D37
  pre:   CPU spiked to `100%` some {5 minutes 10 seconds} ago and has stayed under `10%` since [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the spike is nowhere in the graph; nothing older than five minutes is shown or kept [I>V]
  why:   ten seconds past the window D7 sets is the interviewer's edge, accepted as a table row [I>V]
  spread: A spike stays in the graph only while it is under five minutes old
  serves: N0
  touches: D37 D50

D54 2026-10-18 [I>V] amends D20
  pre:   one task is fully using {1 | 4 | 10} of the Mac's `10` CPU cores [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  that task's row reads {`10.0%` | `40.0%` | `100.0%`} under CPU, its share of the whole machine; no task's number is ever above a hundred percent [I>V]
  why:   ten cores is this Mac's count per `hw.ncpu`; the rows are the interviewer's spread, accepted as a table [I>V]
  spread: A task's CPU is its share of the whole Mac
  sib:   none -- the hundred percent cap is an outline row
  serves: N1
  touches: D20 D49

D55 2026-10-18 [I>V] amends D12
  pre:   seven tasks are running at CPU `30%`, `25%`, `20%`, `15%`, `10%`, `5%` and `1%`, and the one at `5%` uses the most RAM of all [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the heavy-tasks list shows exactly five rows, the tasks at `30%`, `25%`, `20%`, `15%` and `10%` in that order; ranking is by CPU alone, so the high-RAM task is not listed [I>V]
  sib:   D24
  serves: N1
  touches: D12 D24

D56 2026-10-18 [I>V] ! amends D24
  pre:   a task that is not running as the visionary's own user, such as `WindowServer`, `kernel_task` or `mds_stores`, is among the top five by CPU [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the task is listed in its CPU rank and counts toward the five rows, marked `system`, with no `End` button; every task running as the visionary keeps its `End` button, `node`, Finder and Dock included [I>V]
  sib:   D35
  serves: N1
  touches: D24 D55

D57 2026-10-18 [I>V] ! amends D35
  pre:   the meter itself ranks among the top five tasks by CPU [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the meter's own row is listed in its CPU rank, marked `system` as D56 marks tasks that cannot be ended there, with no `End` button; `Quit Meter` stays the way to stop it [I>V]
  serves: N1 N2
  touches: D35 D56

D58 2026-10-18 [I>V] amends D41
  pre:   two tasks both sit at exactly `12.0%` CPU, tied for the last of the five rows [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the tie is broken by name in alphabetical order, so the task whose name comes first takes the higher row [I>V]
  sib:   none -- a broken tie has no further failure
  serves: N1
  touches: D41 D55

D59 2026-10-18 [I>V] amends D13
  pre:   the panel is open [I>V]
  trig:  the visionary clicks `Open Activity Monitor…`, the row below the heavy-tasks list [I>V]
  resp:  Activity Monitor opens in front, where every task can be seen, sorted and ended; the panel's own list stays at the top five by CPU [I>V]
  sib:   none -- no failure case for opening it was ruled
  serves: N1
  touches: D13 D55

D60 2026-10-18 [I>V] amends D17
  pre:   Xcode is in the heavy-tasks list [I>V]
  trig:  the visionary clicks `End` on Xcode's row [I>V]
  resp:  with no confirmation step, Xcode is asked to quit the normal way, as the app's own Quit would, so it may still ask to save; its button reads `Ending…` until Xcode is gone, and then the row leaves the list and the next-highest CPU task moves up, so the list again shows five rows [I>V]
  sib:   D36
  serves: N1
  touches: D17 D36

D61 2026-10-18 [I>V] ! amends D36
  pre:   `node` has used `95%` of the Mac's CPU for the last `60 minutes`, and the visionary has clicked nothing in the meter [I>V]
  trig:  another minute passes [I>V]
  resp:  `node` is still running, and its row still has an ordinary `End` button with no warning, highlight or prompt urging the visionary to end it [I>V]
  serves: N1
  touches: D36 D60

D62 2026-10-18 [I>V] amends D16
  pre:   the visionary clicked `End` on a task and its button reads `Ending…` [I>V]
  trig:  the task is still running {5 seconds} later [I>V]
  resp:  the button turns into `Force Quit`, and clicking it ends the task outright, without asking it [I>V]
  why:   the visionary picked the wait from options of three, five and ten seconds [I>V]
  spread: Force Quit appears only for a task still running after five seconds
  sib:   D38
  serves: N1
  touches: D16 D38 D39

D63 2026-10-18 [I>V] ! amends D38
  pre:   the visionary clicked `End` on a task and its button reads `Ending…` [I>V]
  trig:  they click the button again before five seconds have passed [I>V]
  resp:  nothing more happens; the button only becomes clickable again as `Force Quit`, once five seconds have passed [I>V]
  sib:   D39
  serves: N1
  touches: D38 D62

D64 2026-10-18 [I>V] ! amends D39
  pre:   the visionary clicked `End` on a task [I>V]
  trig:  the task quits {2 seconds} later [I>V]
  resp:  its row leaves the list, and `Force Quit` never appears for it [I>V]
  why:   two seconds is the interviewer's example inside the wait D62 sets, accepted as a table row [I>V]
  spread: Force Quit appears only for a task still running after five seconds
  sib:   D40
  serves: N1
  touches: D39 D62

D65 2026-10-18 [I>V] amends D34
  pre:   the meter is in the menu bar and its panel is open [I>V]
  trig:  the visionary clicks `Quit Meter`, the very last row of the panel, below `Open Activity Monitor…` [I>V]
  resp:  the meter leaves the menu bar at once, and returns by itself at the next login as D42 rules [I>V]
  sib:   none -- no failure case for quitting was ruled
  serves: N0
  touches: D34 D42

D66 2026-10-18 [I>V] amends D7
  resp:  tracking means the current CPU, GPU and RAM usage plus a look back over the last {5 minutes}; nothing is kept once it falls out of that window [I>V]
  why:   the visionary picked the window from options of one, five, fifteen and sixty minutes [I>V]
  spread: A spike stays in the graph only while it is under five minutes old
  ->     need N0
  touches: D7 D50 D53

# Phase 3.25 triage (2026-10-18): the visionary ticked Performance, Reliability, Evolvability and Lifecycle; the six unticked categories are fenced below, declined with provenance (checklist categories, not derived from the visionary's answers).

D67 2026-10-18 [I>V]
  resp:  usability needs beyond what is ruled, such as readability on light or dark menu bars, keyboard use or colour-blind viewing, are not scoped [I>V]
  ->     fence-declined usability
  touches: none

D68 2026-10-18 [I>V]
  resp:  availability needs, what is acceptable when the meter is missing at the moment it is wanted, are not scoped beyond its starting at login [I>V]
  ->     fence-declined availability
  touches: D42

D69 2026-10-18 [I>V]
  resp:  security needs, who or what must never use the meter's power to end tasks and which permissions it asks for, are not scoped beyond the single-user assumption and the system-task rule [I>V]
  ->     fence-declined security
  touches: D3 D56

D70 2026-10-18 [I>V]
  resp:  operational burden, how long the meter runs unattended and what upkeep the visionary will not commit to, is not scoped [I>V]
  ->     fence-declined ops-burden
  touches: none

D71 2026-10-18 [I>V]
  resp:  diagnosability, what the visionary can find out when the meter shows something odd or breaks, is not scoped [I>V]
  ->     fence-declined diagnosability
  touches: none

D72 2026-10-18 [I>V]
  resp:  compliance with outside rules or standards, App Store rules included, is not scoped [I>V]
  ->     fence-declined compliance
  touches: none

D73 2026-10-18 [I>V]
  pre:   the meter is running with its panel {closed | open}, refreshing every second [I>V]
  trig:  a minute passes [I>V]
  resp:  the meter's own CPU use, averaged over that minute and counted as its share of the whole Mac, stays under {1% | 5%} [I>V]
  why:   the interviewer proposed both lines when the visionary asked for a view, and the visionary took them as offered [I>V]
  spread: The meter's own CPU stays under its line
  sib:   none -- the outline carries both panel states
  serves: N2
  touches: N2 D45 D57
# Phase 3.25 Performance; the visionary asked for the interviewer's view; all four lines were offered labeled as the interviewer's pick and chosen
# roads not taken: only the closed-panel CPU line and the energy check; the same four lines with other numbers

D74 2026-10-18 [I>V]
  pre:   the meter has been running without a restart for {1 hour | TBD days} [I>V]
  trig:  the visionary looks at the meter's row in Activity Monitor's Memory tab [I>V]
  resp:  its Memory value is under {50 MB} [I>V]
  why:   fifty megabytes is the interviewer's line, taken as offered; the hour is the interviewer's short row; the long row was offered as days and its length is not yet fixed [I>V]
  spread: The meter's memory stays under its line
  sib:   none -- the long-running row is the failure case
  serves: N2
  touches: N2 D73

D75 2026-10-18 [I>V]
  pre:   the Mac is on battery and the meter has been running all day [I>V]
  trig:  the visionary opens the battery menu [I>V]
  resp:  the meter is not listed under `Apps Using Significant Energy` [I>V]
  sib:   none -- macOS's own judgment is the check
  serves: N2
  touches: N2 D73

D76 2026-10-18 [I>V] amends D74
  pre:   the meter has been running without a restart for {1 hour | 7 days} [I>V]
  trig:  the visionary looks at the meter's row in Activity Monitor's Memory tab [I>V]
  resp:  its Memory value is under {50 MB} [I>V]
  why:   fifty megabytes and seven days are the interviewer's picks, offered labeled as such and chosen, a week being about how long this Mac goes between restarts; the hour is the interviewer's short row [I>V]
  spread: The meter's memory stays under its line
  sib:   none -- the long-running row is the failure case
  serves: N2
  touches: D74 N2
# roads not taken: one day, quick to check but blind to slow leaks; thirty days, strictest but hard ever to verify

D77 2026-10-18 [I>V]
  pre:   the meter is running with {its panel closed | its panel open} [I>V]
  trig:  the meter crashes and vanishes from the menu bar [I>V]
  resp:  it is back in the menu bar by itself within {10 seconds}, without the visionary doing anything, and its five-minute history starts over empty [I>V]
  why:   ten seconds is the interviewer's pick, offered labeled as such and chosen, quick enough to go unnoticed and slow enough not to thrash; the panel states are the interviewer's spread [I>V]
  spread: The meter comes back by itself after a crash
  sib:   none -- a repeating crash was not ruled
  serves: N0
  touches: D42 D66 D51
# Phase 3.25 Reliability, a checklist category put with provenance
# roads not taken: gone until the next login; crash behaviour out of scope; back within three seconds; back within sixty seconds

D78 2026-10-18 [I>V] !
  pre:   the menu bar item is live, and then no fresh {CPU | GPU | RAM} reading arrives [I>V]
  trig:  {3 seconds} pass without one [I>V]
  resp:  that value shows as a dash, as in `GPU   –%`, until a fresh reading arrives, while the other two values stay live [I>V]
  why:   three seconds is three missed refreshes at the rate D45 sets, the interviewer's pick, offered labeled as such and chosen [I>V]
  spread: A value with no fresh reading turns into a dash
  serves: N0
  touches: D45 D43
# Phase 3.25 Reliability; the visionary asked for the interviewer's view; the frozen-number-looks-live case was offered as the interviewer's pick and chosen
# roads not taken: keep the last value; reliability covered as it was

D79 2026-10-18 [I>V] amends D45
  pre:   the menu bar item reads CPU at {20% | 80% | 0%} [I>V]
  trig:  the Mac's CPU use moves to {80% | 20% | 100%} and stays there [I>V]
  resp:  the item shows the new CPU value within {1 second} [I>V]
  why:   the visionary picked the one-second refresh from options; the rows are the interviewer's spread, accepted as a table [I>V]
  spread: The readout follows a change within a second
  sib:   D78
  serves: N0
  touches: D45 D78 N2

D80 2026-10-18 [I>V]
  pre:   the meter runs on a Mac with {8 | 10 | 16} CPU cores, and one task fully uses all of them [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  that task's row reads `100.0%` under CPU on every one of those Macs, because its share is counted against that Mac's own core count; RAM is likewise counted against that Mac's own physical memory [I>V]
  why:   the core counts are the interviewer's spread around this Mac's ten [I>V]
  spread: The meter counts against the Mac it runs on
  sib:   none -- a wrong count shows in the outline
  serves: N0 N1
  touches: D54 D47
# Phase 3.25 Evolvability, a checklist category put with provenance
# roads not taken: this Mac only, changes handled when they come

D81 2026-10-18 [I>V]
  resp:  a macOS update asks nothing of the visionary; a reading the update stops providing falls back to the dash D78 rules, never to a wrong number [I>V]
  ->     structural
  serves: N0
  touches: D78 D49

D82 2026-10-18 [I>V]
  resp:  removing the meter cleanly, so nothing is left behind at login or on disk, is not scoped [I>V]
  ->     fence-declined clean-removal
  touches: D42
# Phase 3.25 Lifecycle: clean removal was left unticked

D83 2026-10-18 [I>V]
  pre:   the meter is not on this Mac [I>V]
  trig:  the visionary does the one install step [I>V]
  resp:  the item appears in the menu bar right away with no settings to fill in, the only thing to click through being any permission macOS itself asks for, and from then on it starts at every login as D42 rules [I>V]
  sib:   none -- a failed install was not ruled
  serves: N0
  touches: D42 D65
# Phase 3.25 Lifecycle, a checklist category put with provenance

D84 2026-10-18 [I>V]
  pre:   an older version of the meter is installed and starts at login [I>V]
  trig:  the visionary does the one install step with a newer version [I>V]
  resp:  the newer version replaces the older one, appears in the menu bar, and keeps starting at every login; the meter itself never checks for or offers updates [I>V]
  sib:   none -- a failed update was not ruled
  serves: N0
  touches: D83 D42
# roads not taken: the meter checks for updates and offers one in its panel; the meter updates itself silently

N5 2026-10-18 [I] visionary 2
  need:  I also want to see my Mac's network and disk activity and how hot it is, beside how hard it is working [I]
# surfaced by the Phase 3.25 domain question, interviewer's priors named as such; re-enters Phase 1 for these areas; weight a guess

D85 2026-10-18 [I>V]
  resp:  the chip temperature joins the menu bar item after RAM, while network and disk activity appear only in the panel, on lines below the graph's legend; this amends the three-value menu bar text of D43 and the width rule of D44 [I>V]
  ->     need N5
  touches: D43 D44 D50 N5
# roads not taken: all three in the panel only, menu bar unchanged; all of them in the menu bar, about twice as wide

D86 2026-10-18 [I>V]
  resp:  the menu bar temperature is the chip's, shown in degrees Celsius as a whole number followed by `°C` [I>V]
  ->     need N5
  touches: D85
# roads not taken: degrees Fahrenheit; following the Mac's region setting

D87 2026-10-18 [I>V]
  resp:  this Mac lets the meter, running as the visionary, read its chip temperature without an admin password [I>V]
  ->     fence-assumption chip-temperature-readable
  touches: D86 D85
# uncheckable from here per rule 6; reopening condition: the meter cannot read the chip temperature on this Mac without an admin password
# evidence that no far-side readout exists: `pmset -g therm` reports warning levels only; Activity Monitor's ActivityMonitor.loctable and Localizable.loctable hold no "temperature" string

D88 2026-10-18 [I>V]
  pre:   the Mac has sat idle, and the menu bar shows the chip temperature [I>V]
  trig:  one task fully uses every CPU core for {2 minutes} [I>V]
  resp:  the temperature shown at the end is higher than the one shown at idle; no figure from macOS exists to check it against, so its rising under load is the whole check [I>V]
  why:   two minutes is the interviewer's load length, inside the offered sense check of rising under load [I>V]
  spread: The temperature rises under load
  sib:   none -- a failed reading is the dash case
  serves: N5
  touches: D86 D87
# the visionary kept degrees after being told nothing independent can check them; offered as the interviewer's pick and chosen
# roads not taken: macOS's own heat level word instead of degrees; dropping temperature

D89 2026-10-18 [I] amends D43
  pre:   the Mac is running with CPU, GPU, RAM and chip temperature at {100%, 7%, 93%, 98 °C | 7%, 100%, 9%, 61 °C | 0%, 0%, 0%, 35 °C} [I]
  trig:  the visionary looks at the menu bar [I>V]
  resp:  the item near Control Center reads {`CPU 100%  GPU   7%  RAM  93%   98°C` | `CPU   7%  GPU 100%  RAM   9%   61°C` | `CPU   0%  GPU   0%  RAM   0%   35°C`} as one line, CPU first, then GPU, then RAM, then the temperature, each number right-aligned in a slot three digits wide so the labels, percent signs and degree sign never move [I]
  why:   the first row's temperature is the one in the mockup the visionary chose; the other two temperatures are the interviewer's, not yet put [I]
  spread: Reading the values in the menu bar
  sib:   D90
  serves: N0 N5
  touches: D43 D85 D86

D90 2026-10-18 [I] ! amends D44
  pre:   the menu bar item has been showing CPU `7%`, GPU `0%`, RAM `9%` and `35°C` [I>V]
  trig:  the readings change to CPU, GPU, RAM and temperature at {7%, 0%, 9%, 35 °C | 100%, 100%, 100%, 105 °C | 0%, 100%, 0%, 61 °C} [I]
  resp:  the item keeps the same width, which always leaves room for a hundred percent on all three and a three-digit temperature, so the menu bar icons to its left do not move [I>V]
  why:   the rows are the interviewer's extremes; the temperatures are the interviewer's, not yet put [I]
  spread: The menu bar item keeps one width
  serves: N0 N5
  touches: D44 D89

D91 2026-10-18 [I>V] ! amends D78
  pre:   the menu bar item is live, and then no fresh {CPU | GPU | RAM | temperature} reading arrives [I>V]
  trig:  {3 seconds} pass without one [I>V]
  resp:  that value shows as a dash, as in `GPU   –%` or `  –°C`, until a fresh reading arrives, while the other values stay live [I>V]
  why:   three seconds is three missed refreshes at the rate D79 sets, the interviewer's pick, chosen; the temperature row follows the option text the visionary chose, which named the dash [I>V]
  spread: A value with no fresh reading turns into a dash
  serves: N0 N5
  touches: D78 D88

D92 2026-10-18 [V] ratifies D89
  resp:  the menu bar rows with the temperatures of ninety-eight, sixty-one and thirty-five degrees are right [V]
  touches: D89

D93 2026-10-18 [V] ratifies D90
  resp:  the width rows with the temperature extremes, up to a hundred and five degrees, are right [V]
  touches: D90

D94 2026-10-18 [V] ratifies N5
  resp:  the network, disk and temperature need is right as worded, at weight two [V]
  touches: N5

D95 2026-10-18 [I>V]
  pre:   Activity Monitor reads Data received/sec, Data sent/sec, Data read/sec and Data written/sec of {0 bytes, 0 bytes, 0 bytes, 0 bytes | 112.4 MB, 0.3 MB, 210.0 MB, 1.2 GB} [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  below the legend the panel reads {`Net ↓ 0.0 KB/s ↑ 0.0 KB/s` and `Disk R 0.0 KB/s W 0.0 KB/s` | `Net ↓ 112.4 MB/s ↑ 0.3 MB/s` and `Disk R 210.0 MB/s W 1.2 GB/s`}: one decimal, the unit growing from KB/s to MB/s to GB/s with the number, and each value the one Activity Monitor shows for the whole Mac in its Network and Disk tabs [I>V]
  why:   the rows are the interviewer's idle floor and the busy mockup values; the format and the pin are the interviewer's pick, offered labeled as such and chosen [I>V]
  spread: Network and disk match Activity Monitor
  sib:   D91
  serves: N5
  touches: D85 D50
# evidence: Activity Monitor's ActivityMonitor.loctable and nib carry `Data received/sec`, `Data sent/sec`, `Data read/sec` and `Data written/sec`
# roads not taken: the same format with no pin to Activity Monitor; network in megabits per second; always megabytes per second

D96 2026-10-18 [I>V]
  resp:  network, disk and temperature show only their current values; they keep no history, and the five-minute graph stays CPU, GPU and RAM [I>V]
  ->     need N5
  touches: D85 D50 D66
# roads not taken: a second small five-minute graph for network and disk speed and temperature

D97 2026-10-18 [I>V] ! amends D91
  pre:   the meter is live, and then no fresh {CPU | GPU | RAM | temperature | network | disk} reading arrives [I>V]
  trig:  {3 seconds} pass without one [I>V]
  resp:  that value shows as a dash, as in `GPU   –%`, `  –°C` or `↓ –`, until a fresh reading arrives, while the other values stay live [I>V]
  why:   three seconds is three missed refreshes at the rate D79 sets, the interviewer's pick, chosen; the network and disk rows were the interviewer's view, offered and accepted [I>V]
  spread: A value with no fresh reading turns into a dash
  serves: N0 N5
  touches: D91 D95

D98 2026-10-18 [I>V]
  pre:   the panel is closed, and any app is in front [I>V]
  trig:  the visionary presses Control-Option-Command-M [I>V]
  resp:  the panel opens exactly as if the menu bar item had been clicked; pressing the same combination again, or Esc, closes it [I>V]
  sib:   none -- a taken combination was checked away
  serves: N0 N1
  touches: D50 D59
# Phase 3.25 domain question, interviewer's priors named as such
# rule 6: the visionary first picked Option-Command-M, whose option text the interviewer had written as rarely used; Apple's shortcut page, support.apple.com/en-us/102650, reads "To minimize all windows of the front app, press Option-Command-M", so the premise fell and the choice went back as a fresh decision point
# evidence: the same page lists no Control-Option-Command shortcut with a letter key, only with eight, comma, period and the power button
# roads not taken: Option-Command-M anyway, taking over minimize-all in every app; a combination the visionary sets in the meter

# Phase 3.5 adversarial pass (2026-10-18), objections put one at a time, strongest first.

D99 2026-10-18 [I>V] ! amends D56
  pre:   a task that is part of macOS itself, such as `loginwindow`, `Dock` or `Finder`, or one not running as the visionary's own user, such as `WindowServer` or `kernel_task`, is among the top five by CPU [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the task is listed in its CPU rank and counts toward the five rows, marked `system`, with no `End` button, whoever it runs as; a task is part of macOS itself when its program lives in macOS's own `/System` folders; every other task running as the visionary keeps its `End` button, `node` and Xcode included [I>V]
  sib:   D57
  serves: N1
  touches: D56 D57 D61
# objection 1: `ps` shows loginwindow, WindowManager, ControlCenter, SystemUIServer, Dock and Finder all running as linus, so D56 gave them End buttons; ending loginwindow ends the login session, standard macOS behaviour not tested here
# evidence: `ps -axo comm` shows Dock, Finder, loginwindow, ControlCenter and WindowManager all under /System/Library/CoreServices; `node` runs from ~/.nvm
# this reverses D56's clause that Finder and Dock keep their End buttons
# roads not taken: a short named list of session-ending tasks, loginwindow among them; keeping D56 as it was

D100 2026-10-18 [I>V] amends D25
  resp:  while the panel is open, the heavy-tasks list re-ranks by CPU on every refresh, even under the pointer, except while the pointer rests on a row's `End` button: that row keeps its task for as long as the pointer stays there, its numbers still updating [I>V]
  ->     need N1
  touches: D25 D60 D99
# objection 2: rows swapping at the click and End with no confirmation could end a windowless task the visionary did not choose; the visionary asked for the interviewer's view, and the hold was offered labeled as the interviewer's pick, named as narrowing D25, and chosen
# roads not taken: keeping D25 and D60 as they were; naming the task on the button after the click

D101 2026-10-18 [I>V]
  pre:   the pointer rests on the `End` button of Xcode's row, and `node` is just below it [I>V]
  trig:  `node` passes Xcode on CPU at the next refresh [I>V]
  resp:  the row under the pointer still shows Xcode with its updated numbers; once the pointer leaves the button, the list re-ranks and `node` moves above Xcode [I>V]
  sib:   none -- the pointer leaving is the release case
  serves: N1
  touches: D100 D60

D102 2026-10-18 [I>V] reaffirms D32
  resp:  what happens when the menu bar is too crowded for the meter beside the notch stays out of scope, now that the item carries four fields [I>V]
  touches: D32 D89 N3
# objection 3: the wider item may be hidden beside the notch, defeating the heaviest need; the visionary asked for the interviewer's view; fence plus a named assumption was offered labeled as the interviewer's pick and chosen
# the compact fallback was flagged as resting on an unverified claim, that macOS tells an app it is hidden
# roads not taken: the fence alone; a compact form when crowded, reversing D32; dropping temperature from the bar

D103 2026-10-18 [I>V]
  resp:  the visionary keeps enough room on the built-in screen's menu bar for the meter's full width [I>V]
  ->     fence-assumption room-in-the-menu-bar
  touches: D102 D89 D90
# reopening condition: the visionary finds the meter missing from the built-in screen's menu bar

D104 2026-10-18 [I>V]
  pre:   the visionary clicked `Quit Meter` [I>V]
  trig:  `60 seconds` pass [I>V]
  resp:  the meter is still not in the menu bar; it returns only at the visionary's next login, never by the crash return that D77 rules [I>V]
  sib:   none -- the crash case is D77's
  serves: N0
  touches: D65 D77 D42
# objection 4: nothing pinned a quit apart from a crash; rendered as a candidate scenario and accepted

D105 2026-10-18 [I>V]
  pre:   the visionary clicked `End` on Xcode in the second row and moved the pointer away [I>V]
  trig:  Xcode drops to the fourth row at the next refresh [I>V]
  resp:  `Ending…`, and later `Force Quit`, stays on Xcode's row wherever it moves; the task now in the second row shows an ordinary `End` button [I>V]
  sib:   none -- the state follows the task
  serves: N1
  touches: D60 D62 D100
# objection 5: nothing pinned the ending state to the task rather than the row position; rendered as a candidate scenario and accepted

D106 2026-10-18 [I>V] amends D55
  pre:   seven tasks are running at CPU `30%`, `25%`, `20%`, `15%`, `10%`, `5%` and `1%`; the one at `5%` uses the most RAM of all, and the one at `1%` uses the most GPU of all [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the list shows the five tasks at `30%`, `25%`, `20%`, `15%` and `10%` in that order, ranked by CPU alone, and below them the biggest GPU user tagged `GPU` and the biggest RAM user tagged `RAM`, each with its `End` button; a biggest GPU or RAM user already among the five gets no extra row, so the list holds five to seven rows, and a `system` task in an extra row keeps no `End` button as D99 rules [I>V]
  sib:   D99
  serves: N1
  touches: D55 D59 D60 D99 D58
# objection 6: a GPU or RAM hog with little CPU never reached the list; the visionary asked for the interviewer's view; the two extra rows were offered labeled as the interviewer's pick and chosen, knowingly amending D55's exactly-five rule
# roads not taken: CPU only with Activity Monitor for the rest; ranking by each task's highest of CPU, GPU and RAM

D107 2026-10-18 [I>V]
  pre:   a task uses {6.4 GB | 16 GB | 32 GB} of RAM on this Mac's `32 GB` [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  that task's RAM value reads {`20.0%` | `50.0%` | `100.0%`}, its share of the Mac's physical memory, counted the way D47 counts the whole Mac [I>V]
  why:   the rule came with the interviewer's pick for objection six; the rows are the interviewer's spread on this Mac's memory [I>V]
  spread: A task's RAM is its share of the Mac's memory
  sib:   none -- the full-memory row is the cap
  serves: N1
  touches: D47 D106 D54

D108 2026-10-18 [I>V] amends D106
  pre:   seven tasks are running at CPU `30%`, `25%`, `20%`, `15%`, `10%`, `5%` and `1%`; the one at `5%` uses the most RAM of all at `40.0%`, and the one at `1%` uses the most GPU of all at `90.0%` [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  the list shows the five tasks at `30%`, `25%`, `20%`, `15%` and `10%` in that order, ranked by CPU alone, and below them the biggest GPU user tagged `GPU` and the biggest RAM user tagged `RAM`, each with its `End` button; an extra row appears only when its task uses over a tenth of the GPU or of the Mac's memory as D109 rules, and a biggest GPU or RAM user already among the five gets no extra row, so the list holds five to seven rows; a `system` task in an extra row keeps no `End` button as D99 rules [I>V]
  sib:   D109
  serves: N1
  touches: D106 D99

D109 2026-10-18 [I>V] !
  pre:   the biggest {GPU | GPU | RAM | RAM} user is not among the five CPU rows and uses {9.9% | 10.1% | 9.9% | 10.1%} of the {GPU | GPU | Mac's memory | Mac's memory} [I>V]
  trig:  the visionary opens the panel [I>V]
  resp:  its extra row is {absent | shown | absent | shown}; a quiet Mac shows just the five CPU rows [I>V]
  why:   a tenth is the interviewer's pick, offered labeled as such and chosen, high enough to keep a quiet Mac's list clean and low enough to catch a task holding a few gigabytes of this Mac's memory; the rows straddle it [I>V]
  spread: An extra row appears only for a real GPU or RAM hog
  sib:   D99
  serves: N1
  touches: D108 D107
# roads not taken: over a quarter of the GPU or memory; always, even at a tenth of a percent

D110 2026-10-18 [I>V] ! amends D61
  pre:   `node` has used `95%` of the Mac's CPU for the last `60 minutes`, and the visionary has clicked nothing in the meter [I>V]
  trig:  another minute passes [I>V]
  resp:  `node` is still running, and its row still has an ordinary `End` button, with no colour, icon, highlight, warning or prompt urging the visionary to end it; the only words a row may carry beyond its name and values are the plain `GPU`, `RAM` or `system` tags in the row's own style, which say why it is listed or why it has no `End` [I>V]
  serves: N1
  touches: D61 D2 D108 D99
# objection 7: the GPU and RAM tags of D108 read as the flagging D2 declined; the interviewer named it as a contradiction rule 7 should have caught before the ruling; the visionary asked for the interviewer's view; tags as plain reasons with D61 restated was offered labeled as the interviewer's pick and chosen
# roads not taken: extra rows with no tags; dropping the extra rows, reversing objection six

D111 2026-10-18 [I>V]
  resp:  a per-core breakdown of CPU use is not scoped [I>V]
  ->     fence-declined per-core-breakdown
  touches: D54
# Phase 3.25 domain question: the per-core breakdown was offered from the interviewer's priors and left unticked; recorded at the Phase 4 fence readback, where it was found missing

# Drafting (2026-10-18): fixes made while writing the feature files, content unchanged.

D112 2026-10-18 [I>V] amends D88
  pre:   the Mac has sat idle, and the menu bar shows the chip temperature [I>V]
  trig:  one task fully uses every CPU core for `2 minutes` [I>V]
  resp:  the temperature shown at the end is higher than the one shown at idle; no figure from macOS exists to check it against, so its rising under load is the whole check [I>V]
  sib:   none -- a failed reading is the dash case
  serves: N5
  touches: D88 D97
# drafting fix: D88 braced a single load length, and a one-row outline fails the feature lint; the length is restated as a backticked example and the scenario is a plain one

D113 2026-10-18 [I>V] amends D66
  resp:  tracking means the current CPU, GPU and RAM usage plus a look back over the last five minutes; nothing is kept once it falls out of that window [I>V]
  why:   the visionary picked the window from options of one, five, fifteen and sixty minutes [I>V]
  ->     need N0
  touches: D66 D50 D53
# drafting fix: a need-resolving entry cannot be cited by a scenario tag, so its spread line could never be satisfied; the window's spread is carried by D50 and D53, which share the outline

# Cold gate, after the read (2026-10-19): the visionary read the contract at normal depth with no corrections; the held findings were then put one at a time.

D114 2026-10-19 [I>V] ! amends D97
  pre:   the meter is live, and then no fresh {CPU | GPU | RAM | temperature | network | disk} reading arrives [I>V]
  trig:  {3 seconds} pass without one [I>V]
  resp:  that value shows as {`CPU   –%` | `GPU   –%` | `RAM   –%` | `  –°C` | `Net ↓ – ↑ –` | `Disk R – W –`} until a fresh reading arrives, a network or disk reading dashing its whole line since both halves come from one reading, while the other values stay live [I>V]
  why:   three seconds is three missed refreshes at the rate D79 sets; the CPU, RAM and whole-line rows were derived by the interviewer, held at the cold gate, and the whole-line dash was offered labeled as the interviewer's pick and chosen [I>V]
  spread: A value with no fresh reading turns into a dash
  serves: N0 N5
  touches: D97 D95
# roads not taken: dashing only the stale half of a network or disk line

D115 2026-10-19 [I>V] amends D79
  pre:   the menu bar item reads {CPU 20% | CPU 80% | CPU 0% | GPU 0% | RAM 40% | 45°C} [I>V]
  trig:  that reading moves to {80% | 20% | 100% | 90% | 60% | 70 °C} and stays there [I>V]
  resp:  the item shows the new value within {1 second}, for GPU, RAM and the temperature as for CPU [I>V]
  why:   the visionary picked the one-second refresh from options; the CPU rows were accepted as a table; the GPU, RAM and temperature rows were the interviewer's, held at the cold gate, and offered labeled as the interviewer's pick and chosen [I>V]
  spread: The readout follows a change within a second
  sib:   D114
  serves: N0 N5
  touches: D79 D114 D73
# roads not taken: CPU only, leaving the other values' refresh to the build

D116 2026-10-19 [V] signs D115
  resp:  the visionary read the contract at normal depth with no corrections, ruled the two held findings, and signs it as of this entry [V]
  touches: D115
