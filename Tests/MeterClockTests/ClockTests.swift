import Darwin
import Testing

@testable import MeterClock

/// Whether the Mac has slept since it booted: only then do the clock that counts sleep and the one
/// that does not differ.
private let hasSleptSinceBoot: Bool = {
  var value: UInt64 = 0
  var size = MemoryLayout<UInt64>.size
  return sysctlbyname("kern.sleep_abs_time", &value, &size, nil, 0) == 0 && value > 0
}()

@Suite("the meter's clock counts the time the Mac sleeps")
struct ClockTests {
  private func nanoseconds(_ clock: clockid_t) -> Double {
    Double(clock_gettime_nsec_np(clock)) / 1_000_000_000
  }

  @Test("it reads CLOCK_MONOTONIC, which counts sleep")
  func readsMonotonic() {
    let before = nanoseconds(CLOCK_MONOTONIC)
    let now = Clock.now()
    let after = nanoseconds(CLOCK_MONOTONIC)
    #expect(now >= before - 0.05 && now <= after + 0.05)
  }

  @Test(
    "it differs from CLOCK_UPTIME_RAW, which stops while asleep, on a Mac that has slept since boot",
    .enabled(
      if: hasSleptSinceBoot,
      "this Mac has not slept since it booted (kern.sleep_abs_time is 0), so the two clocks agree")
  )
  func differsFromUptimeRaw() {
    #expect(abs(Clock.now() - nanoseconds(CLOCK_UPTIME_RAW)) > 1)
  }

  @Test("it never steps back")
  func neverStepsBack() {
    let first = Clock.now()
    let second = Clock.now()
    #expect(second >= first)
  }
}
