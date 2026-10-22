import Testing

@testable import MeterCore

@Suite("The keep-alive: back after a crash, never after Quit Meter (D77, D65, D104)")
struct KeepAliveTests {
  @Test("a crash, by any signal, is relaunched")
  func crashRelaunches() {
    for signal: Int32 in [4, 6, 9, 10, 11] {  // SIGILL, SIGABRT, SIGKILL, SIGBUS, SIGSEGV
      #expect(KeepAlive.relaunches(after: .signaled(signal)))
    }
    #expect(KeepAlive.relaunches(after: .exited(1)))
  }

  @Test("Quit Meter exits with the status launchd keeps the job down after")
  func quitStaysDown() {
    #expect(KeepAlive.quitStatus == 0)
    #expect(!KeepAlive.relaunches(after: .exited(KeepAlive.quitStatus)))
  }

  @Test("the LaunchAgent relaunches only an unsuccessful exit, starts at load, within ten seconds")
  func agentPlist() {
    let plist = KeepAlive.agentPlist(label: "a.b", program: "/x/Meter.app/Contents/MacOS/Meter")
    #expect(plist.contains("<key>Label</key>\n\t<string>a.b</string>"))
    #expect(
      plist.contains(
        "<key>KeepAlive</key>\n\t<dict>\n\t\t<key>SuccessfulExit</key>\n\t\t<false/>\n\t</dict>"))
    #expect(plist.contains("<key>RunAtLoad</key>\n\t<true/>"))
    #expect(
      plist.contains(
        "<array>\n\t\t<string>/x/Meter.app/Contents/MacOS/Meter</string>\n\t\t<string>--agent</string>"
      ))
    #expect(KeepAlive.throttleSeconds > 0 && KeepAlive.throttleSeconds < 10)
    #expect(plist.contains("<integer>\(KeepAlive.throttleSeconds)</integer>"))
  }

  @Test("a terminate request (Activity Monitor's Quit, kill, log-out) ends it as a quit")
  func terminateIsQuit() {
    // The visionary's ruling 2026-10-21: SIGTERM is the user's own quit, so the job exits 0.
    #expect(KeepAlive.exitStatus(onSignal: 15) == KeepAlive.quitStatus)
    #expect(!KeepAlive.relaunches(after: .exited(KeepAlive.exitStatus(onSignal: 15)!)))
    // A crash signal is never turned into a quit.
    for crash: Int32 in [4, 6, 9, 10, 11] {
      #expect(KeepAlive.exitStatus(onSignal: crash) == nil)
    }
  }

  @Test("a quit stays quit only until the next login: the job is loaded and started afresh then")
  func quitIsNotRemembered() {
    let plist = KeepAlive.agentPlist(label: "a.b", program: "/x/Meter.app/Contents/MacOS/Meter")
    #expect(plist.contains("<key>RunAtLoad</key>\n\t<true/>"))
    #expect(!plist.contains("Disabled"))
    // The only state a quit leaves is launchd's, for the login session it ended in.
    #expect(KeepAlive.startsAtNextLogin(after: .exited(KeepAlive.quitStatus)))
    #expect(KeepAlive.startsAtNextLogin(after: .signaled(15)))
    #expect(KeepAlive.startsAtNextLogin(after: .signaled(11)))
  }

  @Test("a program path is written as XML text")
  func escapes() {
    let plist = KeepAlive.agentPlist(label: "a", program: "/A & B/<M>")
    #expect(plist.contains("<string>/A &amp; B/&lt;M&gt;</string>"))
  }
}

@Suite("The back-off: a meter that crashes at every start is not relaunched forever")
struct CrashBackoffTests {
  @Test("the first starts run")
  func firstStartsRun() {
    var starts: [Double] = []
    for i in 0..<CrashBackoff.maxStarts {
      let now = 1000 + Double(i) * 5
      #expect(CrashBackoff.decide(starts: starts, now: now) == .run)
      starts.append(now)
    }
    #expect(CrashBackoff.decide(starts: starts, now: 1000 + 5 * 5) == .stayDown)
  }

  @Test("a crash loop stops, however long launchd keeps relaunching")
  func loopStops() {
    // launchd relaunches every throttle interval; each start that runs is recorded.
    var starts: [Double] = []
    var ran = 0
    var now = 0.0
    var stopped = false
    for _ in 0..<1000 {
      if CrashBackoff.decide(starts: starts, now: now) == .stayDown {
        stopped = true
        break
      }
      starts = CrashBackoff.recent(starts, now: now) + [now]
      ran += 1
      now += Double(KeepAlive.throttleSeconds)
    }
    #expect(stopped)
    #expect(ran == CrashBackoff.maxStarts)
  }

  @Test("crashes spread out beyond the window each come back")
  func spreadCrashes() {
    var starts: [Double] = []
    var now = 0.0
    for _ in 0..<50 {
      #expect(CrashBackoff.decide(starts: starts, now: now) == .run)
      starts = CrashBackoff.recent(starts, now: now) + [now]
      now += CrashBackoff.window / Double(CrashBackoff.maxStarts - 1)
    }
  }

  @Test("the window's edge: a start exactly a window ago no longer counts")
  func windowEdge() {
    let starts = (0..<CrashBackoff.maxStarts).map { Double($0) }
    #expect(CrashBackoff.decide(starts: starts, now: 4) == .stayDown)
    #expect(CrashBackoff.decide(starts: starts, now: CrashBackoff.window) == .run)
    #expect(CrashBackoff.decide(starts: starts, now: CrashBackoff.window - 0.001) == .stayDown)
  }

  @Test("a start from a clock set back (in the future) is not counted")
  func futureStarts() {
    #expect(CrashBackoff.recent([10, 20, 500], now: 100) == [10, 20])
  }
}

@Suite("Reinstalling over an older copy (D84): version comparison")
struct AppVersionTests {
  @Test("versions compare part by part, as numbers")
  func compares() {
    #expect(AppVersion("0.0.1")! < AppVersion("0.0.2")!)
    #expect(AppVersion("0.9")! < AppVersion("0.10")!)
    #expect(AppVersion("1.2")! < AppVersion("1.10.0")!)
    #expect(!(AppVersion("2.0")! < AppVersion("1.99.99")!))
    #expect(AppVersion("1.2")! == AppVersion("1.2.0")!)
    #expect(!(AppVersion("1.2.0")! < AppVersion("1.2")!))
  }

  @Test("text that is not a version is refused")
  func refuses() {
    for bad in ["", "1..2", "1.2a", "v1", "-1", "1.", ".1", "١.٢"] {
      #expect(AppVersion(bad) == nil, "\(bad)")
    }
  }

  @Test("what an opened copy does with the meter that runs")
  func openerAction() {
    #expect(Presence.openerAction(running: nil, opened: "0.0.2") == .start)
    #expect(Presence.openerAction(running: "0.0.1", opened: "0.0.2") == .replace)
    #expect(Presence.openerAction(running: "0.0.2", opened: "0.0.2") == .leave)
    #expect(Presence.openerAction(running: "0.0.3", opened: "0.0.2") == .leave)
    #expect(Presence.openerAction(running: "", opened: "0.0.2") == .replace)
  }
}

@Suite("The shortcut (D98)")
struct HotKeyTests {
  @Test("Control-Option-Command-M opens and closes the panel; never Option-Command-M")
  func toggle() {
    #expect(HotKey.togglePanel.keyCode == 0x2E)  // kVK_ANSI_M
    #expect(HotKey.togglePanel.modifiers == 0x1900)  // controlKey | optionKey | cmdKey
    #expect(HotKey.togglePanel.modifiers & HotKey.controlBit != 0)
    #expect(HotKey.togglePanel.modifiers & HotKey.shiftBit == 0)
    #expect(
      HotKey.togglePanel != HotKey(keyCode: 0x2E, modifiers: HotKey.optionBit | HotKey.commandBit))
  }

  @Test("Esc, with no modifier, closes it")
  func escape() {
    #expect(HotKey.closePanel == HotKey(keyCode: 0x35, modifiers: 0))
  }
}
