import Testing

@testable import MeterCore

@Suite("Network and disk speeds as the panel writes them (D95)")
struct ByteRateTextTests {
  @Test(
    "One decimal, decimal prefixes as Activity Monitor's, the unit growing with the number",
    arguments: [
      (0.0, "0.0 KB/s"),
      (49.0, "0.0 KB/s"),
      (50.0, "0.1 KB/s"),
      (999.0, "1.0 KB/s"),
      (1000.0, "1.0 KB/s"),
      // Below a few KB/s decimal and binary prefixes round alike; the MB and GB steps below
      // and the decimal-prefix test tell them apart.
      (1500.0, "1.5 KB/s"),
      (300_000.0, "300.0 KB/s"),
      (500_000.0, "500.0 KB/s"),
      (999_949.0, "999.9 KB/s"),
      (999_950.0, "1.0 MB/s"),
      (1_000_000.0, "1.0 MB/s"),
      (1_048_576.0, "1.0 MB/s"),
      (112_400_000.0, "112.4 MB/s"),
      (210_000_000.0, "210.0 MB/s"),
      (999_949_999.0, "999.9 MB/s"),
      (999_950_000.0, "1.0 GB/s"),
      (999_999_999.0, "1.0 GB/s"),
      (1_200_000_000.0, "1.2 GB/s"),
      (1_073_741_824.0, "1.1 GB/s"),
      (5_000_000_000_000.0, "5000.0 GB/s"),
    ])
  func rate(bytes: Double, text: String) {
    #expect(ByteRateText.rate(bytes) == text)
  }

  @Test("Decimal, not binary: 112.4 million bytes a second is 112.4 MB/s, not 107.2")
  func decimalPrefixes() {
    #expect(ByteRateText.rate(112_400_000) == "112.4 MB/s")
    #expect(ByteRateText.rate(117_859_942) == "117.9 MB/s")
    #expect(ByteRateText.rate(1_288_490_189) == "1.3 GB/s")
  }

  @Test("Bytes, not bits: 1,000,000 bytes a second is 1.0 MB/s, never 8.0")
  func bytesNotBits() {
    #expect(ByteRateText.rate(1_000_000) == "1.0 MB/s")
  }

  @Test("No negative or broken rate is shown")
  func clamped() {
    #expect(ByteRateText.rate(-5) == "0.0 KB/s")
    #expect(ByteRateText.rate(.nan) == "0.0 KB/s")
  }

  @Test("The lines, and a whole-line dash when the reading is not fresh (D114)")
  func lines() {
    #expect(
      ByteRateText.network(ByteRates(112_400_000, 300_000)) == "Net ↓ 112.4 MB/s ↑ 300.0 KB/s")
    #expect(
      ByteRateText.disk(ByteRates(210_000_000, 1_200_000_000)) == "Disk R 210.0 MB/s W 1.2 GB/s")
    #expect(ByteRateText.network(ByteRates(0, 0)) == "Net ↓ 0.0 KB/s ↑ 0.0 KB/s")
    #expect(ByteRateText.network(nil) == "Net ↓ – ↑ –")
    #expect(ByteRateText.disk(nil) == "Disk R – W –")
  }
}

@Suite("Rates from counter deltas")
struct CounterRatesTests {
  @Test("The rate is the bytes counted over the seconds between the reads, summed")
  func deltas() {
    let before = ["en0": ByteCounts(1000, 500), "lo0": ByteCounts(0, 0)]
    let after = ["en0": ByteCounts(3000, 1500), "lo0": ByteCounts(1000, 1000)]
    #expect(
      CounterRates.rates(from: before, to: after, seconds: 0.5) == ByteRates(6000, 4000))
  }

  @Test("A reset counter adds nothing for that interval, never a negative rate or its total")
  func reset() {
    let before = ["en0": ByteCounts(5_000_000, 5_000_000), "utun3": ByteCounts(900, 800)]
    let after = ["en0": ByteCounts(5_001_000, 5_000_500), "utun3": ByteCounts(10, 4)]
    #expect(
      CounterRates.rates(from: before, to: after, seconds: 1) == ByteRates(1000, 500))
    // Only one half reset: the other half still counts.
    let half = ["en0": ByteCounts(5_002_000, 3)]
    #expect(
      CounterRates.rates(from: after, to: half, seconds: 1) == ByteRates(1000, 0))
  }

  @Test("A counter new since the last read, or gone from this one, adds nothing")
  func comingAndGoing() {
    let before = ["en0": ByteCounts(100, 100), "utun9": ByteCounts(7_000_000, 7_000_000)]
    let after = ["en0": ByteCounts(300, 200), "bridge0": ByteCounts(9_000_000, 9_000_000)]
    #expect(CounterRates.rates(from: before, to: after, seconds: 1) == ByteRates(200, 100))
  }

  @Test("No time between the reads is no rate")
  func noTime() {
    #expect(CounterRates.rates(from: [:], to: [:], seconds: 0) == nil)
  }
}

@Suite("The interfaces counted, as Activity Monitor counts them")
struct NetworkInterfacesTests {
  @Test("Loopback and the virtual interfaces are counted, as Activity Monitor counts them")
  func everyInterface() {
    let names = ["lo0", "en0", "awdl0", "llw0", "utun0", "utun4", "bridge0", "anpi0", "ap1"]
    let listed = names.map { InterfaceCounters(name: $0, received: 10, sent: 1) }
    let counted = NetworkInterfaces.counted(listed)
    #expect(Set(counted.keys) == Set(names))
    #expect(counted["lo0"] == ByteCounts(10, 1))
  }

  @Test("An interface listed twice is counted once")
  func once() {
    let listed = [
      InterfaceCounters(name: "en0", received: 10, sent: 1),
      InterfaceCounters(name: "en0", received: 10, sent: 1),
    ]
    #expect(NetworkInterfaces.counted(listed) == ["en0": ByteCounts(10, 1)])
  }
}

/// Fixed network and disk counters, set by each test; never the real system.
private final class CounterInputs: MeterInputs {
  var interfaces: [InterfaceCounters]? = []
  var disks: [String: ByteCounts]? = [:]
  let physicalMemory: UInt64 = 1000
  let pageSize: UInt64 = 100

  func cpuTicks() -> CPUTicks? { nil }
  func memoryPages() -> MemoryPages? { nil }
  func gpuPerformanceStatistics() -> [String: Int]? { nil }
  func temperatureSensors() -> [String: Double]? { nil }
  func networkInterfaces(now: Double) -> [InterfaceCounters]? { interfaces }
  func diskCounters(now: Double) -> [String: ByteCounts]? { disks }
}

@Suite("The sampler's network and disk rates")
struct SamplerNetDiskTests {
  @Test("Rates need two reads; loopback counts; each line goes stale as a whole after 3 s")
  func ratesAndStaleness() {
    let inputs = CounterInputs()
    let sampler = Sampler(inputs: inputs)
    inputs.interfaces = [
      InterfaceCounters(name: "en0", received: 0, sent: 0),
      InterfaceCounters(name: "lo0", received: 0, sent: 0),
    ]
    inputs.disks = ["1": ByteCounts(0, 0)]
    _ = sampler.pass(now: 10)
    #expect(sampler.netDisk(now: 10) == NetDiskValues(network: nil, disk: nil))
    inputs.interfaces = [
      InterfaceCounters(name: "en0", received: 50_000, sent: 1000),
      InterfaceCounters(name: "lo0", received: 6_000, sent: 6_000),
    ]
    inputs.disks = ["1": ByteCounts(105_000_000, 600_000_000)]
    _ = sampler.pass(now: 10.5)
    #expect(
      sampler.netDisk(now: 10.5)
        == NetDiskValues(
          network: ByteRates(112_000, 14_000), disk: ByteRates(210_000_000, 1_200_000_000)))
    // The network reading stops arriving; disk goes on.
    inputs.interfaces = nil
    inputs.disks = ["1": ByteCounts(105_000_000, 600_000_000)]
    _ = sampler.pass(now: 13.5)
    #expect(sampler.netDisk(now: 13.5).network == ByteRates(112_000, 14_000))
    _ = sampler.pass(now: 13.6)
    #expect(sampler.netDisk(now: 13.6).network == nil)
    #expect(sampler.netDisk(now: 13.6).disk == ByteRates(0, 0))
  }

  @Test("After a missed read, the next rate is measured afresh, never across the gap")
  func afterAGap() {
    let inputs = CounterInputs()
    let sampler = Sampler(inputs: inputs)
    inputs.interfaces = [InterfaceCounters(name: "en0", received: 0, sent: 0)]
    _ = sampler.pass(now: 0)
    inputs.interfaces = nil
    _ = sampler.pass(now: 5)
    inputs.interfaces = [InterfaceCounters(name: "en0", received: 9_000_000, sent: 0)]
    _ = sampler.pass(now: 10)
    #expect(sampler.netDisk(now: 10).network == nil)
    inputs.interfaces = [InterfaceCounters(name: "en0", received: 9_000_500, sent: 0)]
    _ = sampler.pass(now: 10.5)
    #expect(sampler.netDisk(now: 10.5).network == ByteRates(1000, 0))
  }

  @Test("After the Mac wakes, the rates are measured afresh, never over the sleep")
  func afterWake() {
    let inputs = CounterInputs()
    let sampler = Sampler(inputs: inputs)
    inputs.disks = ["1": ByteCounts(0, 0)]
    _ = sampler.pass(now: 0)
    sampler.resetCPUBaseline()
    inputs.disks = ["1": ByteCounts(1_000, 0)]
    _ = sampler.pass(now: 0.5)
    #expect(sampler.netDisk(now: 0.5).disk == nil)
  }
}
