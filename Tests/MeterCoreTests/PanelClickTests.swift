import Testing

@testable import MeterCore

private final class Signals: TaskSignals {
  var tasks: [Int32: RunningTask] = [:]
  var sent: [EndRequest] = []
  let userID: UInt32 = 501
  let ownPID: Int32 = 4242
  func running(pid: Int32) -> RunningTask? { tasks[pid] }
  func isApp(pid: Int32) -> Bool { false }
  func send(_ request: EndRequest, to id: TaskID) { sent.append(request) }
  func resolve(path: String) -> String? { path }

  @discardableResult
  func run(_ pid: Int32, started: UInt64) -> TaskID {
    let id = TaskID(pid: pid, started: started)
    tasks[pid] = RunningTask(id: id, uid: 501, path: "/Users/me/bin/task")
    return id
  }
}

private final class CountingInputs: TaskInputs {
  var snapshots = 0
  var cpuCores = 10
  var physicalMemory: UInt64 = 32 << 30
  var userID: UInt32 = 501
  var ownPID: Int32 = 4242
  func snapshot() -> TaskSnapshot? {
    snapshots += 1
    return TaskSnapshot(
      processes: [
        ProcessSample(
          id: TaskID(pid: 700, started: 1000), name: "task", uid: 501, path: "/Users/me/bin/task",
          cpuTime: UInt64(snapshots) * 1_000, memory: 1)
      ], gpuTimes: [:], gpuBusy: nil)
  }
  func resolve(path: String) -> String? { path }
}

@Suite("A click on a row whose task was replaced refreshes the list at once (Q4, 2026-10-20)")
struct PanelClickTests {
  /// A sampler that has measured twice, the last at `at`.
  private func primed(_ inputs: CountingInputs, at: Double) -> TaskSampler {
    let sampler = TaskSampler(inputs: inputs)
    sampler.sample(now: at - 1)
    sampler.sample(now: at)
    return sampler
  }

  @Test("a stale press takes exactly one more snapshot and says to redraw")
  func stale() {
    let system = Signals()
    let inputs = CountingInputs()
    let sampler = primed(inputs, at: 10)
    system.run(700, started: 1500)
    let before = inputs.snapshots
    let redraw = PanelClick.end(
      TaskID(pid: 700, started: 1000), ender: TaskEnder(signals: system), sampler: sampler,
      now: 11)
    #expect(redraw)
    #expect(inputs.snapshots == before + 1)
    #expect(system.sent.isEmpty)
  }

  @Test("a stale press on a task that has gone takes one more snapshot too")
  func gone() {
    let inputs = CountingInputs()
    let sampler = primed(inputs, at: 10)
    let before = inputs.snapshots
    PanelClick.end(
      TaskID(pid: 700, started: 1000), ender: TaskEnder(signals: Signals()), sampler: sampler,
      now: 11)
    #expect(inputs.snapshots == before + 1)
  }

  @Test("a stale press 0.1 s after a sample still takes a snapshot, past the throttle")
  func pastThrottle() {
    let system = Signals()
    let inputs = CountingInputs()
    let sampler = primed(inputs, at: 10)
    system.run(700, started: 1500)
    let before = inputs.snapshots
    let redraw = PanelClick.end(
      TaskID(pid: 700, started: 1000), ender: TaskEnder(signals: system), sampler: sampler,
      now: 10.1)
    #expect(redraw)
    #expect(inputs.snapshots == before + 1)
  }

  @Test("a sent press takes no snapshot")
  func sent() {
    let system = Signals()
    let inputs = CountingInputs()
    let sampler = primed(inputs, at: 10)
    let id = system.run(700, started: 1000)
    let before = inputs.snapshots
    let redraw = PanelClick.end(id, ender: TaskEnder(signals: system), sampler: sampler, now: 11)
    #expect(!redraw)
    #expect(inputs.snapshots == before)
    #expect(system.sent == [.terminate])
  }

  @Test("a second click while Ending… takes no snapshot")
  func ignored() {
    let system = Signals()
    let inputs = CountingInputs()
    let sampler = primed(inputs, at: 10)
    let id = system.run(700, started: 1000)
    let ender = TaskEnder(signals: system)
    PanelClick.end(id, ender: ender, sampler: sampler, now: 11)
    let before = inputs.snapshots
    let redraw = PanelClick.end(id, ender: ender, sampler: sampler, now: 12)
    #expect(!redraw)
    #expect(inputs.snapshots == before)
    #expect(system.sent == [.terminate])
  }
}
