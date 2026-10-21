/// Where the sampler's numbers come from: the real system, or (test builds only) the test
/// reading source. Every read may fail; a failed read is no fresh reading.
public protocol MeterInputs: AnyObject {
  func cpuTicks() -> CPUTicks?
  func memoryPages() -> MemoryPages?
  func gpuPerformanceStatistics() -> [String: Int]?
  func temperatureSensors() -> [String: Double]?
  /// Physical memory in bytes (`hw.memsize`).
  var physicalMemory: UInt64 { get }
  /// The VM page size in bytes.
  var pageSize: UInt64 { get }
  /// Every network interface's link-level byte counters, read at `now` on the meter's clock.
  func networkInterfaces(now: Double) -> [InterfaceCounters]?
  /// Every disk's bytes read and written so far, keyed by the disk, read at `now`.
  func diskCounters(now: Double) -> [String: ByteCounts]?
}

/// One sampling pass at a time. CPU is a load over the time between two counter reads, so
/// the sampler reads the CPU counters more often than it composes the readout; every other
/// reading is taken at the pass itself. Each reading keeps its own timestamp.
public final class Sampler {
  /// The readout is composed this often, so a change shows within a second (D115).
  public static let passInterval: Double = 0.5
  /// The CPU counters are read this often; CPU load covers the last such interval.
  public static let cpuInterval: Double = 0.25

  private let inputs: MeterInputs
  private var lastTicks: Timestamped<CPUTicks>?

  // CPU, GPU and RAM are kept as exact shares: the menu bar rounds them to whole numbers,
  // the panel to one decimal, each from the same exact reading.
  public private(set) var cpu: Timestamped<Share>?
  public private(set) var gpu: Timestamped<Share>?
  public private(set) var ram: Timestamped<Share>?
  public private(set) var temperature: Timestamped<Int>?
  // Network and disk are rates over the time since the last pass, each from one reading of
  // its counters, so each line is fresh or stale as a whole (D114).
  public private(set) var network: Timestamped<ByteRates>?
  public private(set) var disk: Timestamped<ByteRates>?
  private var lastNetwork: Timestamped<[String: ByteCounts]>?
  private var lastDisk: Timestamped<[String: ByteCounts]>?

  public init(inputs: MeterInputs) {
    self.inputs = inputs
  }

  /// Reads the CPU counters and, from the previous read, the CPU load.
  public func sampleCPU(now: Double) {
    guard let ticks = inputs.cpuTicks() else { return }
    if let last = lastTicks, let load = CPULoad.busyShare(from: last.value, to: ticks) {
      cpu = Timestamped(load, at: now)
    }
    lastTicks = Timestamped(ticks, at: now)
  }

  /// Reads memory, GPU, temperature, network and disk, then composes the readout with stale values dashed.
  public func pass(now: Double) -> Readout {
    if let pages = inputs.memoryPages(),
      let share = MemoryUsed.share(
        pages, pageSize: inputs.pageSize, physicalMemory: inputs.physicalMemory)
    {
      ram = Timestamped(share, at: now)
    }
    if let stats = inputs.gpuPerformanceStatistics(),
      let share = GPUUtilization.share(performanceStatistics: stats)
    {
      gpu = Timestamped(share, at: now)
    }
    if let sensors = inputs.temperatureSensors(),
      let celsius = ChipTemperature.celsius(sensors: sensors)
    {
      temperature = Timestamped(celsius, at: now)
    }
    let interfaces = inputs.networkInterfaces(now: now).map(NetworkInterfaces.counted)
    Self.measure(interfaces, now: now, last: &lastNetwork, rates: &network)
    Self.measure(inputs.diskCounters(now: now), now: now, last: &lastDisk, rates: &disk)
    return readout(now: now)
  }

  public func readout(now: Double) -> Readout {
    Readout(
      cpu: Staleness.fresh(cpu, now: now)?.wholePercent,
      gpu: Staleness.fresh(gpu, now: now)?.wholePercent,
      ram: Staleness.fresh(ram, now: now)?.wholePercent,
      temperature: Staleness.fresh(temperature, now: now))
  }

  /// The panel's current values: CPU, GPU and RAM in tenths of a percent, nil when stale.
  public func legend(now: Double) -> LegendValues {
    LegendValues(
      cpu: Staleness.fresh(cpu, now: now)?.tenthsOfPercent,
      gpu: Staleness.fresh(gpu, now: now)?.tenthsOfPercent,
      ram: Staleness.fresh(ram, now: now)?.tenthsOfPercent)
  }

  /// The panel's network and disk rates, nil when stale.
  public func netDisk(now: Double) -> NetDiskValues {
    NetDiskValues(
      network: Staleness.fresh(network, now: now), disk: Staleness.fresh(disk, now: now))
  }

  /// A rate from this read of the counters and the last; a failed read leaves no baseline, so
  /// the rate after it is measured from two fresh reads, never across the gap.
  private static func measure(
    _ counts: [String: ByteCounts]?, now: Double, last: inout Timestamped<[String: ByteCounts]>?,
    rates: inout Timestamped<ByteRates>?
  ) {
    guard let counts else {
      last = nil
      return
    }
    if let last,
      let measured = CounterRates.rates(from: last.value, to: counts, seconds: now - last.at)
    {
      rates = Timestamped(measured, at: now)
    }
    last = Timestamped(counts, at: now)
  }

  /// Forgets the last CPU, network and disk counter reads, so the next load and rates are
  /// measured from fresh pairs of reads (after the Mac wakes: a load spanning the sleep is no
  /// reading of now).
  public func resetCPUBaseline() {
    lastTicks = nil
    lastNetwork = nil
    lastDisk = nil
  }
}

/// The panel's network and disk rates; nil for a reading with no fresh value.
public struct NetDiskValues: Equatable, Sendable {
  public var network: ByteRates?
  public var disk: ByteRates?

  public init(network: ByteRates?, disk: ByteRates?) {
    self.network = network
    self.disk = disk
  }
}
