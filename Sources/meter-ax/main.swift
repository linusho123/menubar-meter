import AppKit
import ApplicationServices

// Test harness helper: reads menu bar status items through the Accessibility API, the way
// any assistive app sees them. It never talks to the meter itself.
//
//   meter-ax item <pid>          the status item(s) of one app, as JSON
//   meter-ax items               every app's status items, as JSON
//   meter-ax watch <pid> <ms>    print "<epoch ms>\t<title>" each time the item's title changes

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
default:
  fail("usage: meter-ax item <pid> | items | watch <pid> <ms>")
}
