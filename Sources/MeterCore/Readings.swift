import Foundation

/// One reading and the moment it arrived.
public struct Reading: Equatable {
    public var value: Double
    public var at: Date
    public init(value: Double, at: Date) { self.value = value; self.at = at }
}

/// How each reading is derived from the raw inputs.
public enum Derive {
    /// Whole-Mac CPU load as Activity Monitor's CPU tab totals it: User plus
    /// System (nice time counts as User), as a share of all ticks on all
    /// cores since the previous pass.
    public static func cpuPercent(previous: CPUTicks, current: CPUTicks) -> Double? {
        guard current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice else { return nil }
        let user = current.user - previous.user
        let nice = current.nice - previous.nice
        let system = current.system - previous.system
        let idle = current.idle - previous.idle
        let busy = user + nice + system
        let total = busy + idle
        guard total > 0 else { return nil }
        return Double(busy) * 100 / Double(total)
    }

    /// Activity Monitor's Memory Used: App Memory (anonymous pages less the
    /// purgeable ones) plus Wired plus Compressed, plus, on a Mac with a
    /// memory-tagging region, that region and its tag-holding pages, which
    /// Activity Monitor counts in Memory Used though it shows them in none of
    /// the three lines (fitted to Activity Monitor on macOS 26 on an M5).
    /// Cached Files (file-backed and purgeable pages) are not counted.
    public static func memoryUsedBytes(_ vm: VMPages) -> UInt64 {
        let app = vm.internalPages - min(vm.purgeablePages, vm.internalPages)
        let tagging = vm.tagStoragePages + vm.tagStoringPages
        return (app + vm.wiredPages + vm.compressorPages + tagging) * vm.pageSize
    }

    public static func ramPercent(_ vm: VMPages, physicalBytes: UInt64) -> Double? {
        guard physicalBytes > 0, vm.pageSize > 0 else { return nil }
        return Double(memoryUsedBytes(vm)) * 100 / Double(physicalBytes)
    }

    /// macOS's own overall GPU utilization: IOAccelerator's
    /// `Device Utilization %`.
    public static let gpuKey = "Device Utilization %"
    public static func gpuPercent(_ stats: [String: Any]) -> Double? {
        guard let n = stats[gpuKey] as? NSNumber else { return nil }
        return n.doubleValue
    }

    /// The chip temperature: the hottest of the SoC's die sensors
    /// (`PMU tdie<n>`, `PMU2 tdie<n>`, …). Calibration (`tcal`), device
    /// (`tdev`), battery and NAND sensors are not the chip.
    public static func chipCelsius(_ sensors: [String: Double]) -> Double? {
        let die = sensors.filter { isDieSensor($0.key) && $0.value > 0 && $0.value < 150 }
        return die.values.max()
    }

    static func isDieSensor(_ name: String) -> Bool {
        let parts = name.split(separator: " ")
        guard parts.count == 2, parts[0].hasPrefix("PMU"),
              parts[0].dropFirst(3).allSatisfy(\.isNumber),
              parts[1].hasPrefix("tdie"), parts[1].count > 4,
              parts[1].dropFirst(4).allSatisfy(\.isNumber) else { return false }
        return true
    }
}

/// One pass a second over the raw inputs; each reading keeps the moment it
/// last arrived so a stale one can turn into a dash.
public final class Sampler {
    public let inputs: ReadingInputs
    public let physicalBytes: UInt64
    private var lastTicks: CPUTicks?

    public private(set) var cpu: Reading?
    public private(set) var gpu: Reading?
    public private(set) var ram: Reading?
    public private(set) var temperature: Reading?

    public init(inputs: ReadingInputs, physicalBytes: UInt64 = physicalMemoryBytes()) {
        self.inputs = inputs
        self.physicalBytes = physicalBytes
    }

    public func pass(now: Date = Date()) {
        inputs.beginPass()
        if let ticks = inputs.cpuTicks() {
            if let last = lastTicks, let p = Derive.cpuPercent(previous: last, current: ticks) {
                cpu = Reading(value: p, at: now)
            }
            lastTicks = ticks
        }
        if let vm = inputs.vmPages(), let p = Derive.ramPercent(vm, physicalBytes: physicalBytes) {
            ram = Reading(value: p, at: now)
        }
        if let stats = inputs.gpuPerformanceStatistics(), let p = Derive.gpuPercent(stats) {
            gpu = Reading(value: p, at: now)
        }
        if let sensors = inputs.temperatureSensors(), let c = Derive.chipCelsius(sensors) {
            temperature = Reading(value: c, at: now)
        }
    }
}
