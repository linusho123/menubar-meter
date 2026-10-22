# User needs

Why menubar-meter exists, need by need, and what actually covers each one.
The ledger explains and prioritizes; it never specifies: at build only the
feature files bind. Ids are the docket's. An amended need keeps its first
id, so the glance need is N0 as N3 worded it, and the get-my-machine-back
need is N1 as N4 worded it. The visionary is every stakeholder here: the
only user of this Mac (D3) and the one who runs it.

- **N0** (visionary, wt 5) — *I need to see at a glance how hard my Mac is working, in CPU, GPU and RAM, without opening anything.* Evidence: D113, D18 — the confirmed vision, the tracking ruling as D7 and D113 restated it, and the decimals ruling; served by D89, D90, D79, D46, D47, D48, D49, D97, D50, D53, D51, D52, D42, D65, D104, D77, D83, D84, D98, D81. Means, ruled: an item in the menu bar near Control Center showing the usage as percentages (N3). Tension: N2 — a one-second refresh and four live fields cost the meter something; capped by the own-cost lines. Coverage: `scenario` — menu-bar-readout.feature, recent-history.feature, presence.feature. Note: the item can be hidden beside the notch, fenced as crowded-menu-bar and held by the named assumption room-in-the-menu-bar.

- **N1** (visionary, wt 4) — *When a task is hogging compute, I need to get my machine back.* Evidence: D2, D10, D100 — the visionary ends every task, the list lives below the graph, and the row under End holds; served by D108, D109, D54, D107, D80, D118, D57, D58, D101, D110, D59, D60, D62, D64, D63, D40, D105. Means, ruled: ending that task myself (N4). Coverage: `scenario` — heavy-tasks.feature, ending-tasks.feature. Note: a hog the list misses can still be found and ended through Open Activity Monitor (D59).

- **N2** (visionary, wt 3) — *I need the meter itself to cost my Mac almost nothing, so it does not add to the load it is showing me.* Evidence: D73, D76, D75, D57 — inferred from "small but effective" and accepted at the needs readback; the four own-cost lines were the interviewer's picks, chosen. Tension: N0 and N5 — everything the meter shows each second is work it must do within these lines. Coverage: `scenario` — own-cost.feature.

- **N5** (visionary, wt 2) — *I also want to see my Mac's network and disk activity and how hot it is, beside how hard it is working.* Evidence: D85, D86, D96 — placement, °C and no history; surfaced by the domain question and ratified by the visionary at weight two; served by D89, D90, D97, D117, D112. Coverage: `partial` — network-and-disk.feature and menu-bar-readout.feature; the accepted trade-off is that the temperature has no independent witness on macOS and is checked only by rising under load (temperature-cross-check), with its readability without an admin password held as the named assumption chip-temperature-readable. No other need caps it; the platform does.

## Tensions

- Between N2 and N0, N5: the meter shows six live readings and refreshes every second, yet must cost under a hundredth of the Mac with its panel closed; resolved by fixed lines checked from outside the meter (own-cost.feature).

## Candidate needs from the domain question

Asked at the close of the checklist sweep, from the interviewer's priors,
never from the visionary's answers:

- Network and disk activity, and temperature — taken, as N5.
- A keyboard shortcut to open the panel — taken, as a scenario serving N0 and N1 (presence.feature, D98).
- A per-core CPU breakdown — declined (per-core-breakdown).
