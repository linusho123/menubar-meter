import Testing

@testable import OwnCost

@Suite("The meter's own CPU, from CPU-time deltas (D73)")
struct CPUShareTests {
  /// A sample every second from `start`, the CPU time rising by `steps[i]` seconds in second i.
  private func samples(_ steps: [Double], start: Double = 0) -> [CPUTimeSample] {
    var cpu = 0.0
    var out = [CPUTimeSample(at: start, cpuSeconds: 0)]
    for (index, step) in steps.enumerated() {
      cpu += step
      out.append(CPUTimeSample(at: start + Double(index + 1) * 1000, cpuSeconds: cpu))
    }
    return out
  }

  @Test("the share over a minute is the CPU time used over the wall time times the cores")
  func meanOverAMinute() throws {
    // 0.6 s of CPU over 60 s on 10 cores: 0.1% of the whole Mac.
    let share = try #require(CPUShare.over(samples(Array(repeating: 0.01, count: 60)), cores: 10))
    #expect(abs(share.mean - 0.1) < 1e-9)
    #expect(abs(share.peak - 0.1) < 1e-9)
    #expect(share.seconds == 60)
  }

  @Test("a spike is never averaged away: the peak is the busiest second")
  func peakSeesASpike() throws {
    // Idle for 59 s and one second at 0.5 s of CPU: a mean of 0.083%, a peak of 5% on 10 cores.
    var steps = Array(repeating: 0.0, count: 60)
    steps[30] = 0.5
    let share = try #require(CPUShare.over(samples(steps), cores: 10))
    #expect(abs(share.mean - 0.5 / 600 * 100) < 1e-9)
    #expect(abs(share.peak - 5) < 1e-9)
    #expect(share.mean < 1)
    #expect(share.peak > 1)
  }

  @Test("uneven sampling: each interval is judged over its own length")
  func uneven() throws {
    let share = try #require(
      CPUShare.over(
        [
          CPUTimeSample(at: 0, cpuSeconds: 1),
          CPUTimeSample(at: 500, cpuSeconds: 1.05),
          CPUTimeSample(at: 2000, cpuSeconds: 1.08),
        ], cores: 2))
    #expect(abs(share.peak - 5) < 1e-9)
    #expect(abs(share.mean - 2) < 1e-9)
  }

  @Test("no share without two samples, time between them, or CPU time only going up")
  func noShare() {
    #expect(CPUShare.over([CPUTimeSample(at: 0, cpuSeconds: 0)], cores: 10) == nil)
    #expect(
      CPUShare.over(
        [CPUTimeSample(at: 0, cpuSeconds: 0), CPUTimeSample(at: 0, cpuSeconds: 1)], cores: 10)
        == nil)
    #expect(
      CPUShare.over(
        [CPUTimeSample(at: 0, cpuSeconds: 5), CPUTimeSample(at: 1000, cpuSeconds: 1)], cores: 10)
        == nil)
    #expect(CPUShare.over(samples([0.1]), cores: 0) == nil)
  }

  @Test(
    "ps CPU times read as seconds",
    arguments: [
      ("0:09.08", 9.08), ("12:34.56", 754.56), ("1:02:03.04", 3723.04),
      ("2-01:02:03.04", 2 * 86_400 + 3723.04), (" 0:00.00\n", 0),
    ])
  func psTime(text: String, seconds: Double) throws {
    let value = try #require(PSTime.seconds(text))
    #expect(abs(value - seconds) < 1e-9)
  }

  @Test(
    "text that is not a ps CPU time reads as nothing", arguments: ["", "9.08", "a:01.00", "1.5:01"])
  func notPSTime(text: String) {
    #expect(PSTime.seconds(text) == nil)
  }
}

@Suite("The meter's memory in Activity Monitor's units (D76)")
struct ActivityMonitorMemoryTests {
  @Test(
    "megabytes of 1,048,576 bytes, to one decimal",
    arguments: [
      (UInt64(17_842_872), "17.0 MB"), (UInt64(72_336_152), "69.0 MB"),
      (UInt64(1_048_576), "1.0 MB"),
    ])
  func text(bytes: UInt64, shown: String) {
    #expect(ActivityMonitorMemory.text(bytes: bytes) == shown)
  }

  @Test("under 50 MB means shown under 50.0 MB: the line sits at 49.95 MB")
  func lineAtFifty() {
    // 49.95 × 1,048,576 = 52,376,371.2 bytes: 52,376,371 shows 49.9 MB, 52,376,372 shows 50.0.
    #expect(ActivityMonitorMemory.text(bytes: 52_376_371) == "49.9 MB")
    #expect(ActivityMonitorMemory.isUnder(bytes: 52_376_371, megabytes: 50))
    #expect(ActivityMonitorMemory.text(bytes: 52_376_372) == "50.0 MB")
    #expect(!ActivityMonitorMemory.isUnder(bytes: 52_376_372, megabytes: 50))
    // Decimal megabytes would be the wrong unit: 50,000,000 bytes is 47.7 MB, under the line.
    #expect(ActivityMonitorMemory.isUnder(bytes: 50_000_000, megabytes: 50))
    #expect(!ActivityMonitorMemory.isUnder(bytes: 52_428_800, megabytes: 50))
  }

  @Test("the physical footprint is read from footprint's own report")
  func fromFootprint() {
    let report = """
      ======================================================================
      Meter [7715]: 64-bit    Footprint: 17842872 B (16384 bytes per page)
      ======================================================================

      Auxiliary data:
          phys_footprint: 17891328 B
          phys_footprint_peak: 43352832 B
      """
    #expect(ActivityMonitorMemory.physicalFootprint(footprintOutput: report) == 17_891_328)
    #expect(ActivityMonitorMemory.physicalFootprint(footprintOutput: "Footprint: 30 MB") == nil)
  }
}
