import Testing

@testable import MeterCore

@Suite("Rounding to whole numbers (D46)")
struct RoundingTests {
  @Test(
    "half rounds up, the rest to the nearest, never over 100",
    arguments: [
      (0.0, 0), (0.4, 0), (0.5, 1), (7.5, 8), (42.49, 42), (99.4, 99), (99.5, 100),
      (99.6, 100), (100.0, 100), (100.4, 100), (150.0, 100), (-3.0, 0),
    ])
  func wholePercentOfDouble(value: Double, shown: Int) {
    #expect(Rounding.wholePercent(value) == shown)
  }

  @Test(
    "exact shares round half up",
    arguments: [
      (UInt64(0), UInt64(1000), 0), (4, 1000, 0), (5, 1000, 1), (75, 1000, 8), (74, 1000, 7),
      (995, 1000, 100), (994, 1000, 99), (996, 1000, 100), (1000, 1000, 100),
    ])
  func wholePercentOfShare(part: UInt64, whole: UInt64, shown: Int) {
    #expect(Rounding.wholePercent(part: part, whole: whole) == shown)
  }

  @Test("a share is never over 100, and there is none of nothing")
  func shareBounds() {
    #expect(Rounding.wholePercent(part: 1200, whole: 1000) == 100)
    #expect(Rounding.wholePercent(part: 0, whole: 0) == nil)
  }

  @Test("whole degrees round half up", arguments: [(61.4, 61), (61.5, 62), (97.99, 98)])
  func wholeNumber(value: Double, shown: Int) {
    #expect(Rounding.wholeNumber(value) == shown)
  }
}
