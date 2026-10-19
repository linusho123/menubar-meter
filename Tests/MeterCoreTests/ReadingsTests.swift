import Testing

@testable import MeterCore

@Suite("CPU as Activity Monitor counts it (D48)")
struct CPULoadTests {
  private let start = CPUTicks(user: 1000, system: 500, idle: 8000, nice: 10)

  @Test("User plus System over the ticks between two reads")
  func userPlusSystem() {
    let later = CPUTicks(user: 1000 + 305, system: 500 + 120, idle: 8000 + 575, nice: 10)
    #expect(CPULoad.busyPercent(from: start, to: later) == 43)
  }

  @Test("System time counts: the load is not User alone")
  func systemCounts() {
    let later = CPUTicks(user: 1000, system: 500 + 500, idle: 8000 + 500, nice: 10)
    #expect(CPULoad.busyPercent(from: start, to: later) == 50)
  }

  @Test("niced user time counts as User")
  func niceCounts() {
    let later = CPUTicks(user: 1000 + 100, system: 500, idle: 8000 + 800, nice: 10 + 100)
    #expect(CPULoad.busyPercent(from: start, to: later) == 20)
  }

  @Test("no time passed, or a counter went back: no number")
  func noHonestNumber() {
    #expect(CPULoad.busyPercent(from: start, to: start) == nil)
    let reset = CPUTicks(user: 5, system: 600, idle: 9000, nice: 10)
    #expect(CPULoad.busyPercent(from: start, to: reset) == nil)
  }
}

@Suite("Memory Used as Activity Monitor counts it (D47)")
struct MemoryUsedTests {
  private let page: UInt64 = 16384
  private let mac: UInt64 = 32 * 1 << 30

  private func pages(usedGB: Double, cacheGB: Double) -> MemoryPages {
    let used = UInt64((usedGB * Double(1 << 30) / Double(page)).rounded())
    let cache = UInt64((cacheGB * Double(1 << 30) / Double(page)).rounded())
    let wired = used / 4
    let compressed = used / 5
    let app = used - wired - compressed
    let purgeable = cache / 10
    return MemoryPages(
      anonymous: app + purgeable, purgeable: purgeable, wired: wired, compressed: compressed,
      fileBacked: cache - purgeable)
  }

  @Test(
    "Memory Used over 32 GB, cache left out",
    arguments: [(18.0, 56), (0.5, 2), (31.9, 100), (16.0, 50)])
  func percent(usedGB: Double, shown: Int) {
    let counts = pages(usedGB: usedGB, cacheGB: 8)
    #expect(MemoryUsed.percent(counts, pageSize: page, physicalMemory: mac) == shown)
  }

  @Test("app memory, wired and compressed add up; purgeable and file-backed do not")
  func components() {
    let counts = MemoryPages(
      anonymous: 1000, purgeable: 100, wired: 200, compressed: 300, fileBacked: 5000)
    #expect(MemoryUsed.bytes(counts, pageSize: 10) == (900 + 200 + 300) * 10)
  }
}

@Suite("GPU is macOS's own reading (D49)")
struct GPUUtilizationTests {
  @Test("the accelerator's Device Utilization, not the renderer or tiler")
  func deviceUtilization() {
    let stats = [
      "Device Utilization %": 4, "Renderer Utilization %": 41, "Tiler Utilization %": 65,
    ]
    #expect(GPUUtilization.percent(performanceStatistics: stats) == 4)
  }

  @Test("a missing or impossible figure is no reading (D81)")
  func lost() {
    #expect(GPUUtilization.percent(performanceStatistics: ["Renderer Utilization %": 4]) == nil)
    #expect(GPUUtilization.percent(performanceStatistics: ["Device Utilization %": 101]) == nil)
    #expect(GPUUtilization.percent(performanceStatistics: ["Device Utilization %": -1]) == nil)
  }
}

@Suite("Chip temperature (D87)")
struct ChipTemperatureTests {
  @Test("the hottest die sensor, other sensors ignored")
  func hottestDie() {
    let sensors = [
      "PMU tdie1": 44.7, "PMU tdie2": 45.0, "PMU2 tdie9": 43.8, "PMU tdev1": -22.1,
      "PMU tcal": 51.8, "gas gauge battery": 29.3, "NAND CH0 temp": 60,
    ]
    #expect(ChipTemperature.celsius(sensors: sensors) == 45)
  }

  @Test("no believable die sensor is no reading (D81)")
  func lost() {
    #expect(ChipTemperature.celsius(sensors: ["gas gauge battery": 29.3]) == nil)
    #expect(ChipTemperature.celsius(sensors: ["PMU tdie1": -40, "PMU tdie2": 400]) == nil)
  }
}

@Suite("Staleness (D114)")
struct StalenessTests {
  @Test("exactly three seconds old is still fresh")
  func exactlyThree() {
    #expect(Staleness.isFresh(readAt: 10, now: 13))
    #expect(Staleness.fresh(Timestamped(42, at: 10), now: 13) == 42)
  }

  @Test("older than three seconds is a dash")
  func olderThanThree() {
    #expect(!Staleness.isFresh(readAt: 10, now: 13.001))
    #expect(Staleness.fresh(Timestamped(42, at: 10), now: 13.001) == nil)
  }

  @Test("no reading at all is a dash")
  func none() {
    #expect(Staleness.fresh(Timestamped<Int>?.none, now: 0) == nil)
  }
}
