Feature: Recent history
  Clicking the menu bar item drops down a panel whose top is one combined
  graph of the last five minutes: one line each for CPU, GPU and RAM on a
  scale of zero to a hundred percent, with a legend of current values to
  one decimal place. Nothing older than five minutes is shown or kept.

  @D50
  Scenario: Clicking the item opens the five-minute graph
    Given the meter has run for over 5 minutes
    And CPU spiked to 100% about 4.5 minutes ago and is at 100% now
    And GPU has sat at 0% and RAM has held near 93%
    When the user clicks the menu bar item
    Then the user sees a panel drop down with one graph running from "5 min ago" on the left to "now" on the right
    And the graph's scale runs from 0% to 100%
    And the graph has exactly 3 lines: CPU, GPU and RAM
    And the CPU line reaches 100% near the graph's left edge
    And the legend reads "CPU 100.0%  GPU 0.0%  RAM 93.0%"

  @D50 @D53
  Scenario Outline: A spike stays in the graph only while it is under five minutes old
    Given CPU spiked to 100% <age> ago and has stayed under 10% since
    When the user opens the panel
    Then the spike the user sees is <where>

    Examples:
      | age                  | where                          |
      | 4.5 minutes          | near the graph's left edge     |
      | 5 minutes 10 seconds | nowhere in the graph           |

  @D51
  Scenario: A history shorter than the window leaves the graph's left empty
    Given the meter has been running for only 30 seconds
    When the user opens the panel
    Then the user sees the graph's axis still run from "5 min ago" to "now"
    And the lines cover only the last 30 seconds at the right edge
    And the rest of the graph is empty

  @D52
  Scenario: The time the Mac slept is a gap in the graph
    Given the meter was running, then the Mac slept for 2 minutes and woke within the last 5 minutes
    When the user opens the panel
    Then the user sees no line for the 2 minutes the Mac was asleep
    And the lines stop where it went to sleep and resume where it woke
