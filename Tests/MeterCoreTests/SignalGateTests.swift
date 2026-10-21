import Testing

@testable import MeterCore

@Suite("The last start-time re-read before a signal (D99, D105)")
struct SignalGateTests {
  private let id = TaskID(pid: 700, started: 1000)

  @Test("a matching start time may be signalled")
  func match() {
    #expect(SignalGate.mayDeliver(id, startTime: { _ in 1000 }))
  }

  @Test("a different start time at the last re-read sends nothing")
  func mismatch() {
    #expect(!SignalGate.mayDeliver(id, startTime: { _ in 2000 }))
  }

  @Test("a process id that no longer runs sends nothing")
  func gone() {
    #expect(!SignalGate.mayDeliver(id, startTime: { _ in nil }))
  }

  @Test(
    "process 0, 1 and below are never signalled, whatever the reader says",
    arguments: [0, 1, -1, -700])
  func neverLowIDs(pid: Int32) {
    #expect(!SignalGate.mayDeliver(TaskID(pid: pid, started: 1000), startTime: { _ in 1000 }))
  }

  @Test("the reader is asked about the row's own process id")
  func readsOwnPID() {
    var asked: [Int32] = []
    _ = SignalGate.mayDeliver(
      id,
      startTime: {
        asked.append($0)
        return 1000
      })
    #expect(asked == [700])
  }
}
