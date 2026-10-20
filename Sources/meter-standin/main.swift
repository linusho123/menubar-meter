import AppKit

// Test harness stand-in: a task the harness runs and the only kind of task a test may end.
//
//   meter-standin <record file> <control file> [busy threads]
//
// Run from inside an .app bundle it is an app (with no Dock icon) that answers the quit request
// an app's Quit menu item answers; run as a plain program it is a windowless task. Either way it
// ignores the terminate signal, so it ends only when the harness lets it or when it is killed.
// It appends one line to the record file for each thing it receives:
//   READY <epoch ms>                        it is running and can receive a request
//   QUIT <epoch ms> <event class>/<event id> the app's quit request (the Apple event that asked)
//   TERM <epoch ms>                         the terminate signal
// Once it has received a quit request or the terminate signal, it exits (status 0) as soon as
// the control file reads `exit`: the harness decides how long it takes to quit, never whether
// it was asked. The kill cannot be caught: the harness sees it as the stand-in's exit signal.
// With busy threads it keeps that many cores busy, so it ranks high by CPU.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
  FileHandle.standardError.write(
    Data("usage: meter-standin <record file> <control file> [busy threads]\n".utf8))
  exit(2)
}
let recordPath = arguments[1]
let controlPath = arguments[2]
let busyThreads = arguments.count > 3 ? Int(arguments[3]) ?? 0 : 0

func record(_ kind: String, _ detail: String? = nil) {
  let stamp = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
  let text = "\(kind) \(stamp)" + (detail.map { " " + $0 } ?? "") + "\n"
  guard let handle = FileHandle(forWritingAtPath: recordPath) else {
    FileManager.default.createFile(atPath: recordPath, contents: Data(text.utf8))
    return
  }
  handle.seekToEndOfFile()
  handle.write(Data(text.utf8))
  handle.synchronizeFile()
  handle.closeFile()
}

func controlSaysExit() -> Bool {
  guard let data = FileManager.default.contents(atPath: controlPath) else { return false }
  return String(decoding: data, as: UTF8.self).contains("exit")
}

/// A busy loop the compiler cannot drop.
final class Spinner: Thread, @unchecked Sendable {
  private var count: UInt64 = 0
  override func main() {
    while true {
      count &+= 1
      if count == 0 { print("") }
    }
  }
}

for _ in 0..<busyThreads { Spinner().start() }

@MainActor
final class StandIn: NSObject, NSApplicationDelegate {
  private var asked = false
  private var quitPending = false
  private var termSource: DispatchSourceSignal?
  private var poll: Timer?

  func start(asApp: Bool) {
    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        record("TERM")
        self?.asked = true
      }
    }
    source.resume()
    termSource = source
    let poll = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.check() }
    }
    RunLoop.main.add(poll, forMode: .common)
    self.poll = poll
    if !asApp { record("READY") }
  }

  private func check() {
    guard asked, controlSaysExit() else { return }
    if quitPending {
      quitPending = false
      NSApp.reply(toApplicationShouldTerminate: true)
    } else {
      exit(0)
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    record("READY")
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let event = NSAppleEventManager.shared().currentAppleEvent
    let kind = event.map { "\(fourCC($0.eventClass))/\(fourCC($0.eventID))" } ?? "none/none"
    record("QUIT", kind)
    asked = true
    quitPending = true
    return .terminateLater
  }

  private func fourCC(_ code: UInt32) -> String {
    String(
      decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, as: UTF8.self)
  }
}

let asApp = Bundle.main.bundlePath.hasSuffix(".app")
MainActor.assumeIsolated {
  let standIn = StandIn()
  standIn.start(asApp: asApp)
  if asApp {
    let app = NSApplication.shared
    app.delegate = standIn
    app.setActivationPolicy(.accessory)
    app.run()
  } else {
    withExtendedLifetime(standIn) { RunLoop.main.run() }
  }
}
