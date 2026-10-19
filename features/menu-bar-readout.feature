Feature: The menu bar readout
  One line of labeled text in the menu bar near Control Center shows how
  hard this Mac is working: CPU, GPU and RAM as whole-number percentages,
  then the chip temperature in degrees Celsius. It refreshes every second,
  keeps one width so nothing beside it moves, and its numbers agree with
  what Activity Monitor and macOS report.

  @D89
  Scenario Outline: Reading the values in the menu bar
    Given the Mac is running with CPU at <cpu>, GPU at <gpu>, RAM at <ram> and the chip at <temp>
    When the user looks at the menu bar
    Then the user sees the item near Control Center read exactly "<text>"

    Examples:
      | cpu  | gpu  | ram | temp   | text                             |
      | 100% | 7%   | 93% | 98 °C  | CPU 100%  GPU   7%  RAM  93%   98°C |
      | 7%   | 100% | 9%  | 61 °C  | CPU   7%  GPU 100%  RAM   9%   61°C |
      | 0%   | 0%   | 0%  | 35 °C  | CPU   0%  GPU   0%  RAM   0%   35°C |

  @D90
  Scenario Outline: The menu bar item keeps one width
    Given the menu bar item has been showing CPU 7%, GPU 0%, RAM 9% and 35°C
    When the readings change to CPU <cpu>, GPU <gpu>, RAM <ram> and <temp>
    Then the item's width in the menu bar is unchanged
    And the menu bar icons to the item's left have not moved

    Examples:
      | cpu  | gpu  | ram  | temp   |
      | 7%   | 0%   | 9%   | 35 °C  |
      | 100% | 100% | 100% | 105 °C |
      | 0%   | 100% | 0%   | 61 °C  |

  @D115
  Scenario Outline: The readout follows a change within a second
    Given the menu bar item reads <reading> at <before>
    When the Mac's <reading> moves to <after> and stays there
    Then within 1 second the user sees the item's <reading> value read "<after>"

    Examples:
      | reading     | before | after |
      | CPU         | 20%    | 80%   |
      | CPU         | 80%    | 20%   |
      | CPU         | 0%     | 100%  |
      | GPU         | 0%     | 90%   |
      | RAM         | 40%    | 60%   |
      | temperature | 45°C   | 70°C  |

  @D46
  Scenario Outline: Rounding the menu bar readout
    Given the Mac's CPU use is <actual>
    When the menu bar item refreshes
    Then the user sees the item's CPU value read "<shown>"

    Examples:
      | actual | shown |
      | 0%     | 0%    |
      | 0.4%   | 0%    |
      | 7.5%   | 8%    |
      | 99.6%  | 100%  |
      | 100%   | 100%  |

  @D47
  Scenario Outline: RAM matches Activity Monitor's Memory Used
    Given this Mac has 32 GB of memory
    And Activity Monitor reads Memory Used of <used>, with reusable cache held besides
    When the menu bar item refreshes
    Then the user sees the item's RAM value read "<shown>"

    Examples:
      | used    | shown |
      | 18.0 GB | 56%   |
      | 0.5 GB  | 2%    |
      | 31.9 GB | 100%  |

  @D48
  Scenario: CPU matches Activity Monitor's total load
    Given Activity Monitor's CPU tab reads System "12.0%" and User "30.5%" at the same moment
    When the menu bar item refreshes
    Then the user sees the item's CPU value read "43%"

  @D49
  Scenario: GPU is macOS's own overall GPU reading
    Given macOS reports its overall GPU utilization as "4%"
    When the menu bar item refreshes
    Then the user sees the item's GPU value read "4%"

  @D114
  Scenario Outline: A value with no fresh reading turns into a dash
    Given the meter is live
    And no fresh <reading> reading arrives
    When 3 seconds pass without one
    Then the user sees that value shown as "<dash>"
    And the user sees the other values still updating

    Examples:
      | reading     | dash          |
      | CPU         | CPU   –%      |
      | GPU         | GPU   –%      |
      | RAM         | RAM   –%      |
      | temperature | –°C           |
      | network     | Net ↓ – ↑ –   |
      | disk        | Disk R – W –  |

  @D112
  Scenario: The temperature rises under load
    Given the Mac has sat idle and the menu bar shows the chip temperature
    When one task fully uses every CPU core for 2 minutes
    Then the temperature the user sees at the end is higher than the one shown at idle
