/// The meter's presence (D42, D65, D104, D77, D98, D83, D84): the login job macOS keeps alive,
/// the back-off that stops a crash from looping, what an opened copy does with the running one,
/// and the shortcut. Pure rules; the app carries them out.

/// How the meter's process ended, as launchd sees it.
public enum Termination: Equatable, Sendable {
  /// The process exited with this status. `Quit Meter` exits with `KeepAlive.quitStatus`.
  case exited(Int32)
  /// A signal ended it (a crash: SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGKILL…).
  case signaled(Int32)
}

/// The login job: started at every login (D42), relaunched by launchd after a crash (D77) and
/// never after `Quit Meter` (D65, D104).
public enum KeepAlive {
  /// `Quit Meter` exits with this status; launchd keeps the job down after it.
  public static let quitStatus: Int32 = 0
  /// launchd waits at least this long between two starts of the job, so a crash right after a
  /// start is relaunched within ten seconds (D77), and never sooner than this.
  public static let throttleSeconds = 5

  /// Whether launchd relaunches the job after it ended so. The job's `KeepAlive` is
  /// `SuccessfulExit = false`: relaunch unless it exited with status 0.
  public static func relaunches(after end: Termination) -> Bool {
    switch end {
    case .exited(let status): status != quitStatus
    case .signaled: true
    }
  }

  /// What the meter does when it is sent `signal`: nil leaves the signal's default (a crash
  /// signal ends it, and launchd relaunches it); a status ends it at once as a quit. A terminate
  /// request (SIGTERM: Activity Monitor's Quit, `kill`, log-out and shutdown) is the user's own
  /// quit, like `Quit Meter` (the visionary's ruling 2026-10-21, D104).
  public static func exitStatus(onSignal signal: Int32) -> Int32? {
    signal == 15 ? quitStatus : nil  // SIGTERM
  }

  /// Whether the job starts at the next login after it ended so. It always does: a quit is only
  /// launchd's state for the login session it ended in (the plist has `RunAtLoad` and is never
  /// disabled), so a SIGTERM at log-out or shutdown cannot keep the meter away from the next
  /// login (D42, D104).
  public static func startsAtNextLogin(after end: Termination) -> Bool { true }

  /// The LaunchAgent property list for the job labelled `label`, running `program` (the
  /// installed bundle's own executable, by its full path) with `--agent`. It encodes
  /// `relaunches(after:)` for launchd.
  public static func agentPlist(label: String, program: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>Label</key>
    \t<string>\(escaped(label))</string>
    \t<key>ProgramArguments</key>
    \t<array>
    \t\t<string>\(escaped(program))</string>
    \t\t<string>\(Presence.agentArgument)</string>
    \t</array>
    \t<key>RunAtLoad</key>
    \t<true/>
    \t<key>KeepAlive</key>
    \t<dict>
    \t\t<key>SuccessfulExit</key>
    \t\t<false/>
    \t</dict>
    \t<key>ThrottleInterval</key>
    \t<integer>\(throttleSeconds)</integer>
    \t<key>LimitLoadToSessionType</key>
    \t<string>Aqua</string>
    \t<key>ProcessType</key>
    \t<string>Interactive</string>
    </dict>
    </plist>

    """
  }

  private static func escaped(_ text: String) -> String {
    var out = ""
    for character in text {
      switch character {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      default: out.append(character)
      }
    }
    return out
  }
}

/// The back-off that keeps a meter crashing at every start from being relaunched forever: the
/// job's starts within the last `window` seconds are counted, and once `maxStarts` have
/// happened the next start stays down (it exits with `KeepAlive.quitStatus`, so launchd stops)
/// until the user opens the meter or logs in again.
public enum CrashBackoff {
  public static let window: Double = 120
  public static let maxStarts = 5

  public enum Decision: Equatable, Sendable {
    case run
    case stayDown
  }

  /// The starts still inside the window at `now`, oldest first.
  public static func recent(_ starts: [Double], now: Double) -> [Double] {
    starts.filter { $0 <= now && now - $0 < window }.sorted()
  }

  /// Whether a start at `now` runs, given the job's earlier starts.
  public static func decide(starts: [Double], now: Double) -> Decision {
    recent(starts, now: now).count >= maxStarts ? .stayDown : .run
  }
}

/// A version as `CFBundleShortVersionString` writes it: dot-separated whole numbers.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
  public let parts: [Int]

  /// Nil for a string that is not dot-separated whole numbers.
  public init?(_ text: String) {
    let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
    var parts: [Int] = []
    for piece in pieces {
      guard !piece.isEmpty, piece.allSatisfy(\.isASCII), let n = Int(piece), n >= 0 else {
        return nil
      }
      parts.append(n)
    }
    guard !parts.isEmpty else { return nil }
    self.parts = parts
  }

  public var description: String { parts.map(String.init).joined(separator: ".") }

  /// Missing trailing parts count as zero: 1.2 equals 1.2.0.
  public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    let count = max(lhs.parts.count, rhs.parts.count)
    for i in 0..<count {
      let l = i < lhs.parts.count ? lhs.parts[i] : 0
      let r = i < rhs.parts.count ? rhs.parts[i] : 0
      if l != r { return l < r }
    }
    return false
  }

  public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
    !(lhs < rhs) && !(rhs < lhs)
  }
}

/// What a copy of the meter opened by the user or by the installer does (D83, D84).
public enum Presence {
  /// The argument the login job starts the meter with.
  public static let agentArgument = "--agent"

  public enum OpenerAction: Equatable, Sendable {
    /// No meter runs: start the login job.
    case start
    /// An older meter runs (or one whose version is unknown): replace it with the copy just
    /// opened, which loads the login job afresh and starts it.
    case replace
    /// A newer meter runs, or the same version from this very copy: leave it be.
    case leave
  }

  /// `running` is the version of the meter the login job runs now (nil when none runs; an
  /// unreadable version as an empty string) and `runningProgram` the program the job names;
  /// `opened` and `openedProgram` are the copy just opened. The same version from another copy
  /// takes the job over, so the job never stays on a copy that is later removed.
  public static func openerAction(
    running: String?, opened: String, runningProgram: String?, openedProgram: String
  ) -> OpenerAction {
    guard let running else { return .start }
    guard let old = AppVersion(running), let new = AppVersion(opened) else { return .replace }
    if old < new { return .replace }
    if new < old { return .leave }
    return runningProgram == openedProgram ? .leave : .replace
  }

  /// Whether `path` lies in a quarantined side-open's private copy (App Translocation): such a
  /// copy runs as the meter itself and never writes the login job, since its path vanishes.
  public static func isTranslocated(_ path: String) -> Bool {
    path.split(separator: "/").contains("AppTranslocation")
  }
}

/// The shortcut that opens and closes the panel from any app (D98): Control-Option-Command-M,
/// never Option-Command-M, which minimizes all windows of the front app; Esc closes the panel.
public struct HotKey: Equatable, Sendable {
  /// Carbon's modifier bits (`Events.h`).
  public static let commandBit: UInt32 = 0x0100
  public static let shiftBit: UInt32 = 0x0200
  public static let optionBit: UInt32 = 0x0800
  public static let controlBit: UInt32 = 0x1000

  /// The virtual key code (`kVK_ANSI_M`, `kVK_Escape`).
  public let keyCode: UInt32
  public let modifiers: UInt32

  public static let togglePanel = HotKey(
    keyCode: 0x2E, modifiers: controlBit | optionBit | commandBit)
  public static let closePanel = HotKey(keyCode: 0x35, modifiers: 0)
}
