import AppKit
import MeterCore

/// The panel that drops down from the menu bar item: the combined five-minute graph of CPU,
/// GPU and RAM on a fixed axis, its scale and time labels, and the legend of current values
/// (D50, D51, D52, D19); below them the network and disk lines (D95, D96, D114), the
/// heavy-tasks list (D10, D108), then `Open Activity
/// Monitor…` (D59) and `Quit Meter`. It shows no peak values (D9).
@MainActor
final class PanelController {
  private static let width: CGFloat = 384
  private static let margin: CGFloat = 12
  private static let scaleWidth: CGFloat = 34
  private static let plotHeight: CGFloat = 120
  private static let rowHeight: CGFloat = 20

  private let engine: MeterEngine
  private let tasks: TaskSampler
  private let ender: TaskEnder
  private let clock: () -> Double
  private let panel: NSPanel
  private let graph: GraphView
  private let legend: NSTextField
  private let networkLine: NSTextField
  private let diskLine: NSTextField
  private let list: TaskListView
  private var outsideClicks: Any?
  /// Told each time the panel opens (true) or closes (false).
  var onOpenChange: ((Bool) -> Void)?

  /// The rows on show, and the row whose End button the pointer rests on (D100).
  private var shownRows: [HeavyRow] = []
  private var hold = PointerHold()

  init(
    engine: MeterEngine, tasks: TaskSampler, ender: TaskEnder, clock: @escaping () -> Double
  ) {
    self.engine = engine
    self.tasks = tasks
    self.ender = ender
    self.clock = clock
    graph = GraphView()
    legend = NSTextField(labelWithString: "")
    networkLine = NSTextField(labelWithString: "")
    diskLine = NSTextField(labelWithString: "")
    list = TaskListView(
      width: Self.width - 2 * Self.margin, rowHeight: Self.rowHeight,
      rows: HeavyTasks.cpuRows + 2)

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
    // From the bottom: Quit Meter, Open Activity Monitor…, the heavy-tasks list, the disk and
    // network lines, the legend, the time axis, the graph.
    let actionsHeight = 2 * Self.rowHeight + 2
    let listY = margin + actionsHeight + 8
    let lineHeight: CGFloat = 18
    let diskY = listY + list.frame.height + 8
    let networkY = diskY + lineHeight
    let legendY = networkY + lineHeight + 4
    let plotY = legendY + legendHeight + 6 + timeHeight + 4
    let height = plotY + Self.plotHeight + margin

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

    legend.frame = NSRect(x: plotX, y: legendY, width: plotWidth, height: legendHeight)
    legend.lineBreakMode = .byClipping
    content.addSubview(legend)

    // The network and disk lines, below the legend: current values only, no history (D95, D96).
    for (line, y) in [(networkLine, networkY), (diskLine, diskY)] {
      line.frame = NSRect(x: plotX, y: y, width: plotWidth, height: lineHeight)
      line.lineBreakMode = .byClipping
      line.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      content.addSubview(line)
    }

    // The heavy-tasks list, below the graph (D10).
    list.frame.origin = NSPoint(x: margin, y: listY)
    content.addSubview(list)

    // Its last rows: Open Activity Monitor… (D59), then Quit Meter at the bottom.
    let openRow = ActionRow(title: "Open Activity Monitor\u{2026}")
    openRow.frame = NSRect(
      x: margin, y: margin + Self.rowHeight + 2, width: Self.width - 2 * margin,
      height: Self.rowHeight)
    content.addSubview(openRow)
    let quitRow = ActionRow(title: "Quit Meter")
    quitRow.frame = NSRect(
      x: margin, y: margin, width: Self.width - 2 * margin, height: Self.rowHeight)
    content.addSubview(quitRow)

    openRow.target = self
    openRow.action = #selector(openActivityMonitor(_:))
    quitRow.target = self
    quitRow.action = #selector(quitMeter(_:))

    // End, Ending… and Force Quit act on the task the row shows, never on a row (D60, D105).
    list.onEnd = { [weak self] task in
      MainActor.assumeIsolated { self?.end(task) }
    }
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
    // The tasks are sampled only while the panel is open: the first snapshot now, the first
    // measured list a moment later.
    hold.reset()
    tasks.reset()
    tasks.sample(now: clock())
    showList()
    refresh(now: nil)
    panel.orderFrontRegardless()
    // A click anywhere else closes the panel, as it would a menu.
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
    outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
    onOpenChange?(true)
  }

  func close() {
    let wasOpen = isOpen
    panel.orderOut(nil)
    if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
    outsideClicks = nil
    hold.reset()
    tasks.reset()
    if wasOpen { onOpenChange?(false) }
  }

  /// `Quit Meter`: the meter leaves the menu bar at once (D65). It exits with the status the
  /// login job is kept down after, so it stays gone until the next login (D104).
  @objc private func quitMeter(_ sender: Any?) {
    close()
    exit(KeepAlive.quitStatus)
  }

  /// Redraws the graph and the legend from the engine, and re-ranks the heavy tasks, when the
  /// panel is open. `now` is the pass that just ran; nil means the engine's latest.
  func refresh(now: Double?) {
    guard isOpen || now == nil else {
      // Closed, nothing is listed: a task that has gone since is forgotten all the same (D40).
      ender.forgetGone()
      return
    }
    let at = now ?? engine.now
    graph.show(engine.history, now: at)
    legend.attributedStringValue = Self.legendText(engine.legend(now: at))
    let rates = engine.netDisk(now: at)
    networkLine.stringValue = ByteRateText.network(rates.network)
    diskLine.stringValue = ByteRateText.disk(rates.disk)
    guard isOpen, now != nil else { return }
    followPointer()
    if tasks.sample(now: clock()) { showList() }
    showButtons()
  }

  /// Between passes: the first list after the panel opens shows as soon as it can be measured,
  /// and a row whose End button the pointer has left is let go at once.
  func tick() {
    guard isOpen else { return }
    followPointer()
    if !tasks.hasList, tasks.sample(now: clock()) { showList() }
    showButtons()
  }

  /// Holds the row whose End button the pointer rests on, and lets it go once the pointer has
  /// left the button, re-ranking the list there and then (D100, D101).
  private func followPointer() {
    let resting = list.endButtonRow(under: NSEvent.mouseLocation)
    if hold.follow(resting: resting, shown: shownRows.map(\.task.id)) { showList() }
  }

  /// The list as ranked now, holding the row whose End button the pointer rests on (D100). When
  /// the held task has gone the list refills, and the End button that slides under the pointer
  /// is greyed out until the pointer leaves it.
  private func showList() {
    var rows = HeavyTasks.rank(tasks.tasks)
    if let held = hold.held {
      if tasks.tasks.contains(where: { $0.id == held.id }) {
        rows = HeavyTasks.holding(
          held.id, at: held.index, in: rows, tasks: tasks.tasks)
      } else {
        hold.heldTaskLeft()
      }
    }
    // A task that has gone takes its ending state with it (D40); until a list is measured (the
    // panel just opened) nothing is known to have gone.
    if tasks.hasList { ender.keep(only: Set(tasks.tasks.map(\.id))) }
    shownRows = rows
    let now = clock()
    list.disarmedRow = hold.disarmed
    list.show(rows) { ender.button(for: $0, now: now) }
  }

  /// Every End button as its task's ending state reads now: `Ending…` turns into `Force Quit`
  /// five seconds after the click (D62).
  private func showButtons() {
    let now = clock()
    list.disarmedRow = hold.disarmed
    list.showButtons { ender.button(for: $0, now: now) }
  }

  /// The user clicked the End, or Force Quit, button of the row showing `task`. No
  /// confirmation is asked (D60).
  private func end(_ task: TaskID) {
    // A row whose task has gone or been replaced sends nothing, and the list is measured afresh
    // at once (PanelClick).
    if PanelClick.end(task, ender: ender, sampler: tasks, now: clock()) { showList() }
    showButtons()
  }

  @objc private func openActivityMonitor(_ sender: Any?) {
    guard
      let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.ActivityMonitor")
    else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
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
///
/// The graph is painted into a bitmap of the meter's own and shown as its layer's contents.
/// Painted in `draw(_:)` instead, it cost the meter about 45 MB of graphics memory while the panel
/// was open (`footprint`: "Owned physical footprint (unmapped) (graphics)"), taking its Memory in
/// Activity Monitor to 69 MB, over the 50 MB line (D76); the bitmap costs under 1 MB (DESIGN, P7).
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
  /// The bitmap the graph is painted into, kept while the view's size and scale stay the same.
  private var bitmap: CGContext?

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

  override var wantsUpdateLayer: Bool { true }

  /// Paints the graph into the bitmap, in the panel's appearance, and shows it.
  override func updateLayer() {
    guard let layer else { return }
    let scale = window?.backingScaleFactor ?? 2
    let width = Int((bounds.width * scale).rounded())
    let height = Int((bounds.height * scale).rounded())
    guard width > 0, height > 0 else { return }
    if bitmap?.width != width || bitmap?.height != height {
      bitmap = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: window?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue)
    }
    guard let bitmap else { return }
    bitmap.saveGState()
    bitmap.clear(CGRect(x: 0, y: 0, width: width, height: height))
    bitmap.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
    effectiveAppearance.performAsCurrentDrawingAppearance { self.paint() }
    NSGraphicsContext.restoreGraphicsState()
    bitmap.restoreGState()
    layer.contentsScale = scale
    layer.contents = bitmap.makeImage()
  }

  private func paint() {
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
