Feature: Ending tasks
  A task ends only when the user clicks its End button. End asks the task
  to quit the normal way, with no confirmation first, so an app may still
  ask to save. If the task is still running five seconds later the button
  becomes Force Quit, which ends it outright. The ending state belongs to
  the task, wherever its row moves.

  @D60
  Scenario: Ending a task that quits
    Given Xcode is in the heavy-tasks list
    When the user clicks End on Xcode's row
    Then Xcode receives the same quit request its own Quit menu sends, with no confirmation shown by the meter first
    And the user sees Xcode's button read "Ending…" until Xcode is gone
    And once Xcode is gone the user sees its row leave the list and the next-highest CPU task move up into the five CPU rows

  @D62 @D64
  Scenario Outline: Force Quit appears only for a task still running after five seconds
    Given the user clicked End on a task
    When the task <outcome>
    Then the user sees <after>

    Examples:
      | outcome                             | after                                           |
      | quits 2 seconds later               | its row leave the list, with no Force Quit ever |
      | is still running 5 seconds later    | its button turn into "Force Quit"                |

  @D62
  Scenario: Force Quit ends the task outright
    Given a task's button reads "Force Quit"
    When the user clicks "Force Quit"
    Then Activity Monitor no longer lists the task, which was ended at once without being asked
    And the user sees its row leave the list

  @D63
  Scenario: Clicking Ending again does nothing
    Given the user clicked End on a task and its button reads "Ending…"
    When the user clicks the button again before 5 seconds have passed
    Then nothing more happens to the task
    And the user sees the button still read "Ending…" until it becomes "Force Quit" at 5 seconds

  @D40
  Scenario: A task that exits while showing Force Quit just leaves
    Given a task's button reads "Force Quit"
    When the task exits by itself before the user clicks it
    Then the user sees its row leave the list
    And no other task is ended

  @D105
  Scenario: The ending state follows its task when rows move
    Given the user clicked End on Xcode in the second row and moved the pointer away
    When Xcode drops to the fourth row at the next refresh
    Then the user sees "Ending…" on Xcode's row in the fourth row
    And the user sees an ordinary End button on the task now in the second row
