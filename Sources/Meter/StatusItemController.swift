import AppKit
import MeterCore

/// The menu bar item: one line of monospaced text in an item of fixed width (D89, D90).
@MainActor
final class StatusItemController {
  private let item: NSStatusItem
  private let font: NSFont
  private var shown = ""

  init() {
    let size = NSFont.menuBarFont(ofSize: 0).pointSize
    font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    // The width always leaves room for a hundred percent on all three and a three-digit
    // temperature, so nothing beside the item moves when the numbers change.
    let textWidth = (ReadoutText.widest as NSString).size(withAttributes: [.font: font]).width
    item = NSStatusBar.system.statusItem(withLength: ceil(textWidth) + 12)
    item.button?.font = font
    item.button?.alignment = .center
  }

  func show(_ readout: Readout) {
    let text = ReadoutText.text(readout)
    guard text != shown else { return }
    shown = text
    item.button?.title = text
  }
}
