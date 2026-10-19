import AppKit

// Test harness stand-in: a plain status item the harness starts after the meter, so it sits
// to the meter's left, and whose position shows whether the meter's width ever changes.

@MainActor
final class Neighbor: NSObject, NSApplicationDelegate {
  private var item: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "NB"
    self.item = item
  }
}

let app = NSApplication.shared
let neighbor = Neighbor()
app.delegate = neighbor
app.setActivationPolicy(.accessory)
app.run()
