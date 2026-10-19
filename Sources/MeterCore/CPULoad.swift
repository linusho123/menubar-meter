/// Cumulative CPU tick counters for the whole Mac, all cores together, as the kernel keeps them.
public struct CPUTicks: Equatable, Sendable {
  public var user: UInt64
  public var system: UInt64
  public var idle: UInt64
  public var nice: UInt64

  public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
    self.user = user
    self.system = system
    self.idle = idle
    self.nice = nice
  }
}

/// Whole-Mac CPU load the way Activity Monitor's CPU tab counts it: User plus System (D48).
/// Activity Monitor's User includes niced user time.
public enum CPULoad {
  /// The busy share between two counter reads, as a whole percentage.
  /// Nil when no time passed or a counter went backwards (a reset): no honest number exists.
  public static func busyPercent(from earlier: CPUTicks, to later: CPUTicks) -> Int? {
    guard later.user >= earlier.user, later.system >= earlier.system,
      later.idle >= earlier.idle, later.nice >= earlier.nice
    else { return nil }
    let user = (later.user - earlier.user) + (later.nice - earlier.nice)
    let system = later.system - earlier.system
    let idle = later.idle - earlier.idle
    return Rounding.wholePercent(part: user + system, whole: user + system + idle)
  }
}
