/// A task as it is told apart from every other: its process id and the moment it started, so a
/// reused process id is never taken for the task that had it before.
public struct TaskID: Hashable, Sendable {
  public var pid: Int32
  public var started: UInt64

  public init(pid: Int32, started: UInt64) {
    self.pid = pid
    self.started = started
  }
}

/// One task as the system reports it at a moment: who runs it, where its program lives, and its
/// cumulative CPU and GPU time and its memory.
public struct ProcessSample: Equatable, Sendable {
  public var id: TaskID
  /// The name the user knows it by: an app's own name, else its program's file name.
  public var name: String
  /// The user it runs as.
  public var uid: UInt32
  /// Where its program lives, nil when the system does not say.
  public var path: String?
  /// CPU time used so far, user plus system, in nanoseconds of one core.
  public var cpuTime: UInt64
  /// GPU time used so far, in nanoseconds.
  public var gpuTime: UInt64
  /// Its memory in bytes, as Activity Monitor's Memory column counts it.
  public var memory: UInt64

  public init(
    id: TaskID, name: String, uid: UInt32, path: String?, cpuTime: UInt64, gpuTime: UInt64,
    memory: UInt64
  ) {
    self.id = id
    self.name = name
    self.uid = uid
    self.path = path
    self.cpuTime = cpuTime
    self.gpuTime = gpuTime
    self.memory = memory
  }
}

/// Where the task sampler's numbers come from: the real system, or (test builds only) the test
/// reading source.
public protocol TaskInputs: AnyObject {
  /// Every task running now; nil when the system gives no list.
  func processes() -> [ProcessSample]?
  /// This Mac's CPU cores, as `hw.ncpu` counts them: one task can use all of them at once.
  var cpuCores: Int { get }
  /// Physical memory in bytes (`hw.memsize`).
  var physicalMemory: UInt64 { get }
  /// The user the meter runs as: the Mac's own user.
  var userID: UInt32 { get }
  /// The meter's own process id.
  var ownPID: Int32 { get }
  /// A program's path with every symbolic link resolved, nil when it cannot be resolved.
  func resolve(path: String) -> String?
}

/// One task's use of the Mac over the last refresh, each value an exact share of the whole Mac
/// (D54, D107, D80): CPU of all its cores, GPU of the GPU's time, RAM of its physical memory.
public struct TaskUsage: Equatable, Sendable {
  public var id: TaskID
  public var name: String
  public var cpu: Share?
  public var gpu: Share?
  public var ram: Share?
  /// Part of macOS, not the user's own, or the meter itself: listed with no End (D99, D57).
  public var isSystem: Bool

  public init(
    id: TaskID, name: String, cpu: Share?, gpu: Share?, ram: Share?, isSystem: Bool
  ) {
    self.id = id
    self.name = name
    self.cpu = cpu
    self.gpu = gpu
    self.ram = ram
    self.isSystem = isSystem
  }
}

/// Which tasks get no End button (D99, D57).
public enum SystemTasks {
  /// macOS's own folder: a program that lives under it is part of macOS.
  public static let systemFolder = "/System"

  /// A task is `system` when it is the meter itself, when it does not run as the user, or when
  /// its program, every symbolic link resolved, lives in `/System`. A task whose program the
  /// system does not name cannot be shown to be the user's own, so it is `system` too.
  public static func isSystem(
    pid: Int32, uid: UInt32, path: String?, userID: UInt32, ownPID: Int32,
    resolve: (String) -> String?
  ) -> Bool {
    if pid == ownPID { return true }
    if uid != userID { return true }
    guard let path else { return true }
    return livesInSystemFolder(resolve(path) ?? path)
  }

  /// Whether a resolved path lies in `/System` itself, not merely a folder whose name starts
  /// the same way (`/Systems`). The Mac's disk ignores case, so neither does this.
  public static func livesInSystemFolder(_ path: String) -> Bool {
    var components: [Substring] = []
    for part in path.split(separator: "/", omittingEmptySubsequences: true) {
      switch part {
      case ".": continue
      case "..": if !components.isEmpty { components.removeLast() }
      default: components.append(part)
      }
    }
    guard path.hasPrefix("/"), let first = components.first else { return false }
    return first.lowercased() == systemFolder.dropFirst().lowercased()
  }
}

/// The task sampler: while the panel is open, each refresh turns two snapshots of the tasks into
/// each task's share of the Mac between them (D54, D107, D80, D49).
public final class TaskSampler {
  /// Two snapshots closer than this are too close to measure a load between.
  public static let minimumInterval: Double = 0.2

  private let inputs: TaskInputs
  private var previous: (at: Double, byID: [TaskID: ProcessSample])?
  public private(set) var tasks: [TaskUsage] = []

  public init(inputs: TaskInputs) {
    self.inputs = inputs
  }

  /// Whether a list has been measured since the last reset.
  public var hasList: Bool { previous != nil && !tasks.isEmpty }

  /// Forgets everything: the panel closed.
  public func reset() {
    previous = nil
    tasks = []
  }

  /// Takes a snapshot and, from the one before it, each task's use since. Returns whether the
  /// list was measured afresh.
  @discardableResult
  public func sample(now: Double) -> Bool {
    if let previous, now - previous.at < Self.minimumInterval { return false }
    guard let list = inputs.processes() else {
      reset()
      return false
    }
    var byID: [TaskID: ProcessSample] = [:]
    for process in list { byID[process.id] = process }
    defer { previous = (now, byID) }
    guard let previous else { return false }
    tasks = Self.usage(
      from: previous.byID, to: list, seconds: now - previous.at, inputs: inputs)
    return true
  }

  /// Each task's use between two snapshots `seconds` apart. A task not in the earlier snapshot
  /// has no load to show yet and is left out.
  public static func usage(
    from earlier: [TaskID: ProcessSample], to later: [ProcessSample], seconds: Double,
    inputs: TaskInputs
  ) -> [TaskUsage] {
    guard seconds > 0 else { return [] }
    let nanoseconds = UInt64((seconds * 1_000_000_000).rounded())
    let cores = UInt64(max(1, inputs.cpuCores))
    return later.compactMap { process in
      guard let before = earlier[process.id] else { return nil }
      let cpu =
        process.cpuTime >= before.cpuTime
        ? Share(part: process.cpuTime - before.cpuTime, whole: nanoseconds * cores) : nil
      let gpu =
        process.gpuTime >= before.gpuTime
        ? Share(part: process.gpuTime - before.gpuTime, whole: nanoseconds) : nil
      return TaskUsage(
        id: process.id, name: process.name, cpu: cpu, gpu: gpu,
        ram: Share(part: process.memory, whole: inputs.physicalMemory),
        isSystem: SystemTasks.isSystem(
          pid: process.id.pid, uid: process.uid, path: process.path, userID: inputs.userID,
          ownPID: inputs.ownPID, resolve: inputs.resolve(path:)))
    }
  }
}
