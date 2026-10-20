/// The meter's one sampling loop, shared by the menu bar and the panel: the CPU counters read
/// every quarter second, a full pass every half second (D115), and each pass recorded in the
/// five-minute history. Time is given by the caller on a clock that keeps running while the
/// Mac sleeps.
public final class MeterEngine {
  public let sampler: Sampler
  public private(set) var history = History()
  private var cpuReads = 0
  /// The latest time the meter's clock gave the engine, in `begin`, `tick`, `willSleep` or
  /// `didWake`: the panel's "now" when it opens between passes.
  public private(set) var now: Double = 0

  public static let readsPerPass = Int((Sampler.passInterval / Sampler.cpuInterval).rounded())

  public init(inputs: MeterInputs) {
    sampler = Sampler(inputs: inputs)
  }

  /// The first reads: the CPU counters and a full pass.
  public func begin(now: Double) -> Readout {
    self.now = now
    sampler.sampleCPU(now: now)
    return pass(now: now)
  }

  /// One CPU counter read and, every `readsPerPass` reads, a full pass. Returns the readout
  /// when a pass ran.
  public func tick(now: Double) -> Readout? {
    self.now = now
    sampler.sampleCPU(now: now)
    cpuReads += 1
    guard cpuReads % Self.readsPerPass == 0 else { return nil }
    return pass(now: now)
  }

  private func pass(now: Double) -> Readout {
    let readout = sampler.pass(now: now)
    history.record(HistorySample(at: now, sampler.legend(now: now)))
    return readout
  }

  /// The panel's legend values right now.
  public func legend(now: Double) -> LegendValues {
    sampler.legend(now: now)
  }

  /// The Mac is going to sleep: the history's lines stop here.
  public func willSleep(now: Double) {
    self.now = now
    history.sleep(at: now)
  }

  /// The Mac woke: the lines resume, never joined across the sleep, and the next CPU load is
  /// measured afresh rather than over the sleep.
  public func didWake(now: Double) {
    self.now = now
    history.wake(at: now)
    sampler.resetCPUBaseline()
  }
}
