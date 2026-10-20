/// An exact share of a whole (busy ticks of all ticks, bytes used of physical memory), kept
/// unrounded so the menu bar's whole number (D46) and the panel's one decimal (D19) are each
/// rounded once, from the same exact value, never one from the other.
public struct Share: Equatable, Sendable {
  public let part: UInt64
  public let whole: UInt64

  /// Nil when `whole` is zero: there is no share of nothing. A part over the whole is held to it.
  public init?(part: UInt64, whole: UInt64) {
    guard whole > 0 else { return nil }
    self.part = min(part, whole)
    self.whole = whole
  }

  /// A whole percentage, a half rounding up, never over 100.
  public var wholePercent: Int {
    Int((part * 200 + whole) / (2 * whole))
  }

  /// Tenths of a percent (`935` is 93.5%), a half rounding up, never over 1000.
  public var tenthsOfPercent: Int {
    Int((part * 2000 + whole) / (2 * whole))
  }
}
