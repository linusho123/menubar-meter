Feature: The meter's own cost
  The meter must cost the Mac almost nothing, so it never adds to the load
  it shows. Its own CPU, memory and energy stay under fixed lines, checked
  from outside the meter.

  @D73
  Scenario Outline: The meter's own CPU stays under its line
    Given the meter is running with its panel <panel>, refreshing every second
    When a minute passes
    Then the meter's own CPU use over that minute, as a share of the whole Mac measured outside the meter, is under <line>

    Examples:
      | panel  | line |
      | closed | 1%   |
      | open   | 5%   |

  @D76
  Scenario Outline: The meter's memory stays under its line
    Given the meter has been running without a restart for <time>
    When the user looks at the meter's row in Activity Monitor's Memory tab
    Then the user sees its Memory value under 50 MB, after <time>

    Examples:
      | time    |
      | 1 hour  |
      | 7 days  |

  @D75
  Scenario: The meter is never flagged as an energy hog
    Given the Mac is on battery and the meter has been running all day
    When the user opens the battery menu
    Then the user does not see the meter listed under "Apps Using Significant Energy"
