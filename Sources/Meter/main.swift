import AppKit
import MeterCore

let arguments = CommandLine.arguments
// The build writes the bundle's login job from the same rules the meter keeps (scripts/build-app.sh).
if arguments.count == 3, arguments[1] == "--launch-agent-plist" {
  print(KeepAlive.agentPlist(label: arguments[2], program: "Contents/MacOS/Meter"), terminator: "")
  exit(0)
}
#if METER_TEST_SOURCE
  // Test builds only: the harness takes back the login job its scratch install registered.
  // The installed app has no removal of its own (clean removal is not scoped, D82).
  if arguments.count == 2, arguments[1] == "--test-unregister" { exit(Launch.unregister()) }
#endif
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
