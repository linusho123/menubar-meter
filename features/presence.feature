Feature: Presence
  The meter is there without being asked: it starts at every login, comes
  back by itself after a crash, and opens its panel from anywhere with
  Control-Option-Command-M. Quit Meter removes it until the next login.
  It installs, and updates, by one install step the user does.

  @D42
  Scenario: The meter appears by itself at login
    Given the user has not opened the meter themselves
    When the user logs in to the Mac after a restart
    Then the user sees the meter's item in the menu bar

  @D65
  Scenario: Quit Meter removes the meter
    Given the meter is in the menu bar and its panel is open
    When the user clicks "Quit Meter", the last row of the panel
    Then the user sees the meter leave the menu bar at once

  @D104
  Scenario: A quit meter stays gone until the next login
    Given the user clicked "Quit Meter"
    When 60 seconds pass
    Then the user sees no meter in the menu bar
    And at the user's next login the user sees the meter in the menu bar again

  @D77
  Scenario Outline: The meter comes back by itself after a crash
    Given the meter is running with its panel <panel>
    When the meter crashes and vanishes from the menu bar
    Then within 10 seconds the user sees the meter back in the menu bar, without doing anything
    And its graph shows no history from before the crash

    Examples:
      | panel  |
      | closed |
      | open   |

  @D98
  Scenario: The shortcut opens and closes the panel from any app
    Given the panel is closed and Safari is in front
    When the user presses Control-Option-Command-M
    Then the user sees the meter's panel open, as if the menu bar item had been clicked
    And when the user presses Control-Option-Command-M again, the user sees the panel close

  @D98
  Scenario: Esc closes the panel opened by the shortcut
    Given the user opened the panel with Control-Option-Command-M
    When the user presses Esc
    Then the user sees the panel close

  @D83
  Scenario: One install step puts the meter in the menu bar
    Given the meter is not on this Mac
    When the user does the one install step
    Then the user sees the meter's item in the menu bar right away, with no settings to fill in
    And at the user's next login the user sees the meter in the menu bar again

  @D84
  Scenario: Installing a newer version replaces the old one
    Given an older version of the meter is installed and starts at login
    When the user does the one install step with a newer version
    Then the user sees the newer version in the menu bar
    And at the user's next login the user sees the newer version start
    And the meter never shows an offer to update itself
