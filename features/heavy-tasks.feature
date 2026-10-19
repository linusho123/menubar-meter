Feature: Heavy tasks
  Below the graph, the panel lists the heavy tasks under the heading
  "heavy tasks", with columns CPU, GPU and RAM, each value to one decimal
  place as that task's share of the whole Mac. The list holds the top five
  by CPU, plus the biggest GPU user and the biggest RAM user when they are
  real hogs. Every task the user may end has an End button; tasks that are
  part of macOS, or not the user's own, are marked "system" and have none.
  The app never nudges the user to end anything, and its last rows open
  Activity Monitor and quit the meter.

  @D108
  Scenario: The top five by CPU, then the biggest GPU and RAM hogs
    Given these tasks are running
      | task     | cpu   | gpu   | ram   |
      | node     | 30.0% | 0.0%  | 3.0%  |
      | Xcode    | 25.0% | 0.0%  | 6.0%  |
      | Safari   | 20.0% | 2.0%  | 4.0%  |
      | Mail     | 15.0% | 0.0%  | 1.0%  |
      | Spotify  | 10.0% | 1.0%  | 2.0%  |
      | Photos   | 5.0%  | 0.0%  | 40.0% |
      | Chrome   | 1.0%  | 90.0% | 4.0%  |
    When the user opens the panel
    Then the user sees the heavy-tasks list read, in order
      | task    | tag | button |
      | node    |     | End    |
      | Xcode   |     | End    |
      | Safari  |     | End    |
      | Mail    |     | End    |
      | Spotify |     | End    |
      | Chrome  | GPU | End    |
      | Photos  | RAM | End    |

  @D109
  Scenario Outline: An extra row appears only for a real GPU or RAM hog
    Given the biggest <kind> user is not among the five CPU rows
    And it uses <share> of the <whole>
    When the user opens the panel
    Then the user sees its extra row tagged "<kind>" is <shown>

    Examples:
      | kind | share | whole            | shown  |
      | GPU  | 9.9%  | GPU              | absent |
      | GPU  | 10.1% | GPU              | listed |
      | RAM  | 9.9%  | Mac's memory     | absent |
      | RAM  | 10.1% | Mac's memory     | listed |

  @D54
  Scenario Outline: A task's CPU is its share of the whole Mac
    Given this Mac has 10 CPU cores
    And one task is fully using <cores> of them
    When the user opens the panel
    Then the user sees that task's row read "<cpu>" under CPU

    Examples:
      | cores | cpu    |
      | 1     | 10.0%  |
      | 4     | 40.0%  |
      | 10    | 100.0% |

  @D107
  Scenario Outline: A task's RAM is its share of the Mac's memory
    Given this Mac has 32 GB of memory
    And one task in the list uses <used> of it
    When the user opens the panel
    Then the user sees that task's row read "<ram>" under RAM

    Examples:
      | used   | ram    |
      | 6.4 GB | 20.0%  |
      | 16 GB  | 50.0%  |
      | 32 GB  | 100.0% |

  @D80
  Scenario Outline: The meter counts against the Mac it runs on
    Given the meter runs on a Mac with <cores> CPU cores
    And one task fully uses all of them
    When the user opens the panel
    Then the user sees that task's row read "100.0%" under CPU, on a Mac of <cores> cores

    Examples:
      | cores |
      | 8     |
      | 10    |
      | 16    |

  @D49
  Scenario: A task's GPU value is Activity Monitor's % GPU for it
    Given Activity Monitor's "% GPU" column reads "12.3" for Safari
    And Safari is in the heavy-tasks list
    When the user opens the panel
    Then the user sees Safari's row read "12.3%" under GPU

  @D99
  Scenario Outline: A macOS or other-user task is listed as system with no End
    Given <task>, whose program <where>, is among the top five by CPU
    When the user opens the panel
    Then the user sees <task> listed in its CPU rank, tagged "system"
    And <task>'s row has no End button

    Examples:
      | task         | where                                        |
      | loginwindow  | lives in /System and runs as the user        |
      | Dock         | lives in /System and runs as the user        |
      | WindowServer | runs as _windowserver, not as the user       |
      | kernel_task  | runs as root, not as the user                |

  @D99
  Scenario: The user's own tasks outside /System keep their End button
    Given node, run as the user from ~/.nvm, and Xcode, run as the user from /Applications, are in the heavy-tasks list
    When the user opens the panel
    Then the user sees an End button on node's row and on Xcode's row

  @D57
  Scenario: The meter in its own list has no End button
    Given the meter itself ranks among the top five tasks by CPU
    When the user opens the panel
    Then the user sees the meter's own row in its CPU rank, tagged "system", with no End button
    And the user still sees the "Quit Meter" row at the bottom of the panel

  @D58
  Scenario: A tie is broken alphabetically
    Given "Notes" and "Maps" both sit at exactly 12.0% CPU, tied for the fifth row
    When the user opens the panel
    Then the user sees "Maps" in the fifth row and "Notes" not in the five CPU rows

  @D101
  Scenario: The row under the pointer holds while it rests on End
    Given the pointer rests on the End button of Xcode's row, and node is just below it
    When node passes Xcode on CPU at the next refresh
    Then the user sees the row under the pointer still show Xcode, with its updated numbers
    And when the pointer leaves the button, the user sees node move above Xcode

  @D110
  Scenario: A long-running hog is never nudged or ended by the app
    Given node has used 95% of the Mac's CPU for the last 60 minutes
    And the user has clicked nothing in the meter
    When another minute passes
    Then Activity Monitor still lists node as running
    And the user sees node's row with an ordinary End button and no colour, icon, highlight, warning or prompt

  @D59
  Scenario: Open Activity Monitor from the panel
    Given the panel is open
    When the user clicks "Open Activity Monitor…" below the heavy-tasks list
    Then the user sees Activity Monitor open in front
    And the panel's own list still shows the top five by CPU
