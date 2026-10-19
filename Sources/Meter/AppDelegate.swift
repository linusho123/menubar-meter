import AppKit
import MeterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var sampler: Sampler!
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "meter.sampler", qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController()
        sampler = Sampler(inputs: Self.makeInputs())

        // One sampling pass a second; the menu bar shows each pass's result.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.pass() }
        timer.resume()
        self.timer = timer
    }

    private func pass() {
        let now = Date()
        sampler.pass(now: now)
        let text = Readout.text(cpu: sampler.cpu, gpu: sampler.gpu, ram: sampler.ram,
                                temperature: sampler.temperature, now: now)
        DispatchQueue.main.async { [weak self] in self?.statusItem.show(text) }
    }

    private static func makeInputs() -> ReadingInputs {
        #if METER_TEST_SOURCE
        if let test = TestInputs.fromEnvironment() { return test }
        #endif
        return RealInputs()
    }
}
