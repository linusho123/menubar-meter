import Testing

@testable import MeterCore

@Suite("The hold under a resting pointer, and the End that slides under it (D100, D60)")
struct PointerHoldTests {
  private let a = TaskID(pid: 10, started: 1)
  private let b = TaskID(pid: 11, started: 1)
  private let c = TaskID(pid: 12, started: 1)

  private func step(_ hold: inout PointerHold, _ resting: Int?, _ shown: [TaskID]) -> Bool {
    hold.follow(resting: resting, shown: shown)
  }

  @Test("a pointer resting on an End button holds that row; leaving it lets the row go")
  func holdsAndReleases() {
    var hold = PointerHold()
    #expect(step(&hold, 1, [a, b, c]) == false)
    #expect(hold.held?.id == b)
    #expect(hold.held?.index == 1)
    #expect(step(&hold, nil, [a, b, c]) == true)
    #expect(hold.held == nil)
    #expect(step(&hold, nil, [a, b, c]) == false)
  }

  @Test(
    "the held task leaves under the pointer: the newcomer's End is disarmed until the pointer leaves"
  )
  func newcomerIsDisarmed() {
    var hold = PointerHold()
    _ = hold.follow(resting: 1, shown: [a, b, c])
    // The held task b exits; the list refills and c slides into row 1 under the still pointer.
    hold.heldTaskLeft()
    #expect(hold.held == nil)
    #expect(!hold.isArmed(row: 1))
    // The next ticks, the pointer unmoved: the newcomer is not held, and stays disarmed.
    #expect(step(&hold, 1, [a, c]) == false)
    #expect(hold.held == nil)
    #expect(!hold.isArmed(row: 1))
    // Other rows are not affected.
    #expect(hold.isArmed(row: 0))
    // The pointer leaves the button: armed again, and nothing needs re-ranking.
    #expect(step(&hold, nil, [a, c]) == false)
    #expect(hold.isArmed(row: 1))
    // Back onto it: clickable, and held as any row under the pointer.
    #expect(step(&hold, 1, [a, c]) == false)
    #expect(hold.isArmed(row: 1))
    #expect(hold.held?.id == c)
  }

  @Test("moving straight onto another row's button arms the slot and holds the other row")
  func movingToAnotherButton() {
    var hold = PointerHold()
    _ = hold.follow(resting: 1, shown: [a, b, c])
    hold.heldTaskLeft()
    #expect(step(&hold, 0, [a, c]) == false)
    #expect(hold.isArmed(row: 1))
    #expect(hold.held?.id == a)
  }

  @Test("with nothing held, a task leaving disarms nothing")
  func nothingHeld() {
    var hold = PointerHold()
    hold.heldTaskLeft()
    #expect(hold.isArmed(row: 0))
    #expect(hold.isArmed(row: 1))
  }

  @Test("the panel closing forgets the hold and the disarmed slot")
  func resets() {
    var hold = PointerHold()
    _ = hold.follow(resting: 1, shown: [a, b, c])
    hold.heldTaskLeft()
    hold.reset()
    #expect(hold.held == nil)
    #expect(hold.isArmed(row: 1))
  }
}
