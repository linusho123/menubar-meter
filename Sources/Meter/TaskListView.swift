import AppKit
import MeterCore

/// The heavy-tasks list (D10): the heading `heavy tasks` with the columns CPU, GPU and RAM, then
/// one row per task with its name (cut short with an ellipsis when too long), its plain tags just
/// after it,
/// its three values to one decimal, and its End button, or the word `system` where it has none
/// (D99, D57). The End button reads `End`, `Ending…` or `Force Quit` as its task's ending state
/// says (D60, D62, D63). Every row is drawn alike: no colour, icon, highlight or warning (D110).
/// Styled as Notch Island is: dim headings, white text and pill buttons (PanelStyle).
@MainActor
final class TaskListView: NSView {
  /// Column edges within a row, from the left, for a list of a given width: the End pill at the
  /// right, the three values right-aligned before it, and the name with its tags in the rest.
  struct Columns {
    /// Wide enough for the `Force Quit` pill.
    static let endWidth: CGFloat = 56
    /// A value field, wide enough for `100.0%`; the fields overlap a little, their text never.
    static let valueWidth: CGFloat = 46
    static let valueStep: CGFloat = 42

    let name: (x: CGFloat, width: CGFloat)
    let values: [(x: CGFloat, width: CGFloat)]
    let end: (x: CGFloat, width: CGFloat)

    init(width: CGFloat) {
      end = (width - Self.endWidth, Self.endWidth)
      let lastRight = end.x - 4
      values = (0..<3).map { index in
        let right = lastRight - CGFloat(2 - index) * Self.valueStep
        return (right - Self.valueWidth, Self.valueWidth)
      }
      // The name runs up to where a CPU value of `99.9%` would begin.
      name = (0, values[0].x + Self.valueWidth - 40)
    }
  }

  private let rowViews: [TaskRowView]

  /// The row whose End button is greyed out, whatever its task's state, until the pointer leaves
  /// it: the task that moved under the resting pointer is not the one the user chose.
  var disarmedRow: Int? {
    didSet { for (index, row) in rowViews.enumerated() { row.armed = index != disarmedRow } }
  }

  /// Called when the user clicks the End button of the row showing task `id`.
  var onEnd: ((TaskID) -> Void)? {
    didSet { for row in rowViews { row.onEnd = onEnd } }
  }

  init(width: CGFloat, rowHeight: CGFloat, rows: Int) {
    let headerHeight: CGFloat = 18
    let columns = Columns(width: width)
    var views: [TaskRowView] = []
    for index in 0..<rows {
      views.append(
        TaskRowView(
          frame: NSRect(
            x: 0, y: CGFloat(rows - 1 - index) * rowHeight, width: width, height: rowHeight),
          columns: columns))
    }
    rowViews = views
    super.init(
      frame: NSRect(
        x: 0, y: 0, width: width, height: CGFloat(rows) * rowHeight + headerHeight + 2))

    let headerY = CGFloat(rows) * rowHeight + 2
    let heading = Self.label(
      "heavy tasks", alignment: .left, color: PanelStyle.tertiary, font: PanelStyle.heading)
    heading.frame = NSRect(
      x: columns.name.x, y: headerY, width: columns.name.width, height: headerHeight)
    addSubview(heading)
    for (title, column) in zip(["CPU", "GPU", "RAM"], columns.values) {
      let header = Self.label(
        title, alignment: .right, color: PanelStyle.tertiary, font: PanelStyle.heading)
      header.frame = NSRect(x: column.x, y: headerY, width: column.width, height: headerHeight)
      addSubview(header)
    }
    for row in views {
      row.isHidden = true
      addSubview(row)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  static func label(
    _ text: String, alignment: NSTextAlignment, color: NSColor, font: NSFont = PanelStyle.row
  ) -> NSTextField {
    PanelStyle.label(text, font: font, color: color, alignment: alignment)
  }

  /// The row whose End button lies under a point on screen, if any shows there.
  func endButtonRow(under point: NSPoint) -> Int? {
    guard let window, !isHidden else { return nil }
    return rowViews.firstIndex { row in
      guard !row.isHidden, !row.endButton.isHidden else { return false }
      let button = row.endButton
      return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }
  }

  /// Forgets the pointer on every End button, for a panel that closed with it resting on one.
  func resetHover() {
    for row in rowViews { row.endButton.resetHover() }
  }

  /// Shows `rows`, each End button as `button` says for the row's task.
  func show(_ rows: [HeavyRow], button: (TaskID) -> EndButton) {
    for (index, view) in rowViews.enumerated() {
      if index < rows.count {
        view.show(rows[index], button: button(rows[index].task.id))
        view.isHidden = false
      } else {
        view.isHidden = true
        view.task = nil
      }
    }
  }

  /// Brings every shown End button up to date with its task's ending state.
  func showButtons(_ button: (TaskID) -> EndButton) {
    for view in rowViews where !view.isHidden {
      if let task = view.task { view.showButton(button(task)) }
    }
  }
}

/// One row of the list.
@MainActor
final class TaskRowView: NSView {
  private let name = TaskListView.label("", alignment: .left, color: PanelStyle.primary)
  private let tagField = TaskListView.label("", alignment: .left, color: PanelStyle.tertiary)
  private let values = (0..<3).map { _ in
    TaskListView.label("", alignment: .right, color: PanelStyle.secondary)
  }
  private let system = TaskListView.label(
    HeavyTasks.systemTag, alignment: .right, color: PanelStyle.tertiary)
  let endButton = EndButtonView()
  private let columns: TaskListView.Columns

  /// The task the row shows now, and the one it showed when the mouse went down on its End
  /// button: a click acts only if the row still shows the task it was begun on.
  var task: TaskID?
  /// False while the pointer rests on the End button of a task that moved in under it.
  var armed = true {
    didSet { if let state { showButton(state) } }
  }
  private var state: EndButton?
  private var pressedOn: TaskID?
  var onEnd: ((TaskID) -> Void)?

  init(frame: NSRect, columns: TaskListView.Columns) {
    self.columns = columns
    super.init(frame: frame)
    let textHeight: CGFloat = 16
    let textY = (frame.height - textHeight) / 2
    name.frame = NSRect(x: columns.name.x, y: textY, width: columns.name.width, height: textHeight)
    tagField.frame = NSRect(x: columns.name.x, y: textY, width: 0, height: textHeight)
    for (field, column) in zip(values, columns.values) {
      field.frame = NSRect(x: column.x, y: textY, width: column.width, height: textHeight)
    }
    let end = NSRect(x: columns.end.x, y: 2, width: columns.end.width, height: frame.height - 4)
    system.frame = NSRect(x: end.minX, y: textY, width: end.width, height: textHeight)
    endButton.frame = end
    endButton.target = self
    endButton.action = #selector(endClicked(_:))
    endButton.onMouseDown = { [weak self] in self?.pressedOn = self?.task }
    endButton.onMouseUp = { [weak self] in self?.pressedOn = nil }
    for view in [name, tagField] + values + [system, endButton] { addSubview(view) }
  }

  required init?(coder: NSCoder) {
    fatalError("not used")
  }

  @objc private func endClicked(_ sender: Any?) {
    guard let task, armed else { return }
    // The row was re-ranked between the mouse going down and coming up: not this task.
    if let pressedOn, pressedOn != task { return }
    onEnd?(task)
  }

  func showButton(_ state: EndButton) {
    self.state = state
    if endButton.title != state.title { endButton.title = state.title }
    endButton.isEnabled = state.isClickable && armed
  }

  /// The width a label needs to show its whole text: the text and the cell's inset either side.
  private static func fieldWidth(_ field: NSTextField) -> CGFloat {
    ceil(field.attributedStringValue.size().width) + 5
  }

  func show(_ row: HeavyRow, button: EndButton) {
    task = row.task.id
    showButton(button)
    name.stringValue = row.task.name
    let tags = row.tags.map(\.text).joined(separator: " ")
    tagField.stringValue = tags
    tagField.isHidden = tags.isEmpty
    // The tags sit just after the name, which gives way to them when the room runs short.
    let tagWidth = tags.isEmpty ? 0 : Self.fieldWidth(tagField)
    let room = columns.name.width - (tags.isEmpty ? 0 : tagWidth + 2)
    name.frame.size.width = min(Self.fieldWidth(name), room)
    tagField.frame.origin.x = name.frame.maxX + 2
    tagField.frame.size.width = tagWidth
    for (field, share) in zip(values, [row.task.cpu, row.task.gpu, row.task.ram]) {
      field.stringValue = TaskText.value(share)
    }
    system.isHidden = !row.task.isSystem
    endButton.isHidden = row.task.isSystem
  }
}

/// An End button, drawn as a Notch Island pill: it takes the first click even though the panel is
/// never the key window, and tells its row when the mouse goes down on it and when the click is
/// over. Greyed out, it dims; it never takes a colour (D110).
final class EndButtonView: HoverButton {
  var onMouseDown: (() -> Void)?
  var onMouseUp: (() -> Void)?

  convenience init() {
    self.init(frame: .zero)
    title = EndButton.end.title
    isBordered = false
    setButtonType(.momentaryPushIn)
    font = PanelStyle.pillFont
    alignment = .center
  }

  override var isEnabled: Bool {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    let lit = isHighlighted || isHovered
    let fill = !isEnabled ? PanelStyle.tile : lit ? PanelStyle.pillHover : PanelStyle.pill
    fill.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    let text = NSAttributedString(
      string: title,
      attributes: [
        .font: PanelStyle.pillFont,
        .foregroundColor: isEnabled ? PanelStyle.primary : PanelStyle.disabled,
      ])
    let size = text.size()
    text.draw(
      at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
  }

  override func mouseDown(with event: NSEvent) {
    onMouseDown?()
    // The click is tracked, and its action sent, before this returns.
    super.mouseDown(with: event)
    onMouseUp?()
  }
}

/// One of the panel's last rows: a plain clickable line of text, as a menu item reads, lit softly
/// under the pointer.
final class ActionRow: HoverButton {
  /// The title's inset from the row's left edge, level with the tiles' contents.
  static let inset: CGFloat = 10

  convenience init(title: String) {
    self.init(frame: .zero)
    self.title = title
    isBordered = false
    setButtonType(.momentaryPushIn)
    font = PanelStyle.action
  }

  override func draw(_ dirtyRect: NSRect) {
    if isHighlighted || isHovered {
      PanelStyle.rowHover.setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }
    let text = NSAttributedString(
      string: title, attributes: [.font: PanelStyle.action, .foregroundColor: PanelStyle.primary])
    let size = text.size()
    text.draw(at: NSPoint(x: Self.inset, y: (bounds.height - size.height) / 2))
  }
}
