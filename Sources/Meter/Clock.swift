import Darwin

/// The meter's clock: seconds since an arbitrary point, counting on while the Mac sleeps, so a
/// sleep shows as the stretch of time it took (D52) and a stale reading cannot pass for fresh
/// after a wake (D81). It never steps back when the wall clock is set.
enum Clock {
  static func now() -> Double {
    Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
  }
}
