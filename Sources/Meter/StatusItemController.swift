import AppKit
import MeterCore

/// The menu bar item: one line of monospaced text in an item of fixed width (D89, D90).
/// Clicking it drops the panel down (D50).
@MainActor
final class StatusItemController: NSObject {
  private let item: NSStatusItem
  private let font: NSFont
  private var shown = ""
  private let clicked: (NSStatusBarButton) -> Void

  init(clicked: @escaping (NSStatusBarButton) -> Void) {
    self.clicked = clicked
    let size = NSFont.menuBarFont(ofSize: 0).pointSize
    font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    // The width always leaves room for a hundred percent on all three and a three-digit
    // temperature, so nothing beside the item moves when the numbers change.
    let textWidth = (ReadoutText.widest as NSString).size(withAttributes: [.font: font]).width
    item = NSStatusBar.system.statusItem(withLength: ceil(textWidth) + 12)
    super.init()
    item.button?.font = font
    item.button?.alignment = .center
    item.button?.target = self
    item.button?.action = #selector(click(_:))
  }

  @objc private func click(_ sender: NSStatusBarButton) {
    clicked(sender)
  }

  func show(_ readout: Readout) {
    let text = ReadoutText.text(readout)
    guard text != shown else { return }
    shown = text
    item.button?.title = text
  }
}
