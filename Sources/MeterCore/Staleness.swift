/// A value with the moment it was read, in seconds on one monotonic clock.
public struct Timestamped<Value: Sendable>: Sendable {
  public var value: Value
  public var at: Double

  public init(_ value: Value, at: Double) {
    self.value = value
    self.at = at
  }
}

/// A reading older than three seconds shows as a dash (D114); exactly three is still fresh.
public enum Staleness {
  public static let limit: Double = 3

  public static func isFresh(readAt: Double, now: Double) -> Bool {
    now - readAt <= limit
  }

  public static func fresh<Value>(_ reading: Timestamped<Value>?, now: Double) -> Value? {
    guard let reading, isFresh(readAt: reading.at, now: now) else { return nil }
    return reading.value
  }
}
