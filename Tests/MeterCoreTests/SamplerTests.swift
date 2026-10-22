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
  func networkInterfaces(now: Double) -> [InterfaceCounters]? { nil }
  func diskCounters(now: Double) -> [String: ByteCounts]? { nil }

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
}
