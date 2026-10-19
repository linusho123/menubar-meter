import Foundation
import IOKit

/// Asks macOS itself. No admin password, no helper.
public final class RealInputs: ReadingInputs {
    private let hid = HIDTemperatureSensors()

    public init() {}

    public func beginPass() {}

    public func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    public func vmPages() -> VMPages? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        return VMPages(pageSize: UInt64(pageSize),
                       internalPages: UInt64(stats.internal_page_count),
                       externalPages: UInt64(stats.external_page_count),
                       purgeablePages: UInt64(stats.purgeable_count),
                       wiredPages: UInt64(stats.wire_count),
                       compressorPages: UInt64(stats.compressor_page_count),
                       tagStoragePages: stats.total_tag_storage_pages,
                       tagStoringPages: stats.tag_storing_tag_storage_pages)
    }

    public func gpuPerformanceStatistics() -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var best: [String: Any]?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let prop = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let stats = prop.takeRetainedValue() as? [String: Any],
                  let value = Derive.gpuPercent(stats) else { continue }
            if best == nil || value > (Derive.gpuPercent(best!) ?? -1) { best = stats }
        }
        return best
    }

    public func temperatureSensors() -> [String: Double]? {
        hid.read()
    }
}

// The HID event system's temperature sensors, readable by the logged-in user
// without an admin password (the named assumption chip-temperature-readable,
// D87). These are private CoreFoundation-style entry points of IOKit.
private typealias IOHIDEventSystemClientRef = OpaquePointer
private typealias IOHIDServiceClientRef = OpaquePointer
private typealias IOHIDEventRef = OpaquePointer

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClientRef?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> CFArray?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: IOHIDServiceClientRef, _ key: CFString) -> CFTypeRef?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClientRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> IOHIDEventRef?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

private final class HIDTemperatureSensors {
    private static let temperatureEvent: Int64 = 15        // kIOHIDEventTypeTemperature
    private static let temperatureLevel: Int32 = 15 << 16  // its level field
    private let client: IOHIDEventSystemClientRef?

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        if let client {
            // Apple vendor page, temperature-sensor usage.
            let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
            _ = IOHIDEventSystemClientSetMatching(client, matching)
        }
    }

    func read() -> [String: Double]? {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [AnyObject] else { return nil }
        var out: [String: Double] = [:]
        for s in services {
            let service = OpaquePointer(Unmanaged.passUnretained(s).toOpaque())
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = IOHIDServiceClientCopyEvent(service, Self.temperatureEvent, 0, 0) else { continue }
            out[name] = IOHIDEventGetFloatValue(event, Self.temperatureLevel)
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release()
        }
        return out.isEmpty ? nil : out
    }
}
