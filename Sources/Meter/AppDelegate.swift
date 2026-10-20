import AppKit
import MeterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: StatusItemController?
  private var panel: PanelController?
  private var timer: Timer?
  private var engine: MeterEngine?
  private var clock: () -> Double = Clock.now

  func applicationDidFinishLaunching(_ notification: Notification) {
    let inputs = makeInputs()
    let engine = MeterEngine(inputs: inputs)
    // The task sampler reads the same source as the sampler: the real tasks, or the fed ones.
    let tasks = TaskSampler(inputs: (inputs as? TaskInputs) ?? RealInputs())
    let panel = PanelController(engine: engine, tasks: tasks) { [weak self] in
      self?.clock() ?? Clock.now()
    }
    let statusItem = StatusItemController { [weak self] button in
      self?.panel?.toggle(below: button)
    }
    self.engine = engine
    self.panel = panel
    self.statusItem = statusItem

    // The system's own sleep and wake notifications: a sleep is a gap in the graph (D52).
    let workspace = NSWorkspace.shared.notificationCenter
    workspace.addObserver(
      self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    workspace.addObserver(
      self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

    #if METER_TEST_SOURCE
      // The test reading source may give the meter a past to have run through: it drives the
      // same loop over the past's own clock before the live loop starts.
      (inputs as? TestInputs)?.runPast { [engine] now in _ = engine.tick(now: now) }
    #endif

    statusItem.show(engine.begin(now: clock()))

    let timer = Timer(timeInterval: Sampler.cpuInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    timer.tolerance = 0
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func tick() {
    guard let engine, let statusItem else { return }
    let now = clock()
    if let readout = engine.tick(now: now) {
      statusItem.show(readout)
      panel?.refresh(now: now)
    } else {
      panel?.tick()
    }
  }

  @objc private func willSleep(_ notification: Notification) {
    engine?.willSleep(now: clock())
  }

  @objc private func didWake(_ notification: Notification) {
    engine?.didWake(now: clock())
  }

  private func makeInputs() -> MeterInputs {
    let real = RealInputs()
    #if METER_TEST_SOURCE
      if let feed = ProcessInfo.processInfo.environment[TestInputs.feedVariable] {
        let test = TestInputs(feedPath: feed, real: real)
        clock = { [test] in test.now() }
        return test
      }
    #endif
    return real
  }
}
