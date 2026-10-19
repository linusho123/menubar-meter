#if METER_TEST_SOURCE
  import Foundation
  import MeterCore

  /// The test reading source, compiled only into test builds (-DMETER_TEST_SOURCE) and used only
  /// when the harness names a feed file. It replaces the sampler's raw inputs and nothing else:
  /// the counters, page counts, GPU statistics and sensors the real system would give. Physical
  /// memory and the page size stay the real Mac's. A missing entry in the feed is a reading
  /// that does not arrive.
  ///
  /// The feed is a JSON file the harness rewrites atomically:
  ///   cpu:     {"user": %, "system": %, "since": epoch ms} - the load from `since` on
  ///   memory:  {"anonymous", "purgeable", "wired", "compressed", "fileBacked"} page counts
  ///   gpu:     the accelerator's performance statistics, e.g. {"Device Utilization %": 4}
  ///   sensors: temperature sensor readings by name, e.g. {"PMU tdie1": 45.0}
  final class TestInputs: MeterInputs {
    static let feedVariable = "METER_TEST_FEED"

    private struct Feed: Decodable {
      struct CPU: Decodable, Equatable {
        var user: Double
        var system: Double
        var since: Int64
      }
      struct Memory: Decodable {
        var anonymous: UInt64
        var purgeable: UInt64
        var wired: UInt64
        var compressed: UInt64
        var fileBacked: UInt64
      }
      var cpu: CPU?
      var memory: Memory?
      var gpu: [String: Int]?
      var sensors: [String: Double]?
    }

    private let feedPath: String
    private let real: RealInputs
    private var feed: Feed?

    // The simulated kernel counters: 1000 ticks per millisecond across the whole Mac, split
    // between user, system and idle by the load in effect over each millisecond.
    private var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
    private var load: Feed.CPU?
    private var integratedTo: Int64?

    init(feedPath: String, real: RealInputs) {
      self.feedPath = feedPath
      self.real = real
    }

    var physicalMemory: UInt64 { real.physicalMemory }
    var pageSize: UInt64 { real.pageSize }

    private func reload() {
      guard let data = FileManager.default.contents(atPath: feedPath),
        let decoded = try? JSONDecoder().decode(Feed.self, from: data)
      else { return }
      feed = decoded
    }

    private static func nowMilliseconds() -> Int64 {
      Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    }

    private func advance(to end: Int64, at cpu: Feed.CPU) {
      guard let start = integratedTo, end > start else { return }
      let milliseconds = UInt64(end - start)
      let user = UInt64((cpu.user * 10).rounded())
      let system = UInt64((cpu.system * 10).rounded())
      let idle = 1000 - min(1000, user + system)
      ticks.user += user * milliseconds
      ticks.system += system * milliseconds
      ticks.idle += idle * milliseconds
      integratedTo = end
    }

    func cpuTicks() -> CPUTicks? {
      reload()
      let now = Self.nowMilliseconds()
      guard let current = feed?.cpu else {
        load = nil
        integratedTo = nil
        return nil
      }
      if let previous = load, previous != current {
        // The old load ran until the change, the new one from then on.
        advance(to: min(max(current.since, integratedTo ?? now), now), at: previous)
      }
      if integratedTo == nil { integratedTo = now }
      load = current
      advance(to: now, at: current)
      return ticks
    }

    func memoryPages() -> MemoryPages? {
      reload()
      guard let memory = feed?.memory else { return nil }
      return MemoryPages(
        anonymous: memory.anonymous, purgeable: memory.purgeable, wired: memory.wired,
        compressed: memory.compressed, fileBacked: memory.fileBacked)
    }

    func gpuPerformanceStatistics() -> [String: Int]? {
      reload()
      return feed?.gpu
    }

    func temperatureSensors() -> [String: Double]? {
      reload()
      return feed?.sensors
    }
  }
#endif
