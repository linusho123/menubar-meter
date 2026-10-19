import AppKit
import MeterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: StatusItemController?
  private var timer: Timer?
  private var sampler: Sampler?
  private var cpuReads = 0

  func applicationDidFinishLaunching(_ notification: Notification) {
    let sampler = Sampler(inputs: Self.makeInputs())
    let statusItem = StatusItemController()
    self.sampler = sampler
    self.statusItem = statusItem

    let now = ProcessInfo.processInfo.systemUptime
    sampler.sampleCPU(now: now)
    statusItem.show(sampler.pass(now: now))

    let timer = Timer(timeInterval: Sampler.cpuInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    timer.tolerance = 0
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func tick() {
    guard let sampler, let statusItem else { return }
    let now = ProcessInfo.processInfo.systemUptime
    sampler.sampleCPU(now: now)
    cpuReads += 1
    let readsPerPass = Int((Sampler.passInterval / Sampler.cpuInterval).rounded())
    if cpuReads % readsPerPass == 0 {
      statusItem.show(sampler.pass(now: now))
    }
  }

  private static func makeInputs() -> MeterInputs {
    let real = RealInputs()
    #if METER_TEST_SOURCE
      if let feed = ProcessInfo.processInfo.environment[TestInputs.feedVariable] {
        return TestInputs(feedPath: feed, real: real)
      }
    #endif
    return real
  }
}
