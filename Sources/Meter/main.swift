import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// An agent app: a menu bar item, no Dock icon, no main menu.
app.setActivationPolicy(.accessory)
app.run()
