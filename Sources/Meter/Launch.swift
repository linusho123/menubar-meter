import Foundation
import MeterCore

/// How this copy of the meter was started, and what it does about it (D42, D77, D83, D84).
///
/// - The login job (`--agent`): the user's own LaunchAgent, which launchd starts at every login
///   and relaunches after a crash but not after `Quit Meter`; it is the meter. A crash loop is
///   stopped by `CrashBackoff`.
/// - Opened by the user or by the installer (started by launchd for LaunchServices, so its
///   parent is process 1): it writes the login job for its own program, loads it (which starts
///   it, replacing an older meter that runs) and exits. If launchd will not load the job (the
///   user turned the meter off in Login Items), it is the meter itself, without the keep-alive.
/// - Started by another program (the test harness, a terminal): it is the meter, no more.
enum Launch {
  enum Role {
    case agent
    case opener
    case plain
  }

  static func role(arguments: [String]) -> Role {
    if arguments.dropFirst().contains(Presence.agentArgument) { return .agent }
    return getppid() == 1 ? .opener : .plain
  }

  /// The login job's label: the bundle's identifier.
  static var label: String { Bundle.main.bundleIdentifier ?? "local.menubar-meter.Meter" }
  static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
  }

  // MARK: The login job

  /// A start of the login job: counted against the back-off, which may keep it down.
  static func agentStarts() {
    var state = State.load()
    let now = Date().timeIntervalSince1970
    if CrashBackoff.decide(starts: state.starts, now: now) == .stayDown {
      FileHandle.standardError.write(
        Data("meter: started \(CrashBackoff.maxStarts) times in a short while; staying down\n".utf8))
      exit(KeepAlive.quitStatus)
    }
    state.starts = CrashBackoff.recent(state.starts, now: now) + [now]
    state.pid = getpid()
    state.version = version
    state.save()
  }

  // MARK: Opened

  /// Writes, loads and so starts the login job for this copy. Returns false when launchd will
  /// not run it, so this copy runs as the meter itself.
  static func handOver() -> Bool {
    var state = State.load()
    let running = jobPID()
    let runningVersion: String? = running.map { $0 == state.pid ? state.version ?? "" : "" }
    if Presence.openerAction(running: runningVersion, opened: version) == .leave { return true }

    guard let program = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
      return false
    }
    let plist = KeepAlive.agentPlist(label: label, program: program)
    // Taking the old job out ends an older meter that still runs (D84); loading the new one
    // starts it at once (RunAtLoad), and launchd loads it again at every login (D42).
    _ = launchctl(["bootout", domain])
    do {
      try FileManager.default.createDirectory(
        at: agentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(plist.utf8).write(to: agentFile, options: .atomic)
    } catch {
      FileHandle.standardError.write(Data("meter: login job not written: \(error)\n".utf8))
      return false
    }
    // Opening the meter by hand lifts a back-off that kept a crashing meter down.
    state.starts = []
    state.save()
    let (status, _) = launchctl(["bootstrap", "gui/\(getuid())", agentFile.path])
    guard status == 0 || jobLoaded() else {
      FileHandle.standardError.write(Data("meter: login job not loaded (\(status))\n".utf8))
      return false
    }
    _ = launchctl(["kickstart", domain])
    return true
  }

  /// The user's own LaunchAgent for the meter.
  static var agentFile: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  private static var domain: String { "gui/\(getuid())/\(label)" }

  private static func jobLoaded() -> Bool { launchctl(["print", domain]).0 == 0 }

  /// The process id launchd runs the login job as, nil when it is not running.
  private static func jobPID() -> Int32? {
    let (status, output) = launchctl(["print", domain])
    guard status == 0 else { return nil }
    for line in output.split(separator: "\n") {
      let parts = line.split(separator: "=", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      if parts.count == 2, parts[0] == "pid", let pid = Int32(parts[1]) { return pid }
    }
    return nil
  }

  private static func launchctl(_ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }

  // MARK: State

  /// The login job's recent starts and the version it runs, kept in the user's temporary folder
  /// (emptied at restart), one file per label.
  struct State: Codable {
    var starts: [Double] = []
    var pid: Int32?
    var version: String?

    static var file: URL {
      FileManager.default.temporaryDirectory
        .appendingPathComponent(Launch.label, isDirectory: true)
        .appendingPathComponent("presence.json")
    }

    static func load() -> State {
      guard let data = try? Data(contentsOf: file),
        let state = try? JSONDecoder().decode(State.self, from: data)
      else { return State() }
      return state
    }

    func save() {
      let file = Self.file
      try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let data = try? JSONEncoder().encode(self) { try? data.write(to: file, options: .atomic) }
    }
  }
}
