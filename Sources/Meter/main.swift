import AppKit
import MeterCore

let arguments = CommandLine.arguments
switch Launch.role(arguments: arguments) {
case .agent: Launch.agentStarts()
case .opener:
  if Launch.handOver() { exit(0) }
  Launch.endOtherCopies()
case .plain: break
}

// A terminate request (Activity Monitor's Quit, `kill`, log-out) is a quit, like Quit Meter: it
// exits 0, so launchd does not bring the meter back (D104). A crash signal is not handled.
signal(SIGTERM, SIG_IGN)
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler {
  exit(KeepAlive.exitStatus(onSignal: SIGTERM) ?? KeepAlive.quitStatus)
}
terminate.resume()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// An agent app: a menu bar item, no Dock icon, no main menu.
app.setActivationPolicy(.accessory)
app.run()
