import Testing

@testable import MeterCore

/// Fixed inputs, set by each test; never the real system.
private final class FixedInputs: MeterInputs {
  var ticks: CPUTicks? = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
  var pages: MemoryPages? = MemoryPages(
    anonymous: 0, purgeable: 0, wired: 0, compressed: 0, fileBacked: 0)
  var gpu: [String: Int]? = ["Device Utilization %": 0]
  var sensors: [String: Double]? = ["PMU tdie1": 40]
  let physicalMemory: UInt64 = 1000 * 100
  let pageSize: UInt64 = 100

  func cpuTicks() -> CPUTicks? { ticks }
  func memoryPages() -> MemoryPages? { pages }
  func gpuPerformanceStatistics() -> [String: Int]? { gpu }
  func temperatureSensors() -> [String: Double]? { sensors }
  var interfaces: [InterfaceCounters]?
  var disks: [String: ByteCounts]?
  func networkInterfaces(now: Double) -> [InterfaceCounters]? { interfaces }
  func diskCounters(now: Double) -> [String: ByteCounts]? { disks }

  func addLoad(user: UInt64, system: UInt64, idle: UInt64) {
    ticks?.user += user
    ticks?.system += system
    ticks?.idle += idle
  }
}

@Suite("The sampler")
struct SamplerTests {
  @Test("CPU needs two counter reads; then every reading shows")
  func firstReadings() {
    let inputs = FixedInputs()
    inputs.pages = MemoryPages(anonymous: 300, purgeable: 0, wired: 0, compressed: 0, fileBacked: 0)
    inputs.gpu = ["Device Utilization %": 7]
    let sampler = Sampler(inputs: inputs)
    sampler.sampleCPU(now: 0)
    #expect(sampler.pass(now: 0) == Readout(cpu: nil, gpu: 7, ram: 30, temperature: 40))
    inputs.addLoad(user: 30, system: 12, idle: 58)
    sampler.sampleCPU(now: 0.25)
    #expect(sampler.pass(now: 0.5) == Readout(cpu: 42, gpu: 7, ram: 30, temperature: 40))
  }

  @Test("a reading that stops arriving dashes after three seconds; the others stay live")
  func oneReadingStops() {
    let inputs = FixedInputs()
    let sampler = Sampler(inputs: inputs)
    sampler.sampleCPU(now: 0)
    inputs.addLoad(user: 10, system: 0, idle: 90)
    sampler.sampleCPU(now: 0.25)
    _ = sampler.pass(now: 0.5)
    inputs.gpu = nil
    var now = 0.5
    while now < 3.5 {
      now += 0.25
      inputs.addLoad(user: 20, system: 0, idle: 80)
      sampler.sampleCPU(now: now)
      inputs.sensors = ["PMU tdie1": 40 + now]
      let readout = sampler.pass(now: now)
      #expect(readout.gpu == (now - 0.5 <= 3 ? 0 : nil))
      #expect(readout.cpu == 20)
      #expect(readout.temperature == Rounding.wholeNumber(40 + now))
    }
  }

  @Test("a fresh reading after a dash shows again")
  func recovers() {
    let inputs = FixedInputs()
    let sampler = Sampler(inputs: inputs)
    _ = sampler.pass(now: 0)
    inputs.sensors = nil
    #expect(sampler.pass(now: 4).temperature == nil)
    inputs.sensors = ["PMU tdie1": 55]
    #expect(sampler.pass(now: 4.5).temperature == 55)
  }

  @Test("a change in an instantaneous reading shows at the very next pass")
  func nextPass() {
    let inputs = FixedInputs()
    let sampler = Sampler(inputs: inputs)
    _ = sampler.pass(now: 0)
    inputs.gpu = ["Device Utilization %": 90]
    #expect(sampler.pass(now: Sampler.passInterval).gpu == 90)
  }

  @Test("the readout refreshes well inside a second (D115)")
  func cadence() {
    // A change waits at most one pass to be read; CPU, a load over the last counter
    // interval, at most one pass plus one counter interval.
    #expect(Sampler.passInterval + Sampler.cpuInterval < 1)
  }

  @Test("a reading spanning a sleep comes out low, never huge: the clock counts the sleep")
  func acrossSleep() {
    let inputs = FixedInputs()
    inputs.interfaces = [InterfaceCounters(name: "en0", received: 0, sent: 0)]
    inputs.disks = ["disk0": ByteCounts(0, 0)]
    let sampler = Sampler(inputs: inputs)
    sampler.sampleCPU(now: 0)
    _ = sampler.pass(now: 0)
    // The Mac sleeps an hour; the wake notification has not reached the meter yet. While it
    // slept, a dark wake moved 90 MB in and 30 MB out and wrote 36 MB; the CPU counters moved
    // a little, mostly idle.
    inputs.interfaces = [
      InterfaceCounters(name: "en0", received: 90_000_000, sent: 30_000_000)
    ]
    inputs.disks = ["disk0": ByteCounts(0, 36_000_000)]
    inputs.addLoad(user: 10, system: 0, idle: 990)
    // The meter's clock counted the hour, so the first pass after it divides by the hour.
    let after = 3600.5
    sampler.sampleCPU(now: after)
    _ = sampler.pass(now: after)
    let rates = sampler.netDisk(now: after)
    #expect(rates.network == ByteRates(90_000_000 / after, 30_000_000 / after))
    #expect(rates.disk == ByteRates(0, 36_000_000 / after))
    // Low: about 25 KB/s, not the 180 MB/s the same bytes over one half-second pass would read,
    // as they would on a clock that stopped while the Mac slept.
    #expect((rates.network?.first ?? .infinity) < 26_000)
    #expect(
      CounterRates.rates(
        from: ["en0": ByteCounts(0, 0)], to: ["en0": ByteCounts(90_000_000, 0)], seconds: 0.5)
        == ByteRates(180_000_000, 0))
    #expect(sampler.legend(now: after).cpu == 10)
  }

  @Test("after the wake notification, no rate is measured across the sleep at all")
  func wakeStartsAfresh() {
    let inputs = FixedInputs()
    inputs.interfaces = [InterfaceCounters(name: "en0", received: 0, sent: 0)]
    let engine = MeterEngine(inputs: inputs)
    _ = engine.begin(now: 0)
    engine.willSleep(now: 0.1)
    inputs.interfaces = [InterfaceCounters(name: "en0", received: 90_000_000, sent: 0)]
    engine.didWake(now: 3600)
    _ = engine.tick(now: 3600.25)
    _ = engine.tick(now: 3600.5)
    // The first pass after the wake has no earlier read to measure from.
    #expect(engine.netDisk(now: 3600.5).network == nil)
    inputs.interfaces = [InterfaceCounters(name: "en0", received: 90_000_500, sent: 0)]
    _ = engine.tick(now: 3600.75)
    _ = engine.tick(now: 3601)
    #expect(engine.netDisk(now: 3601).network == ByteRates(1000, 0))
  }
}
