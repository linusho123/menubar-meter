import Foundation
import MeterCore
import ServiceManagement

/// How this copy of the meter was started, and what it does about it (D42, D77, D83, D84).
///
/// - The login job (`--agent`): launchd starts it at every login and relaunches it after a crash
///   but not after `Quit Meter`; it is the meter. A crash loop is stopped by `CrashBackoff`.
/// - Opened by the user or by the installer (started by launchd for LaunchServices, so its
///   parent is process 1): it registers the login job with macOS (Background Task Management),
///   starts it, or restarts it when an older version runs, and exits. If macOS will not run the
///   login job (the user turned it off), it is the meter itself, without the keep-alive.
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

  /// The login job's label: the bundle's identifier, so a renamed copy is its own job.
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

  /// Registers and starts the login job. Returns false when macOS will not run it, so this copy
  /// runs as the meter itself.
  static func handOver() -> Bool {
    let service = SMAppService.agent(plistName: "\(label).plist")
    let wasEnabled = service.status == .enabled
    if !wasEnabled {
      do {
        try service.register()
      } catch {
        FileHandle.standardError.write(Data("meter: login item not registered: \(error)\n".utf8))
      }
    }
    guard service.status == .enabled else { return false }

    // Opening the meter by hand lifts a back-off that kept a crashing meter down.
    var state = State.load()
    state.starts = []
    state.save()

    let running = jobPID()
    let runningVersion: String? = running.map { $0 == state.pid ? state.version ?? "" : "" }
    switch Presence.openerAction(running: wasEnabled ? runningVersion : nil, opened: version) {
    case .start: kickstart(restart: false)
    case .restart: kickstart(restart: true)
    case .leave: break
    }
    return true
  }

  #if METER_TEST_SOURCE
    /// Test builds only: unregisters the login job, which also stops it. Returns 0 once macOS
    /// no longer lists it.
    static func unregister() -> Int32 {
      let service = SMAppService.agent(plistName: "\(label).plist")
      do {
        try service.unregister()
      } catch {
        FileHandle.standardError.write(Data("meter: unregister: \(error)\n".utf8))
      }
      try? FileManager.default.removeItem(at: State.file.deletingLastPathComponent())
      return service.status == .notRegistered || service.status == .notFound ? 0 : 1
    }
  #endif

  private static var domain: String { "gui/\(getuid())/\(label)" }

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

  private static func kickstart(restart: Bool) {
    _ = launchctl(restart ? ["kickstart", "-k", domain] : ["kickstart", domain])
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
