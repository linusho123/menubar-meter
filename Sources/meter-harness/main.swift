// Test harness helper. Never bundled into the app.
//
//   meter-harness trusted                      exit 0 if Accessibility is granted, else 3
//   meter-harness item <pid>                   the app's menu bar item as JSON {title,x,y,w,h}
//   meter-harness items <pid>                  every status item of the app: {items:[…]}
//   meter-harness watch <pid> <regex> <deadlineEpochMs>
//                                              poll the item's title until it matches the regex;
//                                              prints {matched, seenAtEpochMs, title}
//   meter-harness am-memory <pid>              Activity Monitor's Memory tab summary, read from its
//                                              window: {"Memory Used:": "23.65 GB", …}
//   meter-harness marker                       show a stand-in status item "◆" until killed
//
// Everything it reports is what macOS's Accessibility API says the menu bar
// shows: the far side of the meter.
import AppKit
import ApplicationServices

func emit(_ obj: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value
}

/// The status items of the app with this pid.
func statusItems(pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1.0)
    guard let bar = attr(app, "AXExtrasMenuBar") else { return [] }
    return attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func statusItem(pid: pid_t) -> AXUIElement? { statusItems(pid: pid).first }

func itemInfo(_ el: AXUIElement) -> [String: Any] {
    var out: [String: Any] = [:]
    out["title"] = attr(el, kAXTitleAttribute) as? String ?? NSNull()
    var point = CGPoint.zero, size = CGSize.zero
    if let p = attr(el, kAXPositionAttribute) { AXValueGetValue(p as! AXValue, .cgPoint, &point) }
    if let s = attr(el, kAXSizeAttribute) { AXValueGetValue(s as! AXValue, .cgSize, &size) }
    out["x"] = point.x; out["y"] = point.y; out["w"] = size.width; out["h"] = size.height
    return out
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: meter-harness trusted|item|watch|marker …") }

switch args[1] {
case "trusted":
    exit(AXIsProcessTrusted() ? 0 : 3)

case "item":
    guard args.count == 3, let pid = pid_t(args[2]) else { fail("usage: item <pid>") }
    guard AXIsProcessTrusted() else { fail("Accessibility permission is not granted to this terminal", code: 3) }
    guard let el = statusItem(pid: pid) else { emit(["error": "no status item"]); exit(1) }
    emit(itemInfo(el))

case "items":
    guard args.count == 3, let pid = pid_t(args[2]) else { fail("usage: items <pid>") }
    guard AXIsProcessTrusted() else { fail("Accessibility permission is not granted to this terminal", code: 3) }
    emit(["items": statusItems(pid: pid).map { el -> [String: Any] in
        var info = itemInfo(el)
        info["description"] = attr(el, kAXDescriptionAttribute) as? String ?? NSNull()
        return info
    }])

case "watch":
    guard args.count == 5, let pid = pid_t(args[2]), let deadline = Double(args[4]) else {
        fail("usage: watch <pid> <regex> <deadlineEpochMs>")
    }
    guard AXIsProcessTrusted() else { fail("Accessibility permission is not granted to this terminal", code: 3) }
    let re = try! NSRegularExpression(pattern: args[3])
    var last: String? = nil
    while true {
        let t = nowMs()
        if let el = statusItem(pid: pid), let title = attr(el, kAXTitleAttribute) as? String {
            last = title
            if re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
                emit(["matched": true, "seenAtEpochMs": t, "title": title])
                exit(0)
            }
        }
        if t > deadline {
            emit(["matched": false, "seenAtEpochMs": t, "title": last ?? NSNull()])
            exit(1)
        }
        usleep(5_000)
    }

case "am-memory":
    guard args.count == 3, let pid = pid_t(args[2]) else { fail("usage: am-memory <pid>") }
    guard AXIsProcessTrusted() else { fail("Accessibility permission is not granted to this terminal", code: 3) }
    // The summary under the process table: each label paired with the value
    // text on its row, to its right. The process table itself is skipped.
    var texts: [(String, CGPoint)] = []
    func walk(_ el: AXUIElement, _ depth: Int) {
        guard depth < 12 else { return }
        let role = attr(el, kAXRoleAttribute) as? String ?? ""
        if role == "AXTable" || role == "AXOutline" || role == "AXToolbar" { return }
        if role == "AXStaticText", let v = attr(el, kAXValueAttribute) as? String, !v.isEmpty {
            var p = CGPoint.zero
            if let pv = attr(el, kAXPositionAttribute) { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
            texts.append((v, p))
        }
        for c in attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(c, depth + 1) }
    }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 2.0)
    for w in attr(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] { walk(w, 0) }
    let isValue = { (t: String) in t.range(of: #"^[0-9.,]+ (bytes|KB|MB|GB|TB)$"#, options: .regularExpression) != nil }
    var out: [String: Any] = [:]
    for (label, p) in texts where label.hasSuffix(":") {
        let row = texts.filter { isValue($0.0) && abs($0.1.y - p.y) < 4 && $0.1.x > p.x }
        if let nearest = row.min(by: { $0.1.x < $1.1.x }) { out[label] = nearest.0 }
    }
    out["sampledAtEpochMs"] = nowMs()
    emit(out)

case "marker":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "◆"
    app.run()

default:
    fail("unknown command \(args[1])")
}
