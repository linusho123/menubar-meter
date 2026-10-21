/// The hold under a resting pointer (D100, D101), and what happens when the held task leaves.
///
/// A row whose End button the pointer rests on stays where it is (held). When the held task
/// goes, the list refills at once (D60), but the End button that slides under the still pointer
/// is not the one the user chose: it stays greyed out (disarmed) until the pointer has left the
/// button, so one more click cannot end a task nobody picked.
public struct PointerHold: Equatable, Sendable {
  public struct Held: Equatable, Sendable {
    public var id: TaskID
    public var index: Int
  }

  /// The row held, nil when the pointer rests on no End button or the held task has gone.
  public private(set) var held: Held?
  /// The row whose End button is greyed out until the pointer leaves it.
  public private(set) var disarmed: Int?

  public init() {}

  /// Follows the pointer: `resting` is the row whose End button it rests on (nil when none),
  /// `shown` the task in each row. Returns whether a held row was let go, so the list must be
  /// ranked afresh.
  public mutating func follow(resting: Int?, shown: [TaskID]) -> Bool {
    if let resting, resting < shown.count {
      if disarmed == resting { return false }
      disarmed = nil
      if held?.index != resting { held = Held(id: shown[resting], index: resting) }
      return false
    }
    disarmed = nil
    guard held != nil else { return false }
    held = nil
    return true
  }

  /// The held task is no longer in the list: nothing is held, and the End button that takes its
  /// place under the pointer is greyed out until the pointer leaves it.
  public mutating func heldTaskLeft() {
    guard let held else { return }
    disarmed = held.index
    self.held = nil
  }

  /// Whether the End button in row `index` may be clicked as far as the hold goes.
  public func isArmed(row index: Int) -> Bool { disarmed != index }

  /// Forgets everything: the panel closed or opened.
  public mutating func reset() {
    held = nil
    disarmed = nil
  }
}
