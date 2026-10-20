import Testing

@testable import MeterCore

/// The system as the ender sees it, made up: which tasks run under which process ids, which are
/// apps, and everything sent.
private final class FakeSignals: TaskSignals {
  var tasks: [Int32: RunningTask] = [:]
  var apps: Set<Int32> = []
  var sent: [(EndRequest, Int32)] = []
  let userID: UInt32 = 501
  let ownPID: Int32 = 4242

  func running(pid: Int32) -> RunningTask? { tasks[pid] }
  func isApp(pid: Int32) -> Bool { apps.contains(pid) }
  func send(_ request: EndRequest, to pid: Int32) { sent.append((request, pid)) }
  func resolve(path: String) -> String? { path }

  /// A task the user runs from their own folder, started at `started`.
  @discardableResult
  func run(
    _ pid: Int32, started: UInt64 = 1000, uid: UInt32 = 501,
    path: String? = "/Users/me/bin/task", app: Bool = false
  ) -> TaskID {
    let id = TaskID(pid: pid, started: started)
    tasks[pid] = RunningTask(id: id, uid: uid, path: path)
    if app { apps.insert(pid) } else { apps.remove(pid) }
    return id
  }

  func exit(_ pid: Int32) {
    tasks[pid] = nil
    apps.remove(pid)
  }

  var requests: [EndRequest] { sent.map(\.0) }
}

@Suite("The End state machine (D60, D62, D64)")
struct EndStateTests {
  @Test("End, then Ending…, then gone: the task leaving takes its state with it")
  func endThenGone() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700)
    #expect(ender.button(for: task, now: 10) == .end)
    #expect(ender.click(task, now: 10) == .terminate)
    #expect(ender.button(for: task, now: 10) == .ending)
    #expect(ender.button(for: task, now: 12) == .ending)
    system.exit(700)
    ender.keep(only: [])
    #expect(ender.button(for: task, now: 16) == .end)
    #expect(system.requests == [.terminate])
  }

  @Test("Force Quit at five seconds, not before")
  func forceQuitAtFive() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700)
    ender.click(task, now: 100)
    #expect(ender.button(for: task, now: 100 + 4.999) == .ending)
    #expect(ender.button(for: task, now: 103) == .ending)
    #expect(ender.button(for: task, now: 105) == .forceQuit)
    #expect(ender.button(for: task, now: 160) == .forceQuit)
    #expect(TaskEnder.forceQuitAfter == 5)
  }

  @Test("Force Quit kills outright, once; the button then reads Force Quit and cannot be clicked")
  func forceQuitKills() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700)
    ender.click(task, now: 0)
    #expect(ender.click(task, now: 5) == .kill)
    #expect(ender.button(for: task, now: 5) == .forceQuitSent)
    #expect(ender.button(for: task, now: 5).title == "Force Quit")
    #expect(!ender.button(for: task, now: 5).isClickable)
    #expect(ender.click(task, now: 5.5) == nil)
    #expect(system.requests == [.terminate, .kill])
    #expect(system.sent.allSatisfy { $0.1 == 700 })
  }

  @Test("an app gets its own quit request, a windowless task the terminate signal; never a kill")
  func whatEndSends() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let app = system.run(800, path: "/Applications/Xcode.app/Contents/MacOS/Xcode", app: true)
    let task = system.run(801)
    #expect(ender.click(app, now: 0) == .quitRequest)
    #expect(ender.click(task, now: 0) == .terminate)
    #expect(system.requests == [.quitRequest, .terminate])
  }

  @Test("the button's words: End, Ending…, Force Quit; only End and Force Quit can be clicked")
  func buttonWords() {
    #expect(EndButton.end.title == "End")
    #expect(EndButton.ending.title == "Ending\u{2026}")
    #expect(EndButton.forceQuit.title == "Force Quit")
    #expect(EndButton.end.isClickable)
    #expect(!EndButton.ending.isClickable)
    #expect(EndButton.forceQuit.isClickable)
  }
}

@Suite("A second click while Ending… (D63)")
struct SecondClickTests {
  @Test("is ignored: nothing more is sent, and the button still turns into Force Quit at five")
  func ignored() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700)
    ender.click(task, now: 0)
    #expect(ender.click(task, now: 1) == nil)
    #expect(ender.click(task, now: 4.9) == nil)
    #expect(system.requests == [.terminate])
    // The ignored clicks do not restart the five seconds.
    #expect(ender.button(for: task, now: 5) == .forceQuit)
  }
}

@Suite("The state is keyed to the task, process id and start time (D105)")
struct KeyedStateTests {
  @Test("a reused process id gets no state, and nothing is sent to it")
  func reusedPID() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let old = system.run(700, started: 1000)
    ender.click(old, now: 0)
    // The task ends and another starts under the same process id.
    system.exit(700)
    let new = system.run(700, started: 2000)
    #expect(ender.button(for: new, now: 1) == .end)
    #expect(ender.button(for: new, now: 6) == .end)
    // A click on the old row (shown before the refresh) sends nothing to the new task.
    #expect(ender.click(old, now: 6) == nil)
    #expect(system.requests == [.terminate])
  }

  @Test("End on a row whose task was replaced under its process id sends nothing")
  func replacedBeforeEnd() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let shown = TaskID(pid: 700, started: 1000)
    system.run(700, started: 1500)
    #expect(ender.click(shown, now: 0) == nil)
    #expect(ender.button(for: shown, now: 0) == .end)
    #expect(system.sent.isEmpty)
  }

  @Test("Force Quit on a task replaced under its process id sends nothing and drops the state")
  func replacedBeforeForceQuit() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700, started: 1000)
    ender.click(task, now: 0)
    system.exit(700)
    system.run(700, started: 3000)
    #expect(ender.click(task, now: 6) == nil)
    #expect(ender.button(for: task, now: 6) == .end)
    #expect(system.requests == [.terminate])
  }

  @Test("each task keeps its own state, whatever row it is in")
  func perTask() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let xcode = system.run(800, app: true)
    let node = system.run(801)
    ender.click(xcode, now: 0)
    #expect(ender.button(for: xcode, now: 1) == .ending)
    #expect(ender.button(for: node, now: 1) == .end)
  }
}

@Suite("A task that leaves while showing Force Quit (D40)")
struct LeavingTests {
  @Test("its state goes with it, nothing is sent, and no other task's state changes")
  func leaves() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let leaving = system.run(700)
    let other = system.run(701)
    ender.click(leaving, now: 0)
    #expect(ender.button(for: leaving, now: 5) == .forceQuit)
    system.exit(700)
    ender.keep(only: [other])
    #expect(ender.button(for: leaving, now: 6) == .end)
    #expect(ender.button(for: other, now: 6) == .end)
    #expect(system.requests == [.terminate])
  }

  @Test("a Force Quit click that lands after the task left sends nothing")
  func clickAfterLeaving() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700)
    ender.click(task, now: 0)
    system.exit(700)
    #expect(ender.click(task, now: 5) == nil)
    #expect(system.requests == [.terminate])
  }
}

@Suite("Nothing is ever sent to a system task, checked again at the click (D99, D57)")
struct SendTimeSystemTests {
  @Test(
    "a task that is system when the click lands gets nothing",
    arguments: [
      (uid: UInt32(0), path: "/Users/me/bin/task" as String?),
      (uid: UInt32(88), path: "/System/Library/PrivateFrameworks/SkyLight.framework/WindowServer"),
      (uid: UInt32(501), path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
      (uid: UInt32(501), path: "/usr/libexec/trustd"),
      (uid: UInt32(501), path: "/usr/sbin/cfprefsd"),
      (uid: UInt32(501), path: "/sbin/launchd"),
      (uid: UInt32(501), path: "task"),
      (uid: UInt32(501), path: nil),
      (
        uid: UInt32(501),
        path: "/System/Volumes/Preboot/Cryptexes/App/System/usr/libexec/webpushd"
      ),
    ])
  func system(uid: UInt32, path: String?) {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700, uid: uid, path: path)
    #expect(ender.click(task, now: 0) == nil)
    #expect(ender.button(for: task, now: 0) == .end)
    #expect(system.sent.isEmpty)
  }

  @Test("the meter itself gets nothing")
  func meterItself() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let me = system.run(system.ownPID, path: "/Applications/Meter.app/Contents/MacOS/Meter")
    #expect(ender.click(me, now: 0) == nil)
    #expect(system.sent.isEmpty)
  }

  @Test("an app in the App cryptex's Applications folder (Safari) is the user's to end")
  func cryptexApp() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let safari = system.run(
      900,
      path: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/"
        + "Safari.app/Contents/MacOS/Safari",
      app: true)
    #expect(ender.click(safari, now: 0) == .quitRequest)
  }

  @Test("a task that turned system between the row and the click: Force Quit sends nothing")
  func systemAtForceQuit() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    let task = system.run(700)
    ender.click(task, now: 0)
    system.run(700, uid: 0)
    #expect(ender.click(task, now: 5) == nil)
    #expect(system.requests == [.terminate])
  }

  @Test("process id 0 or below is never signalled")
  func noGroupSignals() {
    let system = FakeSignals()
    let ender = TaskEnder(signals: system)
    for pid: Int32 in [0, -1] {
      let id = TaskID(pid: pid, started: 1)
      system.tasks[pid] = RunningTask(id: id, uid: 501, path: "/Users/me/bin/task")
      #expect(ender.click(id, now: 0) == nil)
    }
    #expect(system.sent.isEmpty)
  }
}
