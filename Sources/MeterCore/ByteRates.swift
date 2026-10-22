/// Two byte counters read together: a network interface's bytes received and sent, or a disk's
/// bytes read and written.
public struct ByteCounts: Equatable, Sendable {
  public var first: UInt64
  public var second: UInt64

  public init(_ first: UInt64, _ second: UInt64) {
    self.first = first
    self.second = second
  }
}

/// Two rates in bytes per second, from one reading: received and sent, or read and written.
public struct ByteRates: Equatable, Sendable {
  public var first: Double
  public var second: Double

  public init(_ first: Double, _ second: Double) {
    self.first = first
    self.second = second
  }
}

/// Rates from two reads of a set of counters, each counter keyed by what it counts (an
/// interface's name, a disk's registry entry). A counter that went backwards was reset (its
/// interface or disk went away and came back) and adds nothing for that interval, as does one
/// not read the time before; one no longer read adds nothing. So a reset never shows as a
/// negative rate or as the counter's whole total at once.
public enum CounterRates {
  public static func rates(
    from previous: [String: ByteCounts], to current: [String: ByteCounts], seconds: Double
  ) -> ByteRates? {
    guard seconds > 0 else { return nil }
    var first: UInt64 = 0
    var second: UInt64 = 0
    for (key, now) in current {
      guard let before = previous[key] else { continue }
      if now.first >= before.first { first += now.first - before.first }
      if now.second >= before.second { second += now.second - before.second }
    }
    return ByteRates(Double(first) / seconds, Double(second) / seconds)
  }
}

/// One network interface's link-level byte counters, as the system lists them.
public struct InterfaceCounters: Equatable, Sendable {
  public var name: String
  public var received: UInt64
  public var sent: UInt64

  public init(name: String, received: UInt64, sent: UInt64) {
    self.name = name
    self.received = received
    self.sent = sent
  }
}

/// The interfaces Activity Monitor's Network tab counts for the whole Mac: every one the system
/// lists, loopback (`lo0`) and the virtual ones (`utun`, `awdl`, `llw`, `bridge`, `anpi`, `ap`)
/// included, as measured against Activity Monitor's own totals (DESIGN, P5). Each interface is
/// counted once, by its name, whatever else it is listed with.
public enum NetworkInterfaces {
  public static func counted(_ interfaces: [InterfaceCounters]) -> [String: ByteCounts] {
    var counts: [String: ByteCounts] = [:]
    for interface in interfaces where counts[interface.name] == nil {
      counts[interface.name] = ByteCounts(interface.received, interface.sent)
    }
    return counts
  }
}

/// The panel's network and disk lines (D95, D114): `Net ↓ 112.4 MB/s ↑ 300.0 KB/s` and
/// `Disk R 210.0 MB/s W 1.2 GB/s`, a dash for the whole line when its reading is not fresh.
public enum ByteRateText {
  /// Activity Monitor's prefixes are decimal: a KB is 1000 bytes (measured, DESIGN P5).
  public static let base: Double = 1000
  public static let units = ["KB/s", "MB/s", "GB/s"]
  /// A value moves up a unit once it reads 1000 in the smaller one, as Activity Monitor's
  /// do (999.9 KB/s, then 1.0 MB/s; D117, which amends D95).
  public static let stepUp = 1000

  /// A rate in bytes per second, one decimal, in the unit its number grows into.
  public static func rate(_ bytesPerSecond: Double) -> String {
    let rate = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
    var divisor = base / 10
    for (index, unit) in units.enumerated() {
      let tenths = Rounding.wholeNumber(rate / divisor)
      if tenths < stepUp * 10 || index == units.count - 1 {
        return "\(tenths / 10).\(tenths % 10) \(unit)"
      }
      divisor *= base
    }
    return ""
  }

  public static func network(_ rates: ByteRates?) -> String {
    guard let rates else { return "Net ↓ \(ReadoutText.dash) ↑ \(ReadoutText.dash)" }
    return "Net ↓ \(rate(rates.first)) ↑ \(rate(rates.second))"
  }

  public static func disk(_ rates: ByteRates?) -> String {
    guard let rates else { return "Disk R \(ReadoutText.dash) W \(ReadoutText.dash)" }
    return "Disk R \(rate(rates.first)) W \(rate(rates.second))"
  }
}
