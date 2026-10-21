/// What a row's End button reads and whether it can be clicked (D60, D62, D63).
public enum EndButton: Equatable, Sendable {
  /// `End`: nothing has been asked of the task.
  case end
  /// `Ending…`: the task was asked to quit under five seconds ago; the button cannot be clicked.
  case ending
  /// `Force Quit`: the task was asked to quit five seconds ago or more and still runs.
  case forceQuit
  /// `Force Quit`, clicked: the task was ended outright and is leaving; nothing more is sent.
  case forceQuitSent

  public var title: String {
    switch self {
    case .end: "End"
    case .ending: "Ending\u{2026}"
    case .forceQuit, .forceQuitSent: "Force Quit"
    }
  }

  public var isClickable: Bool {
    self == .end || self == .forceQuit
  }
}

/// What the ender sends a task.
public enum EndRequest: Equatable, Sendable {
  /// An app's own quit request, the one its Quit menu item answers, so it may still ask to save.
  case quitRequest
  /// The terminate signal, the normal quit for a task with no app of its own.
  case terminate
  /// The kill: the task ends at once, without being asked.
  case kill
}

/// A task as the system knows it at the moment something is about to be sent to it.
public struct RunningTask: Equatable, Sendable {
  public var id: TaskID
  public var uid: UInt32
  public var path: String?

  public init(id: TaskID, uid: UInt32, path: String?) {
    self.id = id
    self.uid = uid
    self.path = path
  }
}

/// What the ender asks of the system: the task running now under a process id, read afresh;
/// whether it is an app; and the sending itself.
public protocol TaskSignals: AnyObject {
  /// The task running now with this process id, its start time read again after its path so
  /// the two belong to one task; nil when none runs or it cannot be read.
  func running(pid: Int32) -> RunningTask?
  /// Whether the task with this process id is an app, which takes the quit request.
  func isApp(pid: Int32) -> Bool
  /// Sends `request` to the task with this process id.
  func send(_ request: EndRequest, to pid: Int32)
  /// The user the meter runs as.
  var userID: UInt32 { get }
  /// The meter's own process id.
  var ownPID: Int32 { get }
  /// A program's path with every symbolic link resolved, nil when it cannot be resolved.
  func resolve(path: String) -> String?
}

/// The ender (D60, D62, D63, D40, D105): each task's ending state, keyed to the task (its
/// process id and start time), never to a row, and the only place anything is sent to a task.
/// Nothing is ever sent unless the task running under that process id now is the very task the
/// row showed, started at the same moment, and is not `system` (D99, D57).
public final class TaskEnder {
  /// How long after End the button turns into Force Quit (D62).
  public static let forceQuitAfter: Double = 5

  private struct Ending {
    var clickedAt: Double
    var killed: Bool
  }

  private let signals: TaskSignals
  private var endings: [TaskID: Ending] = [:]

  public init(signals: TaskSignals) {
    self.signals = signals
  }

  /// What the button on the row of task `id` reads at `now`.
  public func button(for id: TaskID, now: Double) -> EndButton {
    guard let ending = endings[id] else { return .end }
    if ending.killed { return .forceQuitSent }
    return now - ending.clickedAt >= Self.forceQuitAfter ? .forceQuit : .ending
  }

  /// The user clicked the button on the row of task `id` at `now`. Returns what was sent, nil
  /// when nothing was: a click on `Ending…` (D63), or a task no longer running as the row showed
  /// it, or a `system` task.
  @discardableResult
  public func click(_ id: TaskID, now: Double) -> EndRequest? {
    switch button(for: id, now: now) {
    case .end:
      guard mayEnd(id) else { return nil }
      let request: EndRequest = signals.isApp(pid: id.pid) ? .quitRequest : .terminate
      signals.send(request, to: id.pid)
      endings[id] = Ending(clickedAt: now, killed: false)
      return request
    case .forceQuit:
      guard mayEnd(id) else {
        endings[id] = nil
        return nil
      }
      signals.send(.kill, to: id.pid)
      endings[id]?.killed = true
      return .kill
    case .ending, .forceQuitSent:
      return nil
    }
  }

  /// Forgets every task that has gone: a task that has gone takes its state with it (D40), and a
  /// later task given its process id starts with none. A task missing from `listed` (one
  /// measured list) is gone only if the system no longer runs it, started at that moment: one
  /// missed sample must not drop the state of a task still running.
  public func keep(only listed: Set<TaskID>) {
    endings = endings.filter { id, _ in
      listed.contains(id) || signals.running(pid: id.pid)?.id == id
    }
  }

  /// Whether anything may be sent to task `id` now: the task under its process id is the same
  /// task, started at the same moment, and is not `system` by the rule the rows follow.
  public func mayEnd(_ id: TaskID) -> Bool {
    guard id.pid > 0, let task = signals.running(pid: id.pid), task.id == id else { return false }
    return !SystemTasks.isSystem(
      pid: task.id.pid, uid: task.uid, path: task.path, userID: signals.userID,
      ownPID: signals.ownPID, resolve: signals.resolve(path:))
  }
}
