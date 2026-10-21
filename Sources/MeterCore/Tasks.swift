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
/// cumulative CPU time and its memory. Its GPU time is in the snapshot's GPU clients.
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
  /// Its memory in bytes, as Activity Monitor's Memory column counts it.
  public var memory: UInt64

  public init(
    id: TaskID, name: String, uid: UInt32, path: String?, cpuTime: UInt64, memory: UInt64
  ) {
    self.id = id
    self.name = name
    self.uid = uid
    self.path = path
    self.cpuTime = cpuTime
    self.memory = memory
  }
}

/// Every task at a moment, and the GPU as a whole at the same moment.
public struct TaskSnapshot: Equatable, Sendable {
  public var processes: [ProcessSample]
  /// Each process's GPU time so far, in nanoseconds: the time the GPU spent on every client the
  /// process opened on it. Every client is here, the tasks the list cannot read included
  /// (another user's, such as WindowServer), so their sum is all the GPU's clients' time.
  public var gpuTimes: [Int32: UInt64]
  /// How busy the GPU reports itself now (its Device Utilization %, as a share); nil when it does
  /// not say.
  public var gpuBusy: Share?

  public init(processes: [ProcessSample], gpuTimes: [Int32: UInt64], gpuBusy: Share?) {
    self.processes = processes
    self.gpuTimes = gpuTimes
    self.gpuBusy = gpuBusy
  }
}

/// Where the task sampler's numbers come from: the real system, or (test builds only) the test
/// reading source.
public protocol TaskInputs: AnyObject {
  /// Every task running now and the GPU's clients; nil when the system gives no list.
  func snapshot() -> TaskSnapshot?
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
/// (D54, D107, D80, D49): CPU of all its cores, GPU as Activity Monitor's % GPU, RAM of its
/// physical memory.
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
  /// The folders whose programs are part of macOS: all of `/System`, and the folders where macOS
  /// keeps its services and users run nothing (`/usr/libexec`, `/usr/sbin`, `/sbin`). `/bin` and
  /// `/usr/bin` are not here: the user runs those commands (the visionary's ruling 2026-10-20).
  static let systemFolders: [[String]] = [
    ["system"], ["usr", "libexec"], ["usr", "sbin"], ["sbin"],
  ]

  /// The one folder inside `/System` whose programs are apps the user runs: the Applications
  /// folder of Apple's App cryptex, where Safari lives behind `/Applications`. This is the path
  /// the system resolves to (`/System/Cryptexes/App` is a link to it, so no resolved path begins
  /// with that). Only a program inside an `.app` bundle there is let through (the visionary's
  /// ruling 2026-10-20); the cryptex's `usr/libexec` agents and everything else stay system.
  static let cryptexApplications = [
    "system", "volumes", "preboot", "cryptexes", "app", "system", "applications",
  ]

  /// A task is `system` when it is the meter itself, when it does not run as the user, or when
  /// its program, every symbolic link resolved, lives in a macOS folder. A task whose program the
  /// system does not name, or names with no absolute path, cannot be shown to be the user's own,
  /// so it is `system` too.
  public static func isSystem(
    pid: Int32, uid: UInt32, path: String?, userID: UInt32, ownPID: Int32,
    resolve: (String) -> String?
  ) -> Bool {
    if pid == ownPID { return true }
    if uid != userID { return true }
    guard let path else { return true }
    let resolved = resolve(path) ?? path
    guard resolved.hasPrefix("/") else { return true }
    return livesInSystemFolder(resolved)
  }

  /// Whether a resolved path lies in one of macOS's folders themselves, not merely in a folder
  /// whose name starts the same way (`/Systems`), and not in an app of the App cryptex. The Mac's disk
  /// ignores case, so neither does this.
  public static func livesInSystemFolder(_ path: String) -> Bool {
    var components: [String] = []
    for part in path.split(separator: "/", omittingEmptySubsequences: true) {
      switch part {
      case ".": continue
      case "..": if !components.isEmpty { components.removeLast() }
      default: components.append(part.lowercased())
      }
    }
    guard path.hasPrefix("/") else { return false }
    if isInsideCryptexApp(components) { return false }
    return systemFolders.contains { components.count > $0.count && components.starts(with: $0) }
  }

  /// Whether lowercased path components name a program inside an `.app` bundle sitting directly
  /// in the App cryptex's Applications folder: `Foo.app`, not `Foo.appx`, with something below it.
  private static func isInsideCryptexApp(_ components: [String]) -> Bool {
    guard components.starts(with: cryptexApplications) else { return false }
    let below = components.dropFirst(cryptexApplications.count)
    guard below.count > 1, let bundle = below.first else { return false }
    return bundle.hasSuffix(".app") && bundle.count > ".app".count
  }
}

/// The task sampler: while the panel is open, each refresh turns two snapshots of the tasks into
/// each task's share of the Mac between them (D54, D107, D80, D49).
public final class TaskSampler {
  /// Two snapshots closer than this are too close to measure a load between.
  public static let minimumInterval: Double = 0.2

  private let inputs: TaskInputs
  private var previous: (at: Double, byID: [TaskID: ProcessSample], gpuTimes: [Int32: UInt64])?
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
  /// list was measured afresh. `force` bypasses the minimum interval, for a refresh asked for
  /// at once.
  @discardableResult
  public func sample(now: Double, force: Bool = false) -> Bool {
    if !force, let previous, now - previous.at < Self.minimumInterval { return false }
    guard let snapshot = inputs.snapshot() else {
      reset()
      return false
    }
    var byID: [TaskID: ProcessSample] = [:]
    for process in snapshot.processes { byID[process.id] = process }
    defer { previous = (now, byID, snapshot.gpuTimes) }
    guard let previous else { return false }
    tasks = Self.usage(
      from: previous.byID, gpuTimes: previous.gpuTimes, to: snapshot,
      seconds: now - previous.at, inputs: inputs)
    return true
  }

  /// Each task's use between two snapshots `seconds` apart. A task not in the earlier snapshot
  /// has no load to show yet and is left out.
  public static func usage(
    from earlier: [TaskID: ProcessSample], gpuTimes earlierGPU: [Int32: UInt64],
    to later: TaskSnapshot, seconds: Double, inputs: TaskInputs
  ) -> [TaskUsage] {
    guard seconds > 0 else { return [] }
    let nanoseconds = UInt64((seconds * 1_000_000_000).rounded())
    let cores = UInt64(max(1, inputs.cpuCores))
    var allClients: UInt64 = 0
    for (pid, time) in later.gpuTimes {
      let before = earlierGPU[pid] ?? 0
      if time > before { allClients &+= time - before }
    }
    return later.processes.compactMap { process in
      guard let before = earlier[process.id] else { return nil }
      let cpu =
        process.cpuTime >= before.cpuTime
        ? Share(part: process.cpuTime - before.cpuTime, whole: nanoseconds * cores) : nil
      let pid = process.id.pid
      let gpuNow = later.gpuTimes[pid] ?? 0
      let gpuBefore = earlierGPU[pid] ?? 0
      let gpu =
        gpuNow >= gpuBefore
        ? GPUShare.of(
          task: gpuNow - gpuBefore, allClients: allClients, busy: later.gpuBusy,
          window: nanoseconds) : nil
      return TaskUsage(
        id: process.id, name: process.name, cpu: cpu, gpu: gpu,
        ram: Share(part: process.memory, whole: inputs.physicalMemory),
        isSystem: SystemTasks.isSystem(
          pid: pid, uid: process.uid, path: process.path, userID: inputs.userID,
          ownPID: inputs.ownPID, resolve: inputs.resolve(path:)))
    }
  }
}

/// A task's GPU as Activity Monitor's `% GPU` counts it (D49): its part of all the GPU's
/// clients' time over the refresh, of how busy the GPU reports itself. On this Mac that tracks
/// Activity Monitor's column where the task's own GPU time over the refresh does not: at light
/// loads the GPU reports itself far busier than its clients' time adds up to.
public enum GPUShare {
  /// `task` and `allClients` are GPU time in nanoseconds over a refresh of `window`
  /// nanoseconds. When the GPU does not say how busy it is, the task's own GPU time over the
  /// refresh stands in.
  public static func of(task: UInt64, allClients: UInt64, busy: Share?, window: UInt64) -> Share? {
    guard let busy else { return Share(part: task, whole: window) }
    guard allClients > 0 else { return Share(part: 0, whole: 1) }
    let part = task.multipliedReportingOverflow(by: busy.part)
    let whole = allClients.multipliedReportingOverflow(by: busy.whole)
    if !part.overflow && !whole.overflow {
      return Share(part: part.partialValue, whole: whole.partialValue)
    }
    let exact = Double(task) / Double(allClients) * Double(busy.part) / Double(busy.whole)
    return Share(part: UInt64((min(1, exact) * 1_000_000_000).rounded()), whole: 1_000_000_000)
  }
}
