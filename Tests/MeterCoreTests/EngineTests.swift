import Testing

@testable import MeterCore

private final class SteadyInputs: MeterInputs {
  var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
  let physicalMemory: UInt64 = 1000 * 100
  let pageSize: UInt64 = 100

  func cpuTicks() -> CPUTicks? {
    ticks.user += 50
    ticks.idle += 50
    return ticks
  }
  func memoryPages() -> MemoryPages? {
    MemoryPages(anonymous: 500, purgeable: 0, wired: 0, compressed: 0, fileBacked: 0)
  }
  func gpuPerformanceStatistics() -> [String: Int]? { ["Device Utilization %": 10] }
  func temperatureSensors() -> [String: Double]? { ["PMU tdie1": 40] }
}

@Suite("The engine's own time")
struct EngineTimeTests {
  @Test("after a long sleep the panel's 'now' is the wake time, so old readings show as dashes")
  func staleAfterWake() {
    let engine = MeterEngine(inputs: SteadyInputs())
    _ = engine.begin(now: 1000)
    var now = 1000.0
    while now < 1010 {
      now += Sampler.cpuInterval
      _ = engine.tick(now: now)
    }
    #expect(engine.legend(now: engine.now).ram == 500)
    engine.willSleep(now: 1011)
    engine.didWake(now: 2000)
    #expect(engine.now == 2000)
    #expect(engine.legend(now: engine.now) == LegendValues(cpu: nil, gpu: nil, ram: nil))
  }
}
