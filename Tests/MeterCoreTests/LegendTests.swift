import Testing

@testable import MeterCore

@Suite("The legend to one decimal (D19, D18)")
struct LegendTests {
  @Test("the legend names each line and its current value")
  func text() {
    let values = LegendValues(cpu: 1000, gpu: 0, ram: 930)
    #expect(Legend.text(values) == "CPU 100.0%  GPU 0.0%  RAM 93.0%")
  }

  @Test("a value with no fresh reading is a dash")
  func dash() {
    #expect(Legend.text(LegendValues(cpu: 75, gpu: nil, ram: 5)) == "CPU 7.5%  GPU –%  RAM 0.5%")
  }

  @Test(
    "one decimal, a half rounding up, never over 100.0",
    arguments: [
      (UInt64(1), UInt64(2000), "0.1"), (1, 2001, "0.0"), (1999, 20000, "10.0"),
      (9345, 10000, "93.5"), (93449, 100_000, "93.4"), (19989, 20000, "99.9"),
      (19999, 20000, "100.0"), (1, 1, "100.0"), (3, 2, "100.0"),
    ])
  func rounding(part: UInt64, whole: UInt64, shown: String) {
    let share = Share(part: part, whole: whole)
    #expect(Legend.oneDecimal(share?.tenthsOfPercent) == shown)
  }

  @Test("the menu bar's whole number and the legend's decimal each round the exact reading")
  func noDoubleRounding() {
    // 0.45%: one decimal is 0.5, but the whole number is 0, not 1 from rounding 0.5 again.
    let share = Share(part: 45, whole: 10000)
    #expect(share?.tenthsOfPercent == 5)
    #expect(share?.wholePercent == 0)
  }
}

/// Fixed inputs, set by each test; never the real system.
private final class SteadyInputs: MeterInputs {
  var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
  var busyPerRead: UInt64 = 25
  let physicalMemory: UInt64 = 1000 * 100
  let pageSize: UInt64 = 100

  func cpuTicks() -> CPUTicks? {
    ticks.user += busyPerRead
    ticks.idle += 100 - busyPerRead
    return ticks
  }
  func memoryPages() -> MemoryPages? {
    MemoryPages(anonymous: 935, purgeable: 0, wired: 0, compressed: 0, fileBacked: 50)
  }
  func gpuPerformanceStatistics() -> [String: Int]? { ["Device Utilization %": 4] }
  func temperatureSensors() -> [String: Double]? { ["PMU tdie1": 40] }
  func networkInterfaces(now: Double) -> [InterfaceCounters]? { nil }
  func diskCounters(now: Double) -> [String: ByteCounts]? { nil }
}

@Suite("The engine records every pass in the history")
struct EngineTests {
  @Test("one sample a pass, with the legend's values")
  func recordsPasses() {
    let engine = MeterEngine(inputs: SteadyInputs())
    _ = engine.begin(now: 0)
    var passes = 0
    for read in 1...8 where engine.tick(now: Double(read) * Sampler.cpuInterval) != nil {
      passes += 1
    }
    #expect(passes == 4)
    #expect(engine.history.samples.count == 5)
    #expect(engine.history.samples.last == HistorySample(at: 2, cpu: 250, gpu: 40, ram: 935))
    #expect(engine.legend(now: 2) == LegendValues(cpu: 250, gpu: 40, ram: 935))
  }

  @Test("sleep and wake leave a gap, and CPU after the wake is not a load over the sleep")
  func sleepAndWake() {
    let inputs = SteadyInputs()
    let engine = MeterEngine(inputs: inputs)
    _ = engine.begin(now: 0)
    for read in 1...4 { _ = engine.tick(now: Double(read) * 0.25) }
    engine.willSleep(now: 1.1)
    _ = engine.tick(now: 1.25)
    _ = engine.tick(now: 1.5)
    engine.didWake(now: 121)
    inputs.busyPerRead = 80
    _ = engine.tick(now: 121.25)
    // The first read after the wake is a new baseline, not the end of a load over the sleep.
    #expect((engine.sampler.cpu?.at ?? 0) < 121)
    let firstPass = engine.tick(now: 121.5)
    #expect(firstPass?.cpu == 80)
    #expect(engine.history.lines(.ram, now: 121.5).count == 2)
    #expect(engine.history.samples.allSatisfy { $0.at <= 1 || $0.at >= 121 })
  }
}
