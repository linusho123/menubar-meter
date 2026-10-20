import AppKit
import MeterCore

/// The panel that drops down from the menu bar item: the combined five-minute graph of CPU,
/// GPU and RAM on a fixed axis, its scale and time labels, and the legend of current values
/// (D50, D51, D52, D19). It shows no peak values (D9).
@MainActor
final class PanelController {
  private static let width: CGFloat = 360
  private static let margin: CGFloat = 12
  private static let scaleWidth: CGFloat = 34
  private static let plotHeight: CGFloat = 120

  private let engine: MeterEngine
  private let panel: NSPanel
  private let graph: GraphView
  private let legend: NSTextField
  private var outsideClicks: Any?

  init(engine: MeterEngine) {
    self.engine = engine
    graph = GraphView()
    legend = NSTextField(labelWithString: "")

    let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    func label(_ text: String, alignment: NSTextAlignment) -> NSTextField {
      let field = NSTextField(labelWithString: text)
      field.font = font
      field.textColor = .secondaryLabelColor
      field.alignment = alignment
      field.sizeToFit()
      return field
    }

    let margin = Self.margin
    let plotX = margin + Self.scaleWidth + 6
    let plotWidth = Self.width - plotX - margin
    let legendHeight: CGFloat = 18
    let timeHeight = ceil(font.boundingRectForFont.height)
    let height = margin + legendHeight + 6 + timeHeight + 4 + Self.plotHeight + margin
    let plotY = margin + legendHeight + 6 + timeHeight + 4

    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .popUpMenu
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.setAccessibilityTitle("Meter")

    let content = PanelBackground(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
    panel.contentView = content

    graph.frame = NSRect(x: plotX, y: plotY, width: plotWidth, height: Self.plotHeight)
    content.addSubview(graph)

    // The scale, 0% at the bottom line and 100% at the top line (D50).
    for (text, fraction) in [("100%", 1.0), ("0%", 0.0)] {
      let field = label(text, alignment: .right)
      let lineY = plotY + graph.lineY(fraction)
      field.frame = NSRect(
        x: margin, y: lineY - field.frame.height / 2, width: Self.scaleWidth,
        height: field.frame.height)
      content.addSubview(field)
    }

    // The time axis, always the whole five minutes (D51).
    let timeY = plotY - 4 - timeHeight
    let past = label("5 min ago", alignment: .left)
    past.frame.origin = NSPoint(x: plotX, y: timeY)
    content.addSubview(past)
    let now = label("now", alignment: .right)
    now.frame.origin = NSPoint(x: plotX + plotWidth - now.frame.width, y: timeY)
    content.addSubview(now)

    legend.frame = NSRect(x: plotX, y: margin, width: plotWidth, height: legendHeight)
    legend.lineBreakMode = .byClipping
    content.addSubview(legend)
  }

  var isOpen: Bool { panel.isVisible }

  /// Opens the panel under the menu bar item, or closes it if it is open.
  func toggle(below button: NSStatusBarButton) {
    if isOpen {
      close()
    } else {
      open(below: button)
    }
  }

  private func open(below button: NSStatusBarButton) {
    guard let itemWindow = button.window else { return }
    let item = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let screen = itemWindow.screen ?? NSScreen.main
    var origin = NSPoint(x: item.minX, y: item.minY - panel.frame.height - 4)
    if let visible = screen?.visibleFrame {
      origin.x = min(origin.x, visible.maxX - panel.frame.width - 4)
      origin.x = max(origin.x, visible.minX + 4)
    }
    panel.setFrameOrigin(origin)
    refresh(now: nil)
    panel.orderFrontRegardless()
    // A click anywhere else closes the panel, as it would a menu.
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
    outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
  }

  func close() {
    panel.orderOut(nil)
    if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
    outsideClicks = nil
  }

  /// Redraws the graph and the legend from the engine, when the panel is open. `now` is the
  /// pass that just ran; nil means the engine's latest.
  func refresh(now: Double?) {
    guard isOpen || now == nil else { return }
    let at = now ?? engine.now
    graph.show(engine.history, now: at)
    legend.attributedStringValue = Self.legendText(engine.legend(now: at))
  }

  /// The legend's text (D19), each line's label in that line's colour.
  private static func legendText(_ values: LegendValues) -> NSAttributedString {
    let size = NSFont.systemFontSize
    let text = NSMutableAttributedString(
      string: Legend.text(values),
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
        .foregroundColor: NSColor.labelColor,
      ])
    var offset = 0
    for metric in HistoryMetric.allCases {
      let label = NSRange(location: offset, length: (metric.label as NSString).length)
      text.addAttributes(
        [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: GraphView.color(metric)],
        range: label)
      let entry = Legend.entry(metric, values.value(metric)) + Legend.separator
      offset += (entry as NSString).length
    }
    return text
  }
}

/// The panel's opaque rounded background.
private final class PanelBackground: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
  }
}

/// The combined graph: one line each for CPU, GPU and RAM over the last five minutes, x fixed
/// from five minutes ago to now and y fixed from 0% to 100% (D50, D51), broken wherever the
/// history has a gap (D52).
final class GraphView: NSView {
  /// Room above 100% and below 0% so a line at either end is drawn whole.
  static let inset: CGFloat = 2

  static func color(_ metric: HistoryMetric) -> NSColor {
    switch metric {
    case .cpu: .systemRed
    case .gpu: .systemGreen
    case .ram: .systemBlue
    }
  }

  private var history = History()
  private var now: Double = 0

  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Graph of the last five minutes")
  }

  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  func show(_ history: History, now: Double) {
    self.history = history
    self.now = now
    needsDisplay = true
  }

  /// The height within the view of a value at `fraction` of the scale (0 is 0%, 1 is 100%).
  func lineY(_ fraction: Double) -> CGFloat {
    Self.inset + (bounds.height - 2 * Self.inset) * CGFloat(fraction)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    bounds.fill()
    NSColor.separatorColor.setStroke()
    let frame = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
    frame.lineWidth = 1
    frame.stroke()

    for metric in HistoryMetric.allCases {
      Self.color(metric).setStroke()
      for run in history.lines(metric, now: now) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        for (index, point) in run.enumerated() {
          let at = NSPoint(x: bounds.width * CGFloat(point.x), y: lineY(point.y))
          if index == 0 { path.move(to: at) } else { path.line(to: at) }
        }
        if run.count == 1, let point = run.first {
          // A lone sample still shows, as a dot.
          let at = NSPoint(x: bounds.width * CGFloat(point.x), y: lineY(point.y))
          path.appendOval(in: NSRect(x: at.x - 0.75, y: at.y - 0.75, width: 1.5, height: 1.5))
        }
        path.stroke()
      }
    }
  }
}
