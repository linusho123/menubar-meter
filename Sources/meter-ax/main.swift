import AppKit
import ApplicationServices

// Test harness helper: reads menu bar status items through the Accessibility API, the way
// any assistive app sees them. It never talks to the meter itself.
//
//   meter-ax item <pid>          the status item(s) of one app, as JSON
//   meter-ax items               every app's status items, as JSON
//   meter-ax watch <pid> <ms>    print "<epoch ms>\t<title>" each time the item's title changes
//   meter-ax press <pid>         press the app's status item, as a click on it does
//   meter-ax windows <pid>       the app's windows and every element in them, as JSON: role,
//                                text, frame, and for text the frame of each word

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
  list.append(entry)
  for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    describe(child, into: &list)
  }
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
case "windows":
  guard arguments.count == 3, let pid = Int32(arguments[2]) else { fail("usage: windows <pid>") }
  emit(windows(pid: pid))
default:
  fail("usage: meter-ax item <pid> | items | watch <pid> <ms> | press <pid> | windows <pid>")
}
