import AppKit
import MeterCore

/// The menu bar item: one line in a monospaced font, at a fixed width that
/// always has room for a hundred percent on all three and a three-digit
/// temperature, so nothing beside it moves.
final class StatusItemController {
    private let item: NSStatusItem
    private let font: NSFont

    init() {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let widest = (Readout.widest as NSString).size(withAttributes: [.font: font]).width
        item = NSStatusBar.system.statusItem(withLength: ceil(widest) + 12)
        item.button?.font = font
        item.button?.alignment = .center
        item.button?.title = Readout.text(cpu: nil, gpu: nil, ram: nil, temperature: nil, now: Date())
    }

    func show(_ text: String) {
        if item.button?.title != text { item.button?.title = text }
    }
}
