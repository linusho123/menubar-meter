/// The menu bar shows whole numbers, rounded to the nearest with a half rounding up (D46, D18).
public enum Rounding {
  /// `part / whole` as a whole percentage, exact for integer inputs, never over 100.
  /// Returns nil when `whole` is zero: there is no share to show.
  public static func wholePercent(part: UInt64, whole: UInt64) -> Int? {
    guard whole > 0 else { return nil }
    let clampedPart = min(part, whole)
    // round(part * 100 / whole) with a half rounding up, in integers.
    let rounded = (clampedPart * 200 + whole) / (2 * whole)
    return Int(min(rounded, 100))
  }

  /// A percentage given as a fraction-bearing number, rounded half up and held to 0...100.
  public static func wholePercent(_ value: Double) -> Int {
    min(100, max(0, wholeNumber(value)))
  }

  /// The nearest whole number, a half rounding up.
  public static func wholeNumber(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
  }
}
