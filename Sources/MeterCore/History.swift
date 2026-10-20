/// The three readings the five-minute graph draws, in the legend's order.
public enum HistoryMetric: CaseIterable, Sendable {
  case cpu
  case gpu
  case ram

  public var label: String {
    switch self {
    case .cpu: "CPU"
    case .gpu: "GPU"
    case .ram: "RAM"
    }
  }
}

/// One pass's readings, in tenths of a percent, at a time on a clock that keeps running while
/// the Mac sleeps. A nil reading had no fresh value and draws no point.
public struct HistorySample: Equatable, Sendable {
  public var at: Double
  public var cpu: Int?
  public var gpu: Int?
  public var ram: Int?

  public init(at: Double, cpu: Int?, gpu: Int?, ram: Int?) {
    self.at = at
    self.cpu = cpu
    self.gpu = gpu
    self.ram = ram
  }

  public init(at: Double, _ values: LegendValues) {
    self.init(at: at, cpu: values.cpu, gpu: values.gpu, ram: values.ram)
  }

  public func value(_ metric: HistoryMetric) -> Int? {
    switch metric {
    case .cpu: cpu
    case .gpu: gpu
    case .ram: ram
    }
  }
}

/// A point on the graph: `x` from 0 (five minutes ago, the left edge) to 1 (now, the right
/// edge), `y` from 0 (0%) to 1 (100%).
public struct GraphPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// The last five minutes of CPU, GPU and RAM, held in memory only (D53, D113). Nothing older
/// than five minutes is kept. Where no samples exist (before launch, while the Mac slept) the
/// history holds nothing, and a sleep is a gap no line is ever drawn across (D52).
public struct History: Sendable {
  /// The window, in seconds: the graph runs from five minutes ago to now (D50).
  public static let window: Double = 300

  public enum Entry: Equatable, Sendable {
    case sample(HistorySample)
    /// A break: the lines stop before it and resume after it.
    case gap
  }

  public private(set) var entries: [Entry] = []
  /// Between the Mac's going to sleep and its waking, nothing is recorded.
  public private(set) var asleep = false

  public init() {}

  public var samples: [HistorySample] {
    entries.compactMap {
      if case .sample(let sample) = $0 { return sample }
      return nil
    }
  }

  private var newest: Double? { samples.last?.at }

  /// Adds one pass's sample and drops whatever is now older than the window. A sample while
  /// asleep, or not later than the newest one held, is not recorded.
  public mutating func record(_ sample: HistorySample) {
    guard !asleep else { return }
    if let newest, sample.at <= newest { return }
    entries.append(.sample(sample))
    trim(now: sample.at)
  }

  /// The Mac is going to sleep: the lines stop here.
  public mutating func sleep(at now: Double) {
    asleep = true
    breakLines()
    trim(now: now)
  }

  /// The Mac woke: the lines resume from the next sample, never joined to the ones before the
  /// sleep. If the clock reads earlier than samples already held, those cannot be placed on
  /// the graph and are dropped; the rest of the history stays.
  public mutating func wake(at now: Double) {
    asleep = false
    entries.removeAll {
      if case .sample(let sample) = $0 { return sample.at > now }
      return false
    }
    breakLines()
    trim(now: now)
  }

  /// Drops every sample more than five minutes old: a sample exactly five minutes old stays.
  public mutating func trim(now: Double) {
    entries.removeAll {
      if case .sample(let sample) = $0 { return now - sample.at > Self.window }
      return false
    }
    while entries.first == .gap { entries.removeFirst() }
    var tidy: [Entry] = []
    for entry in entries where !(entry == .gap && tidy.last == .gap) {
      tidy.append(entry)
    }
    entries = tidy
  }

  private mutating func breakLines() {
    if let last = entries.last, last != .gap { entries.append(.gap) }
  }

  /// One metric's lines at `now`, each a run of consecutive points to be joined. A run ends at
  /// a gap and at a sample with no reading for the metric. The axis is fixed: x spans exactly
  /// the five-minute window and y exactly 0% to 100%, whatever the data.
  public func lines(_ metric: HistoryMetric, now: Double) -> [[GraphPoint]] {
    var runs: [[GraphPoint]] = []
    var run: [GraphPoint] = []
    func endRun() {
      if !run.isEmpty { runs.append(run) }
      run = []
    }
    for entry in entries {
      guard case .sample(let sample) = entry, let tenths = sample.value(metric) else {
        endRun()
        continue
      }
      let age = now - sample.at
      guard age >= 0, age <= Self.window else {
        endRun()
        continue
      }
      run.append(Self.position(age: age, tenths: tenths))
    }
    endRun()
    return runs
  }

  /// Where a reading of `tenths` (of a percent) taken `age` seconds ago sits on the graph.
  public static func position(age: Double, tenths: Int) -> GraphPoint {
    let percent = min(100, max(0, Double(tenths) / 10))
    return GraphPoint(x: 1 - age / window, y: percent / 100)
  }
}
