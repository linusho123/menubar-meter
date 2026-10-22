#if METER_TEST_SOURCE
  import AppKit
  import MeterClock
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
  ///   network: {"received": bytes/s, "sent": bytes/s} - the whole Mac's network rates
  ///   disk:    {"read": bytes/s, "written": bytes/s} - the whole Mac's disk rates; for each, one
  ///            interface's (one disk's) counters grow at those rates on the meter's clock,
  ///            so each pass measures them back exactly
  ///   cores:   optional, the Mac's CPU core count in place of `hw.ncpu`
  ///   tasks:   optional, the running tasks in place of the real ones, each {"pid", "started",
  ///            "name", "uid", "path" (or null), "busyCores": CPU cores it keeps busy,
  ///            "gpuShare": the share of GPU time it takes (0 to 1), "memory": bytes}; its CPU
  ///            and GPU time grow at those rates on the meter's clock from the moment it first
  ///            appears, so each refresh measures them back exactly. A task with "real": true
  ///            is a process the harness runs: its start time, owner, program and name are the
  ///            real system's for that process id, and it is listed only while that process
  ///            runs, so it leaves the list when the process ends; only its rates come from here
  ///   gpuBusy: optional, the percent the GPU is busy over the fed tasks' refreshes (its Device
  ///            Utilization %); as busy as the fed tasks' shares add up to when absent
  ///   past:    optional, the time the meter has already run through before this launch, as
  ///            consecutive stretches ending now, each {"seconds": n} with the cpu (no
  ///            `since`), memory, gpu and sensors in effect over it, or {"seconds": n,
  ///            "asleep": true} for a stretch the Mac slept through
  ///
  /// The past is driven at launch through the meter's own loop on the past's own clock: the
  /// CPU counters every quarter second of it and a pass every half second, and for a sleep the
  /// system's own sleep and wake notifications, posted where macOS posts them. The clock this
  /// source gives the meter is the real one, except while that past runs.
  final class TestInputs: MeterInputs, TaskInputs {
    static let feedVariable = "METER_TEST_FEED"

    private struct Feed: Decodable {
      struct CPU: Decodable, Equatable {
        var user: Double
        var system: Double
        var since: Int64?
      }
      struct Stretch: Decodable {
        var seconds: Double
        var asleep: Bool?
        var cpu: CPU?
        var memory: Memory?
        var gpu: [String: Int]?
        var sensors: [String: Double]?
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
      var past: [Stretch]?
      var cores: Int?
      var tasks: [Task]?
      var gpuBusy: Double?
      var network: Rates?
      var disk: Rates?
    }

    private struct Rates: Decodable {
      var received: Double?
      var sent: Double?
      var read: Double?
      var written: Double?
    }

    /// Fed byte counters, grown at the fed rates from the last read to this one.
    private struct Counter {
      var first: Double = 0
      var second: Double = 0
      var at: Double?

      mutating func grow(to now: Double, first rate1: Double, second rate2: Double) -> ByteCounts {
        if let at, now > at {
          first += max(0, rate1) * (now - at)
          second += max(0, rate2) * (now - at)
        }
        at = now
        return ByteCounts(UInt64(first.rounded()), UInt64(second.rounded()))
      }
    }
    private var networkCounter = Counter()
    private var diskCounter = Counter()

    private struct Task: Decodable {
      var pid: Int32
      var real: Bool?
      var started: UInt64?
      var name: String
      var uid: UInt32
      var path: String?
      var busyCores: Double
      var gpuShare: Double
      var memory: UInt64
    }

    /// Each fed task's CPU and GPU time so far, in nanoseconds, and when they were last grown.
    private var taskTimes: [TaskID: (cpu: Double, gpu: Double, at: Double)] = [:]

    private let feedPath: String
    private let real: RealInputs
    private var feed: Feed?

    // The simulated kernel counters: 1000 ticks per millisecond across the whole Mac, split
    // between user, system and idle by the load in effect over each millisecond.
    private var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
    private var load: Feed.CPU?
    private var integratedTo: Int64?

    /// While the past runs: its clock (seconds on the meter's clock, and epoch milliseconds)
    /// and the readings in effect.
    private var pastNow: (seconds: Double, milliseconds: Int64)?

    init(feedPath: String, real: RealInputs) {
      self.feedPath = feedPath
      self.real = real
    }

    var physicalMemory: UInt64 { real.physicalMemory }
    var pageSize: UInt64 { real.pageSize }
    var cpuCores: Int { feed?.cores ?? real.cpuCores }
    var userID: UInt32 { real.userID }
    var ownPID: Int32 { real.ownPID }

    func resolve(path: String) -> String? {
      real.resolve(path: path)
    }

    /// The fed tasks, their times grown at their rates since the last read; the real tasks when
    /// the feed names none.
    func snapshot() -> TaskSnapshot? {
      reload()
      guard let tasks = feed?.tasks else {
        taskTimes = [:]
        return real.snapshot()
      }
      let clock = now()
      var times: [TaskID: (cpu: Double, gpu: Double, at: Double)] = [:]
      var gpuTimes: [Int32: UInt64] = [:]
      let appNames = RealTasks.appNames()
      let samples: [ProcessSample] = tasks.compactMap { task in
        var id = TaskID(pid: task.pid, started: task.started ?? 1)
        var (name, uid, path) = (task.name, task.uid, task.path)
        if task.real == true {
          // The harness's own process, as the real system knows it, while it runs.
          guard let found = RealTasks.identity(task.pid) else { return nil }
          path = RealTasks.path(task.pid)
          guard let again = RealTasks.identity(task.pid), again.started == found.started else {
            return nil
          }
          id = TaskID(pid: task.pid, started: found.started)
          uid = found.uid
          name = RealTasks.name(
            pid: task.pid, path: path, command: found.command, apps: appNames)
        }
        var time = taskTimes[id] ?? (cpu: 0, gpu: 0, at: clock)
        let seconds = max(0, clock - time.at)
        time.cpu += task.busyCores * seconds * 1_000_000_000
        time.gpu += task.gpuShare * seconds * 1_000_000_000
        time.at = clock
        times[id] = time
        gpuTimes[task.pid, default: 0] += UInt64(time.gpu.rounded())
        return ProcessSample(
          id: id, name: name, uid: uid, path: path,
          cpuTime: UInt64(time.cpu.rounded()), memory: task.memory)
      }
      taskTimes = times
      // The fed GPU is as busy as the feed says, else exactly as busy as its fed tasks keep it.
      let kept = tasks.reduce(0) { $0 + max(0, $1.gpuShare) }
      let busy = min(1, feed?.gpuBusy.map { $0 / 100 } ?? kept)
      return TaskSnapshot(
        processes: samples, gpuTimes: gpuTimes,
        gpuBusy: Share(part: UInt64((busy * 1_000_000).rounded()), whole: 1_000_000))
    }

    /// The meter's clock: the real one, or the past's while it runs.
    func now() -> Double {
      pastNow?.seconds ?? Clock.now()
    }

    private func reload() {
      guard pastNow == nil, let data = FileManager.default.contents(atPath: feedPath),
        let decoded = try? JSONDecoder().decode(Feed.self, from: data)
      else { return }
      feed = decoded
    }

    private func nowMilliseconds() -> Int64 {
      pastNow?.milliseconds ?? Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
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
      let now = nowMilliseconds()
      guard let current = feed?.cpu else {
        load = nil
        integratedTo = nil
        return nil
      }
      if let previous = load, previous != current {
        // The old load ran until the change, the new one from then on.
        advance(to: min(max(current.since ?? now, integratedTo ?? now), now), at: previous)
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

    func networkInterfaces(now: Double) -> [InterfaceCounters]? {
      reload()
      guard let rates = feed?.network else {
        networkCounter.at = nil
        return nil
      }
      let counts = networkCounter.grow(
        to: now, first: rates.received ?? 0, second: rates.sent ?? 0)
      return [InterfaceCounters(name: "en0", received: counts.first, sent: counts.second)]
    }

    func diskCounters(now: Double) -> [String: ByteCounts]? {
      reload()
      guard let rates = feed?.disk else {
        diskCounter.at = nil
        return nil
      }
      return [
        "disk0": diskCounter.grow(to: now, first: rates.read ?? 0, second: rates.written ?? 0)
      ]
    }

    /// Runs the meter through the feed's past, if it has one, ending at this moment: `tick`
    /// is the meter's own CPU-counter tick, called every quarter second of the past's clock.
    func runPast(tick: (Double) -> Void) {
      reload()
      guard let live = feed, let past = live.past, !past.isEmpty else { return }
      let endSeconds = Clock.now()
      let endMilliseconds = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
      var offset = -past.reduce(0) { $0 + $1.seconds }
      func setClock(_ offset: Double) {
        pastNow = (endSeconds + offset, endMilliseconds + Int64((offset * 1000).rounded()))
      }
      let workspace = NSWorkspace.shared.notificationCenter
      for stretch in past {
        let end = offset + stretch.seconds
        if stretch.asleep == true {
          setClock(offset)
          workspace.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
          setClock(end)
          // No CPU time passes in the counters while the Mac sleeps.
          if integratedTo != nil { integratedTo = pastNow?.milliseconds }
          // macOS can run a timer tick at wake before it delivers didWake: enough ticks for a
          // full pass, so a sample is taken in that order too.
          for _ in 0..<MeterEngine.readsPerPass { tick(pastNow?.seconds ?? 0) }
          workspace.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
          offset = end
          continue
        }
        setClock(offset)
        var cpu = stretch.cpu
        cpu?.since = pastNow?.milliseconds
        feed = Feed(
          cpu: cpu, memory: stretch.memory, gpu: stretch.gpu, sensors: stretch.sensors, past: nil,
          cores: live.cores, tasks: live.tasks)
        while offset + Sampler.cpuInterval <= end + 1e-9 {
          offset += Sampler.cpuInterval
          setClock(offset)
          tick(pastNow?.seconds ?? 0)
        }
        offset = end
      }
      pastNow = nil
      feed = live
    }
  }
#endif
