import AppKit
import MeterCore

let arguments = CommandLine.arguments
switch Launch.role(arguments: arguments) {
case .agent: Launch.agentStarts()
case .opener: if Launch.handOver() { exit(0) }
case .plain: break
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// An agent app: a menu bar item, no Dock icon, no main menu.
app.setActivationPolicy(.accessory)
app.run()
