import AppKit

/// The panel's look, shared with Notch Island: a black card, white text at a few opacities, soft
/// tiles and pill buttons, and no colour anywhere but the graph's three lines and their legend
/// labels (D110). The panel is always dark, whatever the system's appearance.
@MainActor
enum PanelStyle {
  static let appearance = NSAppearance(named: .darkAqua)

  static let background = NSColor.black
  static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }

  /// Text, from most to least prominent.
  static let primary = white(0.9)
  static let secondary = white(0.7)
  static let tertiary = white(0.45)
  static let disabled = white(0.3)

  static let tile = white(0.07)
  static let hairline = white(0.12)
  static let grid = white(0.1)
  static let pill = white(0.15)
  static let pillHover = white(0.25)
  static let rowHover = white(0.1)

  static let cornerRadius: CGFloat = 16
  static let tileRadius: CGFloat = 10

  /// Section headings, as Notch Island's shelf heading reads.
  static let heading = NSFont.systemFont(ofSize: 11, weight: .semibold)
  /// The graph's scale and time labels.
  static let caption = NSFont.systemFont(ofSize: 10)
  /// Numbers and the lines that carry them.
  static let body = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
  /// The heavy-tasks rows, a size down so a row fits the panel's width.
  static let row = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
  static let action = NSFont.systemFont(ofSize: 13)
  static let pillFont = NSFont.systemFont(ofSize: 10, weight: .medium)

  static func label(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment)
    -> NSTextField
  {
    let field = NSTextField(labelWithString: text)
    field.font = font
    field.textColor = color
    field.alignment = alignment
    field.lineBreakMode = .byTruncatingTail
    field.sizeToFit()
    return field
  }

  /// A line of words and numbers, as in `Net ↓ 1.2 MB/s ↑ 0.1 MB/s`: the numbers in primary
  /// text and every other word dimmed, so the eye finds the values. The text itself is unchanged.
  static func valuesText(_ text: String) -> NSAttributedString {
    let styled = NSMutableAttributedString(
      string: text, attributes: [.font: body, .foregroundColor: tertiary])
    var location = 0
    for word in text.split(separator: " ", omittingEmptySubsequences: false) {
      let length = (String(word) as NSString).length
      if let first = word.first, first.isNumber || String(first) == "\u{2013}" {
        styled.addAttribute(
          .foregroundColor, value: primary, range: NSRange(location: location, length: length))
      }
      location += length + 1
    }
    return styled
  }
}

/// The panel's black card, with Notch Island's continuous rounded corners.
final class PanelCard: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    guard let layer else { return }
    layer.backgroundColor = PanelStyle.background.cgColor
    layer.cornerRadius = PanelStyle.cornerRadius
    layer.cornerCurve = .continuous
    layer.borderWidth = 0.5
    layer.borderColor = PanelStyle.hairline.cgColor
    layer.masksToBounds = true
  }
}

/// A soft tile grouping one part of the panel, as Notch Island groups its shelf items.
final class Tile: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    guard let layer else { return }
    layer.backgroundColor = PanelStyle.tile.cgColor
    layer.cornerRadius = PanelStyle.tileRadius
    layer.cornerCurve = .continuous
  }
}

/// A button that lights up under the pointer. The panel is never the key window, so its tracking
/// works whether or not the meter is active.
class HoverButton: NSButton {
  private(set) var isHovered = false {
    didSet { if isHovered != oldValue { needsDisplay = true } }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self))
  }

  override func mouseEntered(with event: NSEvent) { isHovered = true }
  override func mouseExited(with event: NSEvent) { isHovered = false }

  /// Forgets the pointer, for a panel that closed with the pointer on the button.
  func resetHover() { isHovered = false }
}
