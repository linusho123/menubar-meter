/// The panel's current CPU, GPU and RAM, in tenths of a percent (`935` is 93.5%); nil for a
/// reading with no fresh value.
public struct LegendValues: Equatable, Sendable {
  public var cpu: Int?
  public var gpu: Int?
  public var ram: Int?

  public init(cpu: Int?, gpu: Int?, ram: Int?) {
    self.cpu = cpu
    self.gpu = gpu
    self.ram = ram
  }

  public func value(_ metric: HistoryMetric) -> Int? {
    switch metric {
    case .cpu: cpu
    case .gpu: gpu
    case .ram: ram
    }
  }
}

/// The graph's legend: each line's label and current value to one decimal place (D19, D18),
/// as in `CPU 100.0%  GPU 0.0%  RAM 93.0%`. A value with no fresh reading is a dash, never an
/// old number (D81). It shows current values only: no peak (D9).
public enum Legend {
  public static let separator = "  "

  public static func text(_ values: LegendValues) -> String {
    HistoryMetric.allCases.map { entry($0, values.value($0)) }.joined(separator: separator)
  }

  /// One entry, as in `RAM 93.0%`.
  public static func entry(_ metric: HistoryMetric, _ tenths: Int?) -> String {
    "\(metric.label) \(oneDecimal(tenths))%"
  }

  /// Tenths of a percent written to one decimal place (`935` is `93.5`), or a dash.
  public static func oneDecimal(_ tenths: Int?) -> String {
    guard let tenths, tenths >= 0 else { return ReadoutText.dash }
    return "\(tenths / 10).\(tenths % 10)"
  }
}
