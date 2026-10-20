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
}
