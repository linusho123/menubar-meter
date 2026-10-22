import AppKit
import ApplicationServices

// Test harness helper: reads menu bar status items through the Accessibility API, the way
// any assistive app sees them. It never talks to the meter itself.
//
//   meter-ax item <pid>          the status item(s) of one app, as JSON
//   meter-ax items               every app's status items, as JSON
//   meter-ax watch <pid> <ms>    print "<epoch ms>\t<title>" each time the item's title changes
//   meter-ax press <pid>         press the app's status item, as a click on it does
//   meter-ax press-item <pid> <title>
//                                press the one status item of the app titled <title> (another
//                                app's menu bar extra, such as Control Center's Battery)
//   meter-ax windows <pid>       the app's windows and every element in them, as JSON: role,
//                                text, frame, and for text the frame of each word
//   meter-ax texts <pid>         the texts in the app's windows, in order, as a JSON array: a
//                                quick read, with no frames
//   meter-ax watch-texts <pid> <ms>
//                                print "<epoch ms>\t<texts as JSON>" each time they change
//   meter-ax press-button <pid> <title>
//                                press the button titled <title> in the app's windows
//   meter-ax move <x> <y>        move the pointer to a point on screen, as the mouse moves it
//   meter-ax click <x> <y>       click the left button at a point on screen, as the mouse does
//   meter-ax pointer             where the pointer is, as JSON
//   meter-ax front               the app in front, as JSON
//   meter-ax cell <pid> <key column> <key> <column>
//                                in the app's table, the text under <column> in the row whose
//                                <key column> reads <key>, as another app's table shows it

struct Item: Encodable {
  var pid: Int32
  var app: String
  var title: String
  var x: Double
  var y: Double
  var width: Double
  var height: Double
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
  var value: AnyObject?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
    return nil
  }
  return value
}

func point(_ element: AXUIElement) -> CGPoint? {
  guard let value = attribute(element, kAXPositionAttribute) else { return nil }
  var result = CGPoint.zero
  guard AXValueGetValue(value as! AXValue, .cgPoint, &result) else { return nil }
  return result
}

func size(_ element: AXUIElement) -> CGSize? {
  guard let value = attribute(element, kAXSizeAttribute) else { return nil }
  var result = CGSize.zero
  guard AXValueGetValue(value as! AXValue, .cgSize, &result) else { return nil }
  return result
}

func title(_ element: AXUIElement) -> String {
  for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
    if let text = attribute(element, name) as? String, !text.isEmpty { return text }
  }
  return ""
}

func statusElements(pid: Int32) -> [AXUIElement] {
  let app = AXUIElementCreateApplication(pid)
  guard let bar = attribute(app, "AXExtrasMenuBar"),
    let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]
  else { return [] }
  return children
}

func items(pid: Int32, name: String) -> [Item] {
  statusElements(pid: pid).compactMap { element in
    guard let origin = point(element), let extent = size(element) else { return nil }
    return Item(
      pid: pid, app: name, title: title(element), x: origin.x, y: origin.y,
      width: extent.width, height: extent.height)
  }
}

/// An element in a window, as an assistive app sees it. Frames are in screen points, origin at
/// the top left of the main display.
struct Element: Encodable {
  var role: String
  var subrole: String
  var text: String
  var x: Double
  var y: Double
  var width: Double
  var height: Double
  /// For text: each word with its frame on screen, from the text's own bounds-for-range.
  var words: [Word]?
  /// For a button: whether it can be clicked now.
  var enabled: Bool?
}

struct Word: Encodable {
  var text: String
  var x: Double
  var y: Double
  var width: Double
  var height: Double
}

struct Window: Encodable {
  var title: String
  var x: Double
  var y: Double
  var width: Double
  var height: Double
  var elements: [Element]
}

func words(of element: AXUIElement, text: String) -> [Word] {
  var result: [Word] = []
  let utf16 = Array(text.utf16)
  var start = 0
  while start < utf16.count {
    while start < utf16.count, utf16[start] == 0x20 { start += 1 }
    var end = start
    while end < utf16.count, utf16[end] != 0x20 { end += 1 }
    guard end > start else { break }
    var range = CFRange(location: start, length: end - start)
    var bounds: AnyObject?
    if let rangeValue = AXValueCreate(.cfRange, &range),
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds)
        == .success, let bounds
    {
      var rect = CGRect.zero
      if AXValueGetValue(bounds as! AXValue, .cgRect, &rect) {
        let word = String(utf16CodeUnits: Array(utf16[start..<end]), count: end - start)
        result.append(
          Word(
            text: word, x: rect.origin.x, y: rect.origin.y, width: rect.width,
            height: rect.height))
      }
    }
    start = end
  }
  return result
}

func describe(_ element: AXUIElement, into list: inout [Element]) {
  let role = attribute(element, kAXRoleAttribute) as? String ?? ""
  let origin = point(element) ?? .zero
  let extent = size(element) ?? .zero
  let text = title(element)
  var entry = Element(
    role: role, subrole: attribute(element, kAXSubroleAttribute) as? String ?? "", text: text,
    x: origin.x, y: origin.y, width: extent.width, height: extent.height)
  if role == kAXStaticTextRole, !text.isEmpty {
    entry.words = words(of: element, text: text)
  }
  if role == kAXButtonRole {
    entry.enabled = attribute(element, kAXEnabledAttribute) as? Bool
  }
  list.append(entry)
  for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    describe(child, into: &list)
  }
}

/// The static texts in the app's windows, in order.
func windowTexts(pid: Int32) -> [String] {
  var texts: [String] = []
  func collect(_ element: AXUIElement) {
    if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole {
      texts.append(title(element))
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      collect(child)
    }
  }
  let app = AXUIElementCreateApplication(pid)
  for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] { collect(window) }
  return texts
}

func windows(pid: Int32) -> [Window] {
  let app = AXUIElementCreateApplication(pid)
  let list = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
  return list.map { window in
    var elements: [Element] = []
    for child in attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      describe(child, into: &elements)
    }
    let origin = point(window) ?? .zero
    let extent = size(window) ?? .zero
    return Window(
      title: title(window), x: origin.x, y: origin.y, width: extent.width, height: extent.height,
      elements: elements)
  }
}

/// The text a table cell shows: its own value, or its first text's.
func cellText(_ cell: AXUIElement) -> String {
  if let value = attribute(cell, kAXValueAttribute) as? String { return value }
  for child in attribute(cell, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    if attribute(child, kAXRoleAttribute) as? String == kAXStaticTextRole {
      return (attribute(child, kAXValueAttribute) as? String ?? title(child))
        .trimmingCharacters(in: .whitespaces)
    }
  }
  return ""
}

/// The first table or outline in an element, without walking into one's rows.
func findTable(_ element: AXUIElement) -> AXUIElement? {
  let role = attribute(element, kAXRoleAttribute) as? String
  if role == kAXOutlineRole || role == kAXTableRole { return element }
  for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    if let found = findTable(child) { return found }
  }
  return nil
}

/// The text under `column` in the row whose `keyColumn` reads `key`, nil when no row does.
func tableCell(pid: Int32, keyColumn: String, key: String, column: String) -> String? {
  let app = AXUIElementCreateApplication(pid)
  for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
    guard let table = findTable(window),
      let header = attribute(table, kAXHeaderAttribute),
      let titles = attribute(header as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement],
      let columns = attribute(table, kAXColumnsAttribute) as? [AXUIElement],
      let rows = attribute(table, kAXRowsAttribute) as? [AXUIElement]
    else { continue }
    // A column's place among the cells, found by its heading's place on screen.
    func index(_ name: String) -> Int? {
      guard let heading = titles.first(where: { title($0) == name }), let x = point(heading)?.x
      else { return nil }
      return columns.firstIndex { point($0)?.x == x }
    }
    guard let keyIndex = index(keyColumn), let valueIndex = index(column) else { continue }
    for row in rows {
      guard let cells = attribute(row, kAXChildrenAttribute) as? [AXUIElement],
        cells.count > max(keyIndex, valueIndex), cellText(cells[keyIndex]) == key
      else { continue }
      return cellText(cells[valueIndex])
    }
  }
  return nil
}

func emit<T: Encodable>(_ value: T) {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let data = (try? encoder.encode(value)) ?? Data("null".utf8)
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

guard AXIsProcessTrusted() else {
  fail("meter-ax: this terminal lacks Accessibility permission")
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "item":
  guard arguments.count == 3, let pid = Int32(arguments[2]) else { fail("usage: item <pid>") }
  emit(items(pid: pid, name: ""))
case "items":
  var all: [Item] = []
  for app in NSWorkspace.shared.runningApplications {
    all += items(pid: app.processIdentifier, name: app.localizedName ?? "")
  }
  emit(all)
case "watch":
  guard arguments.count == 4, let pid = Int32(arguments[2]), let duration = Double(arguments[3])
  else { fail("usage: watch <pid> <ms>") }
  let end = Date().addingTimeInterval(duration / 1000)
  var last: String?
  setvbuf(stdout, nil, _IOLBF, 0)
  while Date() < end {
    let current = statusElements(pid: pid).first.map(title)
    if let current, current != last {
      last = current
      let stamp = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
      print("\(stamp)\t\(current)")
    }
    usleep(5000)
  }
case "press":
  guard arguments.count == 3, let pid = Int32(arguments[2]) else { fail("usage: press <pid>") }
  let elements = statusElements(pid: pid)
  guard elements.count == 1 else { fail("press: \(elements.count) status items for \(pid)") }
  let result = AXUIElementPerformAction(elements[0], kAXPressAction as CFString)
  guard result == .success else { fail("press: AXPress failed (\(result.rawValue))") }
case "press-item":
  guard arguments.count == 4, let pid = Int32(arguments[2]) else {
    fail("usage: press-item <pid> <title>")
  }
  let elements = statusElements(pid: pid).filter { title($0) == arguments[3] }
  guard elements.count == 1 else {
    fail("press-item: \(elements.count) status items titled \(arguments[3]) for \(pid)")
  }
  let result = AXUIElementPerformAction(elements[0], kAXPressAction as CFString)
  guard result == .success else { fail("press-item: AXPress failed (\(result.rawValue))") }
case "windows":
  guard arguments.count == 3, let pid = Int32(arguments[2]) else { fail("usage: windows <pid>") }
  emit(windows(pid: pid))
case "texts":
  guard arguments.count == 3, let pid = Int32(arguments[2]) else { fail("usage: texts <pid>") }
  emit(windowTexts(pid: pid))
case "watch-texts":
  guard arguments.count == 4, let pid = Int32(arguments[2]), let duration = Double(arguments[3])
  else { fail("usage: watch-texts <pid> <ms>") }
  let end = Date().addingTimeInterval(duration / 1000)
  var last: [String]?
  setvbuf(stdout, nil, _IOLBF, 0)
  let encoder = JSONEncoder()
  while Date() < end {
    let current = windowTexts(pid: pid)
    if current != last, let data = try? encoder.encode(current) {
      last = current
      let stamp = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
      print("\(stamp)\t\(String(decoding: data, as: UTF8.self))")
    }
    usleep(5000)
  }
case "press-button":
  guard arguments.count == 4, let pid = Int32(arguments[2]) else {
    fail("usage: press-button <pid> <title>")
  }
  let wanted = arguments[3]
  var found: [AXUIElement] = []
  func search(_ element: AXUIElement) {
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
      title(element) == wanted
    {
      found.append(element)
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
      search(child)
    }
  }
  let app = AXUIElementCreateApplication(pid)
  for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] { search(window) }
  guard found.count == 1 else { fail("press-button: \(found.count) buttons titled \(wanted)") }
  let result = AXUIElementPerformAction(found[0], kAXPressAction as CFString)
  guard result == .success else { fail("press-button: AXPress failed (\(result.rawValue))") }
case "move":
  guard arguments.count == 4, let x = Double(arguments[2]), let y = Double(arguments[3]) else {
    fail("usage: move <x> <y>")
  }
  // The pointer goes there, and the move is posted as the mouse posts one, until macOS reports
  // the pointer there.
  let target = CGPoint(x: x, y: y)
  for _ in 0..<20 {
    CGWarpMouseCursorPosition(target)
    CGEvent(
      mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target,
      mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(50000)
    if let now = CGEvent(source: nil)?.location, abs(now.x - x) < 1, abs(now.y - y) < 1 {
      exit(0)
    }
  }
  fail("move: the pointer did not move to \(x), \(y)")
case "click":
  guard arguments.count == 4, let x = Double(arguments[2]), let y = Double(arguments[3]) else {
    fail("usage: click <x> <y>")
  }
  // The pointer is already there (the harness rests it there first, as a user does), so the
  // button is pressed and let go where it is.
  let target = CGPoint(x: x, y: y)
  guard let now = CGEvent(source: nil)?.location, abs(now.x - x) < 1, abs(now.y - y) < 1 else {
    fail("click: the pointer is not at \(x), \(y)")
  }
  for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    let event = CGEvent(
      mouseEventSource: nil, mouseType: type, mouseCursorPosition: target, mouseButton: .left)
    event?.setIntegerValueField(.mouseEventClickState, value: 1)
    event?.post(tap: .cghidEventTap)
    usleep(60000)
  }
case "pointer":
  struct Pointer: Encodable {
    var x: Double
    var y: Double
  }
  guard let location = CGEvent(source: nil)?.location else { fail("pointer: no event") }
  emit(Pointer(x: location.x, y: location.y))
case "cell":
  guard arguments.count == 6, let pid = Int32(arguments[2]) else {
    fail("usage: cell <pid> <key column> <key> <column>")
  }
  guard
    let text = tableCell(pid: pid, keyColumn: arguments[3], key: arguments[4], column: arguments[5])
  else { fail("cell: no row whose \(arguments[3]) reads \(arguments[4])") }
  print(text)
case "front":
  struct Front: Encodable {
    var pid: Int32
    var name: String
    var bundle: String
  }
  guard let app = NSWorkspace.shared.frontmostApplication else { fail("front: no app") }
  emit(
    Front(
      pid: app.processIdentifier, name: app.localizedName ?? "",
      bundle: app.bundleIdentifier ?? ""))
default:
  fail(
    "usage: meter-ax item <pid> | items | watch <pid> <ms> | press <pid> | press-item <pid> <title>"
      + " | windows <pid>"
      + " | texts <pid> | watch-texts <pid> <ms> | press-button <pid> <title> | move <x> <y> | click <x> <y> | pointer"
      + " | cell <pid> <key column> <key> <column>"
      + " | front")
}
