#if METER_TEST_SOURCE
import Foundation

/// TEST ONLY. Compiled in only when the build passes -DMETER_TEST_SOURCE; the
/// installed app is built without it. It replaces the raw inputs of the
/// sampler, and nothing else, with values the test harness writes to a JSON
/// file named by the METER_TEST_SOURCE environment variable:
///
///     { "cpuTicksPerPass": {"user":…,"system":…,"nice":…,"idle":…},
///       "vm": {"pageSize":…,"internal":…,"external":…,"purgeable":…,"wired":…,"compressor":…,
///              "tagStorage":…,"tagStoring":…},
///       "gpu": { "Device Utilization %": …, … },
///       "sensors": { "PMU tdie1": …, … } }
///
/// A missing or null key is "no fresh reading" for that input. CPU ticks are
/// given per pass and accumulated here into since-boot counters, so the
/// sampler's own differencing still runs.
public final class TestInputs: ReadingInputs {
    public static let environmentKey = "METER_TEST_SOURCE"

    private let url: URL
    private var doc: [String: Any] = [:]
    private var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)

    public init(path: String) { url = URL(fileURLWithPath: path) }

    public static func fromEnvironment() -> TestInputs? {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else { return nil }
        return TestInputs(path: path)
    }

    public func beginPass() {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            doc = [:]
            return
        }
        doc = obj
    }

    private func u64(_ d: [String: Any], _ k: String) -> UInt64? {
        (d[k] as? NSNumber).map { $0.uint64Value }
    }

    public func cpuTicks() -> CPUTicks? {
        guard let d = doc["cpuTicksPerPass"] as? [String: Any],
              let user = u64(d, "user"), let system = u64(d, "system"),
              let idle = u64(d, "idle"), let nice = u64(d, "nice") else { return nil }
        ticks.user += user; ticks.system += system; ticks.idle += idle; ticks.nice += nice
        return ticks
    }

    public func vmPages() -> VMPages? {
        guard let d = doc["vm"] as? [String: Any],
              let pageSize = u64(d, "pageSize"), let internalPages = u64(d, "internal"),
              let externalPages = u64(d, "external"), let purgeablePages = u64(d, "purgeable"),
              let wiredPages = u64(d, "wired"), let compressorPages = u64(d, "compressor") else { return nil }
        return VMPages(pageSize: pageSize, internalPages: internalPages, externalPages: externalPages,
                       purgeablePages: purgeablePages, wiredPages: wiredPages, compressorPages: compressorPages,
                       tagStoragePages: u64(d, "tagStorage") ?? 0, tagStoringPages: u64(d, "tagStoring") ?? 0)
    }

    public func gpuPerformanceStatistics() -> [String: Any]? {
        doc["gpu"] as? [String: Any]
    }

    public func temperatureSensors() -> [String: Double]? {
        guard let d = doc["sensors"] as? [String: Any] else { return nil }
        var out: [String: Double] = [:]
        for (k, v) in d { if let n = v as? NSNumber { out[k] = n.doubleValue } }
        return out
    }
}
#endif
