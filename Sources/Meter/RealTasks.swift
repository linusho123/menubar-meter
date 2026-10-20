import AppKit
import Darwin
import IOKit
import MeterCore

/// The real system's tasks: the kernel's process table for who runs each task and when it
/// started, its resource usage for CPU time and memory, its program's path, and the GPU's
/// per-client statistics for GPU time.
extension RealInputs: TaskInputs {
  var userID: UInt32 { getuid() }
  var ownPID: Int32 { getpid() }

  func resolve(path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  func processes() -> [ProcessSample]? {
    guard let table = RealTasks.processTable() else { return nil }
    let gpu = RealTasks.gpuTimes()
    var appNames: [Int32: String] = [:]
    for app in NSWorkspace.shared.runningApplications {
      if let name = app.localizedName { appNames[app.processIdentifier] = name }
    }
    return table.compactMap { entry in
      guard let usage = RealTasks.usage(entry.pid) else { return nil }
      let path = RealTasks.path(entry.pid)
      let name =
        appNames[entry.pid] ?? path.map { ($0 as NSString).lastPathComponent } ?? entry.command
      return ProcessSample(
        id: TaskID(pid: entry.pid, started: entry.started), name: name, uid: entry.uid,
        path: path, cpuTime: RealTasks.nanoseconds(usage.cpu), gpuTime: gpu[entry.pid] ?? 0,
        memory: usage.memory)
    }
  }
}

enum RealTasks {
  struct Entry {
    var pid: Int32
    var uid: UInt32
    var started: UInt64
    var command: String
  }

  /// Every process the kernel lists, with its owner and start time (what `ps` reads).
  static func processTable() -> [Entry]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return nil }
    let stride = MemoryLayout<kinfo_proc>.stride
    var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
    size = table.count * stride
    guard sysctl(&mib, 4, &table, &size, nil, 0) == 0 else { return nil }
    return table.prefix(size / stride).map { process in
      let start = process.kp_proc.p_un.__p_starttime
      var comm = process.kp_proc.p_comm
      let command = withUnsafeBytes(of: &comm) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
      }
      return Entry(
        pid: process.kp_proc.p_pid, uid: process.kp_eproc.e_ucred.cr_uid,
        started: UInt64(start.tv_sec) * 1_000_000 + UInt64(start.tv_usec), command: command)
    }
  }

  /// A process's CPU time (user plus system, in the kernel's time units) and its memory as
  /// Activity Monitor's Memory column counts it (the physical footprint).
  static func usage(_ pid: Int32) -> (cpu: UInt64, memory: UInt64)? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
      }
    }
    guard result == 0 else { return nil }
    return (info.ri_user_time + info.ri_system_time, info.ri_phys_footprint)
  }

  /// The process's program, as the kernel names its executable.
  static func path(_ pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(
      decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  private static let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  /// The kernel's time units in nanoseconds.
  static func nanoseconds(_ ticks: UInt64) -> UInt64 {
    let (product, overflow) = ticks.multipliedReportingOverflow(by: UInt64(timebase.numer))
    if overflow { return ticks / UInt64(timebase.denom) * UInt64(timebase.numer) }
    return product / UInt64(timebase.denom)
  }

  /// Each process's GPU time so far, in nanoseconds: the accumulated GPU time the GPU's
  /// driver keeps for every client a process opened on it, summed per process. Activity
  /// Monitor's `% GPU` is the share of time this grows by (D49).
  static func gpuTimes() -> [Int32: UInt64] {
    var times: [Int32: UInt64] = [:]
    var accelerators: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS
    else { return times }
    defer { IOObjectRelease(accelerators) }
    while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
      defer { IOObjectRelease(accelerator) }
      var clients: io_iterator_t = 0
      guard
        IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == KERN_SUCCESS
      else { continue }
      while case let client = IOIteratorNext(clients), client != 0 {
        defer { IOObjectRelease(client) }
        guard let creator = property(client, "IOUserClientCreator") as? String,
          let pid = clientPID(creator),
          let usage = property(client, "AppUsage") as? [[String: Any]]
        else { continue }
        for entry in usage {
          if let time = entry["accumulatedGPUTime"] as? NSNumber {
            times[pid, default: 0] &+= time.uint64Value
          }
        }
      }
      IOObjectRelease(clients)
    }
    return times
  }

  private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }

  /// The process id in a client's creator, as in "pid 423, WindowServer".
  static func clientPID(_ creator: String) -> Int32? {
    guard creator.hasPrefix("pid ") else { return nil }
    let digits = creator.dropFirst(4).prefix { $0.isNumber }
    return Int32(digits)
  }
}
