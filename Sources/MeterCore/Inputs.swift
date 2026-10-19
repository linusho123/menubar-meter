import Foundation

/// Cumulative CPU time since boot, in ticks, summed over every core
/// (the kernel's HOST_CPU_LOAD_INFO).
public struct CPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

/// The page counts of the kernel's vm_statistics64 that Activity Monitor's
/// Memory tab is built from, plus the page size they are counted in.
public struct VMPages: Equatable {
    public var pageSize: UInt64
    /// Anonymous (app) pages, purgeable ones included (`internal_page_count`).
    public var internalPages: UInt64
    /// File-backed pages (`external_page_count`): cache.
    public var externalPages: UInt64
    /// Purgeable pages (`purgeable_count`): cache.
    public var purgeablePages: UInt64
    /// Wired pages (`wire_count`).
    public var wiredPages: UInt64
    /// Pages the compressor occupies (`compressor_page_count`).
    public var compressorPages: UInt64
    /// The memory-tagging region (`total_tag_storage_pages`; 0 on Macs and
    /// macOS versions without one).
    public var tagStoragePages: UInt64
    /// Pages of that region holding tags (`tag_storing_tag_storage_pages`).
    public var tagStoringPages: UInt64
    public init(pageSize: UInt64, internalPages: UInt64, externalPages: UInt64,
                purgeablePages: UInt64, wiredPages: UInt64, compressorPages: UInt64,
                tagStoragePages: UInt64 = 0, tagStoringPages: UInt64 = 0) {
        self.pageSize = pageSize; self.internalPages = internalPages
        self.externalPages = externalPages; self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages; self.compressorPages = compressorPages
        self.tagStoragePages = tagStoragePages; self.tagStoringPages = tagStoringPages
    }
}

/// The raw inputs one sampling pass reads. The real source asks macOS; the
/// test-only source (compiled in only under METER_TEST_SOURCE) replaces
/// exactly this and nothing downstream of it. A `nil` is "no fresh reading".
public protocol ReadingInputs: AnyObject {
    /// Called once at the start of every pass.
    func beginPass()
    func cpuTicks() -> CPUTicks?
    func vmPages() -> VMPages?
    /// IOAccelerator's `PerformanceStatistics` dictionary.
    func gpuPerformanceStatistics() -> [String: Any]?
    /// Every temperature sensor macOS's HID event system lists: product
    /// name to degrees Celsius.
    func temperatureSensors() -> [String: Double]?
}

/// The Mac's physical memory, `hw.memsize`. Always read from the real
/// system, in every build.
public func physicalMemoryBytes() -> UInt64 {
    var size: UInt64 = 0
    var len = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &size, &len, nil, 0)
    return size
}
