import AppKit
import MeterCore

/// The heavy-tasks list (D10): the heading `heavy tasks` with the columns CPU, GPU and RAM, then
/// one row per task with its name (cut short with an ellipsis when too long), its plain tags,
/// its three values to one decimal, and its End button, or the word `system` where it has none
/// (D99, D57). The End button reads `End`, `Ending…` or `Force Quit` as its task's ending state
/// says (D60, D62, D63). Every row is drawn alike: no colour, icon, highlight or warning (D110).
@MainActor
final class TaskListView: NSView {
  /// Column edges within a row, from the left.
  enum Column {
    static let name: (x: CGFloat, width: CGFloat) = (0, 104)
    static let tag: (x: CGFloat, width: CGFloat) = (106, 40)
    static let values: [(x: CGFloat, width: CGFloat)] = [(148, 46), (196, 46), (244, 46)]
    /// Wide enough for `Force Quit`.
    static let end: (x: CGFloat, width: CGFloat) = (294, 66)
  }

  static let font = NSFont.monospacedDigitSystemFont(
    ofSize: NSFont.systemFontSize(for: .small) + 1, weight: .regular)

  private let rowViews: [TaskRowView]

  /// Called when the user clicks the End button of the row showing task `id`.
  var onEnd: ((TaskID) -> Void)? {
    didSet { for row in rowViews { row.onEnd = onEnd } }
  }

  init(width: CGFloat, rowHeight: CGFloat, rows: Int) {
    let headerHeight: CGFloat = 18
    var views: [TaskRowView] = []
    for index in 0..<rows {
      views.append(
        TaskRowView(
          frame: NSRect(
            x: 0, y: CGFloat(rows - 1 - index) * rowHeight, width: width, height: rowHeight)))
    }
    rowViews = views
    super.init(
      frame: NSRect(
        x: 0, y: 0, width: width, height: CGFloat(rows) * rowHeight + headerHeight + 2))

    let headerY = CGFloat(rows) * rowHeight + 2
    let heading = Self.label("heavy tasks", alignment: .left, color: .secondaryLabelColor)
    heading.frame = NSRect(
      x: Column.name.x, y: headerY, width: Column.name.width + Column.tag.width,
      height: headerHeight)
    addSubview(heading)
    for (title, column) in zip(["CPU", "GPU", "RAM"], Column.values) {
      let header = Self.label(title, alignment: .right, color: .secondaryLabelColor)
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

  static func label(_ text: String, alignment: NSTextAlignment, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = font
    field.textColor = color
    field.alignment = alignment
    field.lineBreakMode = .byTruncatingTail
    return field
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
  private let name = TaskListView.label("", alignment: .left, color: .labelColor)
  private let tagField = TaskListView.label("", alignment: .left, color: .labelColor)
  private let values = (0..<3).map { _ in
    TaskListView.label("", alignment: .right, color: .labelColor)
  }
  private let system = TaskListView.label(
    HeavyTasks.systemTag, alignment: .center, color: .labelColor)
  let endButton = EndButtonView(title: EndButton.end.title, target: nil, action: nil)

  /// The task the row shows now, and the one it showed when the mouse went down on its End
  /// button: a click acts only if the row still shows the task it was begun on.
  var task: TaskID?
  private var pressedOn: TaskID?
  var onEnd: ((TaskID) -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    let textHeight: CGFloat = 16
    let textY = (frame.height - textHeight) / 2
    typealias Column = TaskListView.Column
    name.frame = NSRect(x: Column.name.x, y: textY, width: Column.name.width, height: textHeight)
    tagField.frame = NSRect(x: Column.tag.x, y: textY, width: Column.tag.width, height: textHeight)
    for (field, column) in zip(values, Column.values) {
      field.frame = NSRect(x: column.x, y: textY, width: column.width, height: textHeight)
    }
    let end = NSRect(x: Column.end.x, y: 0, width: Column.end.width, height: frame.height)
    system.frame = NSRect(x: end.minX, y: textY, width: end.width, height: textHeight)
    endButton.controlSize = .small
    endButton.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
    endButton.bezelStyle = .push
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
    guard let task else { return }
    // The row was re-ranked between the mouse going down and coming up: not this task.
    if let pressedOn, pressedOn != task { return }
    onEnd?(task)
  }

  func showButton(_ state: EndButton) {
    if endButton.title != state.title { endButton.title = state.title }
    endButton.isEnabled = state.isClickable
  }

  func show(_ row: HeavyRow, button: EndButton) {
    task = row.task.id
    showButton(button)
    name.stringValue = row.task.name
    let tags = row.tags.map(\.text).joined(separator: " ")
    tagField.stringValue = tags
    tagField.isHidden = tags.isEmpty
    for (field, share) in zip(values, [row.task.cpu, row.task.gpu, row.task.ram]) {
      field.stringValue = TaskText.value(share)
    }
    system.isHidden = !row.task.isSystem
    endButton.isHidden = row.task.isSystem
  }
}

/// An End button that takes the first click even though the panel is never the key window, and
/// tells its row when the mouse goes down on it and when the click is over.
final class EndButtonView: NSButton {
  var onMouseDown: (() -> Void)?
  var onMouseUp: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    onMouseDown?()
    // The click is tracked, and its action sent, before this returns.
    super.mouseDown(with: event)
    onMouseUp?()
  }
}

/// One of the panel's last rows: a plain clickable line of text, as a menu item reads.
final class ActionRow: NSButton {
  convenience init(title: String) {
    self.init(frame: .zero)
    self.title = title
    isBordered = false
    alignment = .left
    font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    setButtonType(.momentaryChange)
  }
}
