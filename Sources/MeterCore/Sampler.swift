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

  public private(set) var cpu: Timestamped<Int>?
  public private(set) var gpu: Timestamped<Int>?
  public private(set) var ram: Timestamped<Int>?
  public private(set) var temperature: Timestamped<Int>?

  public init(inputs: MeterInputs) {
    self.inputs = inputs
  }

  /// Reads the CPU counters and, from the previous read, the CPU load.
  public func sampleCPU(now: Double) {
    guard let ticks = inputs.cpuTicks() else { return }
    if let last = lastTicks, let load = CPULoad.busyPercent(from: last.value, to: ticks) {
      cpu = Timestamped(load, at: now)
    }
    lastTicks = Timestamped(ticks, at: now)
  }

  /// Reads memory, GPU and temperature, then composes the readout with stale values dashed.
  public func pass(now: Double) -> Readout {
    if let pages = inputs.memoryPages(),
      let percent = MemoryUsed.percent(
        pages, pageSize: inputs.pageSize, physicalMemory: inputs.physicalMemory)
    {
      ram = Timestamped(percent, at: now)
    }
    if let stats = inputs.gpuPerformanceStatistics(),
      let percent = GPUUtilization.percent(performanceStatistics: stats)
    {
      gpu = Timestamped(percent, at: now)
    }
    if let sensors = inputs.temperatureSensors(),
      let celsius = ChipTemperature.celsius(sensors: sensors)
    {
      temperature = Timestamped(celsius, at: now)
    }
    return readout(now: now)
  }

  public func readout(now: Double) -> Readout {
    Readout(
      cpu: Staleness.fresh(cpu, now: now),
      gpu: Staleness.fresh(gpu, now: now),
      ram: Staleness.fresh(ram, now: now),
      temperature: Staleness.fresh(temperature, now: now))
  }
}
