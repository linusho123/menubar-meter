/// macOS's own overall GPU utilization: the "Device Utilization %" figure the GPU's
/// accelerator reports in its performance statistics (D49).
public enum GPUUtilization {
  public static let statisticKey = "Device Utilization %"

  /// The whole percentage, or nil when the figure is missing or outside 0...100:
  /// a lost reading is a dash, never a wrong number (D81).
  public static func percent(performanceStatistics: [String: Int]) -> Int? {
    guard let value = performanceStatistics[statisticKey], (0...100).contains(value) else {
      return nil
    }
    return value
  }
}
