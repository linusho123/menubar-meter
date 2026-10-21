import Darwin
import Foundation
import IOKit
import MeterCore

/// The real system: kernel counters, the GPU accelerator's statistics and the die sensors.
final class RealInputs: MeterInputs {
  let physicalMemory: UInt64
  let pageSize: UInt64
  let cpuCores: Int
  private let thermal = ThermalSensors()

  init() {
    var memsize: UInt64 = 0
    var length = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &memsize, &length, nil, 0)
    physicalMemory = memsize
    var pagesize: Int = 0
    length = MemoryLayout<Int>.size
    sysctlbyname("hw.pagesize", &pagesize, &length, nil, 0)
    pageSize = UInt64(pagesize)
    var ncpu: Int32 = 0
    length = MemoryLayout<Int32>.size
    sysctlbyname("hw.ncpu", &ncpu, &length, nil, 0)
    cpuCores = Int(ncpu)
  }

  func cpuTicks() -> CPUTicks? {
    var info = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    let ticks = info.cpu_ticks
    return CPUTicks(
      user: UInt64(ticks.0), system: UInt64(ticks.1), idle: UInt64(ticks.2),
      nice: UInt64(ticks.3))
  }

  func memoryPages() -> MemoryPages? {
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return MemoryPages(
      anonymous: UInt64(stats.internal_page_count),
      purgeable: UInt64(stats.purgeable_count),
      wired: UInt64(stats.wire_count),
      compressed: UInt64(stats.compressor_page_count),
      fileBacked: UInt64(stats.external_page_count))
  }

  func gpuPerformanceStatistics() -> [String: Int]? {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
        == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      guard
        let property = IORegistryEntryCreateCFProperty(
          service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? [String: Any]
      else { continue }
      var stats: [String: Int] = [:]
      for (key, value) in property {
        if let number = value as? NSNumber { stats[key] = number.intValue }
      }
      if stats[GPUUtilization.statisticKey] != nil { return stats }
    }
    return nil
  }

  func temperatureSensors() -> [String: Double]? {
    thermal.read()
  }

  /// Every interface's 64-bit link-level counters, as `netstat -ib` reads them: the kernel's
  /// interface list (`NET_RT_IFLIST2`), one `RTM_IFINFO2` message per interface.
  func networkInterfaces(now: Double) -> [InterfaceCounters]? {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var length = 0
    guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
    // Room for an interface that appears between the two calls.
    length += length / 4
    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
    var interfaces: [InterfaceCounters] = []
    buffer.withUnsafeBytes { raw in
      var offset = 0
      while offset + MemoryLayout<if_msghdr>.size <= length {
        let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
        let size = Int(header.ifm_msglen)
        guard size > 0 else { break }
        if Int32(header.ifm_type) == RTM_IFINFO2,
          offset + MemoryLayout<if_msghdr2>.size <= length
        {
          let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
          var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
          if if_indextoname(UInt32(message.ifm_index), &name) != nil {
            interfaces.append(
              InterfaceCounters(
                name: String(cString: name), received: message.ifm_data.ifi_ibytes,
                sent: message.ifm_data.ifi_obytes))
          }
        }
        offset += size
      }
    }
    return interfaces
  }

  /// Every disk's bytes read and written, from each block storage driver's statistics (what
  /// `iostat` and Activity Monitor's Disk tab total), keyed by the driver's registry entry.
  func diskCounters(now: Double) -> [String: ByteCounts]? {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
        == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    var disks: [String: ByteCounts] = [:]
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      guard
        let statistics = IORegistryEntryCreateCFProperty(
          service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
          .takeRetainedValue() as? [String: Any],
        let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value,
        let written = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value
      else { continue }
      var entry: UInt64 = 0
      IORegistryEntryGetRegistryEntryID(service, &entry)
      disks[String(entry)] = ByteCounts(read, written)
    }
    return disks
  }
}
