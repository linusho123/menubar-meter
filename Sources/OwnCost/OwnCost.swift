import Foundation

/// The harness's arithmetic for the meter's own cost (D73, D76), measured from outside the meter:
/// CPU time as `ps` prints it, and memory as `footprint` prints it, turned into what the contract
/// pins. Never part of the meter.

/// A process's CPU time read at one moment on the wall clock.
public struct CPUTimeSample: Equatable, Sendable {
  /// Wall-clock milliseconds.
  public var at: Double
  /// The process's CPU time so far, in seconds (user plus system, as `ps` adds them).
  public var cpuSeconds: Double

  public init(at: Double, cpuSeconds: Double) {
    self.at = at
    self.cpuSeconds = cpuSeconds
  }
}

/// A process's CPU use over a stretch of samples, as a share of the whole Mac in percent: the
/// mean over the whole stretch, and the peak over any one interval between two samples, so a
/// spike is never averaged away.
public struct CPUShare: Equatable, Sendable {
  public var mean: Double
  public var peak: Double
  /// The wall-clock seconds the samples span.
  public var seconds: Double

  /// From samples in time order over `cores` cores. Nil with fewer than two samples, a stretch
  /// with no time in it, a clock running backwards, or CPU time going down (another process).
  public static func over(_ samples: [CPUTimeSample], cores: Int) -> CPUShare? {
    guard samples.count >= 2, cores > 0, let first = samples.first, let last = samples.last
    else { return nil }
    var peak = 0.0
    for (a, b) in zip(samples, samples.dropFirst()) {
      guard b.at > a.at, b.cpuSeconds >= a.cpuSeconds else { return nil }
      peak = max(peak, share(cpu: b.cpuSeconds - a.cpuSeconds, wallMs: b.at - a.at, cores: cores))
    }
    let mean = share(
      cpu: last.cpuSeconds - first.cpuSeconds, wallMs: last.at - first.at, cores: cores)
    return CPUShare(mean: mean, peak: peak, seconds: (last.at - first.at) / 1000)
  }

  private static func share(cpu: Double, wallMs: Double, cores: Int) -> Double {
    cpu / (wallMs / 1000 * Double(cores)) * 100
  }
}

/// `ps -o time=` text ("0:09.08", "12:34.56", "1:02:03.04", "2-01:02:03.04") in seconds; nil
/// when it is not a CPU time.
public enum PSTime {
  public static func seconds(_ text: String) -> Double? {
    var rest = Substring(text.trimmingCharacters(in: [" ", "\n", "\t"]))
    var days = 0.0
    if let dash = rest.firstIndex(of: "-") {
      guard let d = Double(rest[..<dash]), d >= 0 else { return nil }
      days = d
      rest = rest[rest.index(after: dash)...]
    }
    let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
    guard (2...3).contains(parts.count) else { return nil }
    var total = 0.0
    for (index, part) in parts.enumerated() {
      guard !part.isEmpty, part.allSatisfy({ $0.isNumber || $0 == "." }),
        let value = Double(part)
      else { return nil }
      // Only the seconds may carry a fraction.
      if index < parts.count - 1, part.contains(".") { return nil }
      total = total * 60 + value
    }
    return days * 86_400 + total
  }
}

/// Memory as Activity Monitor's Memory column shows it: the process's physical footprint, in
/// megabytes of 1,048,576 bytes, to one decimal.
public enum ActivityMonitorMemory {
  public static let bytesPerMegabyte = 1_048_576.0

  /// The footprint in tenths of a megabyte, rounded to the nearest with a half rounding up.
  public static func tenths(bytes: UInt64) -> Int {
    Int((Double(bytes) * 10 / bytesPerMegabyte + 0.5).rounded(.down))
  }

  /// The text Activity Monitor shows, "30.2 MB".
  public static func text(bytes: UInt64) -> String {
    let t = tenths(bytes: bytes)
    return "\(t / 10).\(t % 10) MB"
  }

  /// Whether the value shown is under `megabytes`: a footprint shown as "50.0 MB" is not under
  /// 50 MB.
  public static func isUnder(bytes: UInt64, megabytes: Int) -> Bool {
    tenths(bytes: bytes) < megabytes * 10
  }

  /// The `phys_footprint` figure in `footprint -f bytes --noCategories` output, in bytes.
  public static func physicalFootprint(footprintOutput: String) -> UInt64? {
    for line in footprintOutput.split(separator: "\n") {
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      if fields.count == 3, fields[0] == "phys_footprint:", fields[2] == "B" {
        return UInt64(fields[1])
      }
    }
    return nil
  }
}
