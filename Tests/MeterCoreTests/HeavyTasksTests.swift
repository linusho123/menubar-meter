import Testing

@testable import MeterCore

private let gib: UInt64 = 1 << 30

/// A task's use given as the user reads it, in percent of the whole Mac.
private func task(
  _ name: String, cpu: Double, gpu: Double = 0, ram: Double = 1, pid: Int32? = nil,
  system: Bool = false
) -> TaskUsage {
  func share(_ percent: Double) -> Share? {
    Share(part: UInt64((percent * 100_000).rounded()), whole: 10_000_000)
  }
  // A stable process id from the name, unless the test gives one.
  let hashed = name.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } % 90_000
  let id = TaskID(pid: pid ?? Int32(hashed) + 100, started: 1)
  return TaskUsage(
    id: id, name: name, cpu: share(cpu), gpu: share(gpu), ram: share(ram), isSystem: system)
}

private func names(_ rows: [HeavyRow]) -> [String] {
  rows.map(\.task.name)
}

@Suite("Ranking the heavy tasks (D108, D109, D58)")
struct RankingTests {
  @Test("the top five by CPU, then the biggest GPU user, then the biggest RAM user")
  func topFivePlusHogs() {
    let rows = HeavyTasks.rank([
      task("Photos", cpu: 5, ram: 40),
      task("node", cpu: 30, ram: 3),
      task("Chrome", cpu: 1, gpu: 90, ram: 4),
      task("Mail", cpu: 15),
      task("Xcode", cpu: 25, ram: 6),
      task("Spotify", cpu: 10, gpu: 1, ram: 2),
      task("Safari", cpu: 20, gpu: 2, ram: 4),
    ])
    #expect(names(rows) == ["node", "Xcode", "Safari", "Mail", "Spotify", "Chrome", "Photos"])
    #expect(rows.map(\.words) == [[], [], [], [], [], ["GPU"], ["RAM"]])
  }

  @Test("ranked by CPU alone, never by RAM or GPU")
  func cpuAlone() {
    let rows = HeavyTasks.rank([
      task("a", cpu: 1, gpu: 5, ram: 9),
      task("b", cpu: 2, gpu: 4, ram: 8),
      task("c", cpu: 3, gpu: 3, ram: 7),
      task("d", cpu: 4, gpu: 2, ram: 6),
      task("e", cpu: 5, gpu: 1, ram: 5),
      task("f", cpu: 6, gpu: 0, ram: 4),
    ])
    #expect(names(rows) == ["f", "e", "d", "c", "b"])
  }

  @Test("a tie is broken alphabetically, not by process id")
  func tieAlphabetical() {
    let rows = HeavyTasks.rank([
      task("A", cpu: 40), task("B", cpu: 30), task("C", cpu: 20), task("D", cpu: 15),
      task("Notes", cpu: 12, pid: 200), task("Maps", cpu: 12, pid: 300),
    ])
    #expect(names(rows) == ["A", "B", "C", "D", "Maps"])
  }

  @Test("ties ignore case: node before Xcode")
  func tieIgnoresCase() {
    let rows = HeavyTasks.rank([task("Xcode", cpu: 20, pid: 1), task("node", cpu: 20, pid: 2)])
    #expect(names(rows) == ["node", "Xcode"])
  }

  @Test("tasks tied as the user reads them, to one decimal, are ordered by name")
  func tieAtOneDecimal() {
    let rows = HeavyTasks.rank([task("Notes", cpu: 12.04), task("Maps", cpu: 12.01)])
    #expect(names(rows) == ["Maps", "Notes"])
  }

  @Test(
    "an extra row only for over a tenth of the GPU or the Mac's memory",
    arguments: [
      (9.9, false), (10.0, false), (10.0001, true), (10.1, true), (90.0, true),
    ])
  func extraRowBar(percent: Double, listed: Bool) {
    let five = (1...5).map { task("cpu\($0)", cpu: Double(20 + $0), gpu: 1, ram: 1) }
    let gpuHog = HeavyTasks.rank(five + [task("hog", cpu: 1, gpu: percent, ram: 1)])
    #expect(gpuHog.contains { $0.task.name == "hog" && $0.tags == [.gpu] } == listed)
    #expect(gpuHog.count == (listed ? 6 : 5))
    let ramHog = HeavyTasks.rank(five + [task("hog", cpu: 1, gpu: 0, ram: percent)])
    #expect(ramHog.contains { $0.task.name == "hog" && $0.tags == [.ram] } == listed)
    #expect(ramHog.count == (listed ? 6 : 5))
  }

  @Test("the bar at its edge, exactly: a tenth is not over a tenth")
  func hogEdge() {
    #expect(!HeavyTasks.isHog(Share(part: 100, whole: 1000)!))
    #expect(HeavyTasks.isHog(Share(part: 101, whole: 1000)!))
    #expect(!HeavyTasks.isHog(Share(part: 99, whole: 1000)!))
  }

  @Test("a biggest GPU or RAM user already among the five gets no extra row")
  func hogInFive() {
    let rows = HeavyTasks.rank([
      task("a", cpu: 50, gpu: 80, ram: 60), task("b", cpu: 40), task("c", cpu: 30),
      task("d", cpu: 20), task("e", cpu: 10), task("f", cpu: 1, gpu: 50, ram: 50),
    ])
    #expect(names(rows) == ["a", "b", "c", "d", "e"])
    #expect(rows.allSatisfy { $0.tags.isEmpty })
  }

  @Test("one task that is both the GPU and the RAM hog takes one row with both tags")
  func bothHogs() {
    let five = (1...5).map { task("cpu\($0)", cpu: Double(20 + $0)) }
    let rows = HeavyTasks.rank(five + [task("hog", cpu: 1, gpu: 50, ram: 50)])
    #expect(names(rows) == ["cpu5", "cpu4", "cpu3", "cpu2", "cpu1", "hog"])
    #expect(rows.last?.words == ["GPU", "RAM"])
  }

  @Test("a quiet Mac shows just the five CPU rows")
  func quiet() {
    let rows = HeavyTasks.rank((1...9).map { task("t\($0)", cpu: Double($0), gpu: 1, ram: 2) })
    #expect(rows.count == 5)
  }

  @Test("a system task keeps its rank and counts toward the five; an extra row can be system")
  func systemRows() {
    let rows = HeavyTasks.rank([
      task("WindowServer", cpu: 30, system: true), task("b", cpu: 20), task("c", cpu: 10),
      task("d", cpu: 5), task("e", cpu: 4), task("f", cpu: 3),
      task("kernel_task", cpu: 1, gpu: 40, system: true),
    ])
    #expect(names(rows) == ["WindowServer", "b", "c", "d", "e", "kernel_task"])
    #expect(rows.first?.words == ["system"])
    #expect(rows.last?.words == ["GPU", "system"])
  }

  @Test("a task with no CPU reading yet is not ranked")
  func noReading() {
    var fresh = task("new", cpu: 99)
    fresh.cpu = nil
    #expect(HeavyTasks.rank([fresh, task("old", cpu: 1)]).map(\.task.name) == ["old"])
  }
}

@Suite("The system mark (D99, D57)")
struct SystemTaskTests {
  private let me: UInt32 = 501
  private let meter: Int32 = 4242

  private func isSystem(
    pid: Int32 = 77, uid: UInt32 = 501, path: String?,
    links: [String: String] = [:]
  ) -> Bool {
    SystemTasks.isSystem(
      pid: pid, uid: uid, path: path, userID: me, ownPID: meter,
      resolve: { links[$0] ?? $0 })
  }

  @Test("a program in /System is system, whoever it runs as")
  func inSystem() {
    #expect(isSystem(path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/x"))
    #expect(isSystem(path: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"))
  }

  @Test("a task not run as the user is system, wherever its program lives")
  func otherUser() {
    #expect(isSystem(uid: 88, path: "/Users/me/bin/WindowServer"))
    #expect(isSystem(uid: 0, path: nil))
  }

  @Test("the user's own programs outside /System keep End")
  func ownTasks() {
    #expect(!isSystem(path: "/Users/me/.nvm/versions/node/v24.19.0/bin/node"))
    #expect(!isSystem(path: "/Applications/Xcode.app/Contents/MacOS/Xcode"))
  }

  @Test("a lookalike folder or name does not fool it")
  func lookalike() {
    #expect(!isSystem(path: "/Systems/loginwindow"))
    #expect(!isSystem(path: "/SystemX/Library/CoreServices/Dock"))
    #expect(!isSystem(path: "/Users/me/System/Library/CoreServices/loginwindow"))
    #expect(!isSystem(path: "/Users/me/bin/loginwindow"))
  }

  @Test("a symbolic link is resolved: a link into /System is system, a link out is not")
  func symlinks() {
    #expect(isSystem(path: "/Users/me/bin/dock", links: ["/Users/me/bin/dock": "/System/Dock"]))
    #expect(!isSystem(path: "/System/link", links: ["/System/link": "/Users/me/real"]))
  }

  @Test("the path is read as the disk reads it: case and dot segments do not fool it")
  func normalised() {
    #expect(isSystem(path: "/system/Library/CoreServices/Dock.app/Contents/MacOS/Dock"))
    #expect(isSystem(path: "//System/Library/x"))
    #expect(isSystem(path: "/Users/../System/Library/x"))
    #expect(!isSystem(path: "/System/../Users/me/x"))
    #expect(!isSystem(path: "System/Library/x"))
  }

  @Test("a program the system does not name is system: it cannot be shown to be the user's")
  func unknownPath() {
    #expect(isSystem(path: nil))
  }

  @Test("the meter itself is system")
  func meterItself() {
    #expect(isSystem(pid: meter, path: "/Applications/Meter.app/Contents/MacOS/Meter"))
  }
}

private final class FedTasks: TaskInputs {
  var list: [ProcessSample]? = []
  var cpuCores = 10
  var physicalMemory: UInt64 = 32 * gib
  var userID: UInt32 = 501
  var ownPID: Int32 = 4242
  func processes() -> [ProcessSample]? { list }
  func resolve(path: String) -> String? { path }
}

private func process(
  _ pid: Int32, started: UInt64 = 1, cpu: UInt64 = 0, gpu: UInt64 = 0, memory: UInt64 = 0,
  uid: UInt32 = 501, path: String? = "/Users/me/bin/task"
) -> ProcessSample {
  ProcessSample(
    id: TaskID(pid: pid, started: started), name: "task\(pid)", uid: uid, path: path,
    cpuTime: cpu, gpuTime: gpu, memory: memory)
}

@Suite("Each task's share of the whole Mac (D54, D107, D80, D49)")
struct TaskSamplerTests {
  /// The tasks' values after `busyCores` cores' worth of CPU time over `seconds`.
  private func measure(
    cores: Int, busyCores: Double, seconds: Double = 0.5, memory: UInt64 = 0,
    gpu: Double = 0
  ) -> TaskUsage? {
    let inputs = FedTasks()
    inputs.cpuCores = cores
    let sampler = TaskSampler(inputs: inputs)
    inputs.list = [process(7, cpu: 1_000, gpu: 5, memory: memory)]
    sampler.sample(now: 10)
    let cpu = UInt64(busyCores * seconds * 1_000_000_000)
    let gpuTime = UInt64(gpu * seconds * 1_000_000_000)
    inputs.list = [process(7, cpu: 1_000 + cpu, gpu: 5 + gpuTime, memory: memory)]
    #expect(sampler.sample(now: 10 + seconds))
    return sampler.tasks.first
  }

  @Test(
    "CPU is the share of all the Mac's cores",
    arguments: [(1.0, "10.0%"), (4, "40.0%"), (10, "100.0%")])
  func cpuShare(busy: Double, shown: String) {
    #expect(TaskText.value(measure(cores: 10, busyCores: busy)?.cpu) == shown)
  }

  @Test("CPU is counted against the Mac it runs on", arguments: [8, 10, 16])
  func ownCores(cores: Int) {
    #expect(TaskText.value(measure(cores: cores, busyCores: Double(cores))?.cpu) == "100.0%")
    #expect(TaskText.value(measure(cores: cores, busyCores: Double(cores) / 2)?.cpu) == "50.0%")
  }

  @Test("no task's CPU is ever above a hundred percent")
  func capped() {
    #expect(TaskText.value(measure(cores: 10, busyCores: 12)?.cpu) == "100.0%")
  }

  @Test(
    "RAM is the share of the Mac's physical memory",
    arguments: [
      (6.4, "20.0%"), (16, "50.0%"), (32, "100.0%"),
    ])
  func ramShare(gigabytes: Double, shown: String) {
    let bytes = UInt64((gigabytes * Double(gib)).rounded())
    #expect(TaskText.value(measure(cores: 10, busyCores: 1, memory: bytes)?.ram) == shown)
  }

  @Test("GPU is the share of time the task kept the GPU busy")
  func gpuShare() {
    #expect(TaskText.value(measure(cores: 10, busyCores: 1, gpu: 0.123)?.gpu) == "12.3%")
  }

  @Test("a task first seen in this snapshot has no load yet and is left out")
  func newTask() {
    let inputs = FedTasks()
    let sampler = TaskSampler(inputs: inputs)
    inputs.list = [process(7)]
    #expect(!sampler.sample(now: 1))
    inputs.list = [process(7, cpu: 100), process(8, cpu: 100)]
    #expect(sampler.sample(now: 1.5))
    #expect(sampler.tasks.map(\.id.pid) == [7])
  }

  @Test("a reused process id is a new task: its old times are not carried over")
  func reusedPID() {
    let inputs = FedTasks()
    let sampler = TaskSampler(inputs: inputs)
    inputs.list = [process(7, started: 1, cpu: 5_000_000_000)]
    sampler.sample(now: 1)
    inputs.list = [process(7, started: 2, cpu: 10)]
    sampler.sample(now: 1.5)
    #expect(sampler.tasks.isEmpty)
  }

  @Test("snapshots too close together measure nothing; the earlier one is kept")
  func tooClose() {
    let inputs = FedTasks()
    let sampler = TaskSampler(inputs: inputs)
    inputs.list = [process(7)]
    sampler.sample(now: 1)
    inputs.list = [process(7, cpu: 1_000_000_000)]
    #expect(!sampler.sample(now: 1.1))
    #expect(sampler.sample(now: 1.5))
    #expect(TaskText.value(sampler.tasks.first?.cpu) == "20.0%")
  }

  @Test("each task is marked system by the rule, the meter's own row included")
  func marks() {
    let inputs = FedTasks()
    let sampler = TaskSampler(inputs: inputs)
    let list = [
      process(1, path: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"),
      process(2, uid: 0, path: nil),
      process(3, path: "/Users/me/.nvm/bin/node"),
      process(4242, path: "/Applications/Meter.app/Contents/MacOS/Meter"),
    ]
    inputs.list = list
    sampler.sample(now: 1)
    sampler.sample(now: 2)
    #expect(sampler.tasks.map(\.isSystem) == [true, true, false, true])
  }
}

@Suite("The row under the pointer holds (D100, D101)")
struct HoldTests {
  private let xcode = task("Xcode", cpu: 25, pid: 10)
  private let node = task("node", cpu: 20, pid: 11)

  @Test("the held row keeps its task, with its numbers updated, though another passes it")
  func holds() {
    let before = HeavyTasks.rank([task("a", cpu: 40), xcode, node])
    #expect(names(before) == ["a", "Xcode", "node"])
    var updatedXcode = xcode
    updatedXcode.cpu = Share(part: 26, whole: 100)
    var updatedNode = node
    updatedNode.cpu = Share(part: 30, whole: 100)
    let tasks = [task("a", cpu: 40), updatedXcode, updatedNode]
    let ranked = HeavyTasks.rank(tasks)
    #expect(names(ranked) == ["a", "node", "Xcode"])
    let held = HeavyTasks.holding(xcode.id, at: 1, tags: [], in: ranked, tasks: tasks)
    #expect(names(held) == ["a", "Xcode", "node"])
    #expect(held[1].task.cpu == Share(part: 26, whole: 100))
  }

  @Test("a held task that drops out of the five keeps its row; the lowest CPU row gives way")
  func droppedOut() {
    let tasks = [
      task("a", cpu: 50), task("b", cpu: 40), task("c", cpu: 30), task("d", cpu: 20),
      task("e", cpu: 10), task("held", cpu: 1, pid: 99),
    ]
    let ranked = HeavyTasks.rank(tasks)
    #expect(!names(ranked).contains("held"))
    let id = TaskID(pid: 99, started: 1)
    let held = HeavyTasks.holding(id, at: 2, tags: [], in: ranked, tasks: tasks)
    #expect(names(held) == ["a", "b", "held", "c", "d"])
  }

  @Test("a held task that has left the Mac holds nothing")
  func gone() {
    let ranked = HeavyTasks.rank([task("a", cpu: 40), node])
    let held = HeavyTasks.holding(xcode.id, at: 0, tags: [], in: ranked, tasks: [node])
    #expect(held == ranked)
  }

  @Test("with no hold the list re-ranks on every refresh")
  func noHold() {
    var faster = node
    faster.cpu = Share(part: 30, whole: 100)
    #expect(names(HeavyTasks.rank([xcode, faster])) == ["node", "Xcode"])
  }
}

@Suite("A task's values as its row shows them (D18, D19)")
struct TaskTextTests {
  @Test("one decimal place, a half rounding up, and a dash for no reading")
  func values() {
    #expect(TaskText.value(Share(part: 123, whole: 1000)) == "12.3%")
    #expect(TaskText.value(Share(part: 1, whole: 1)) == "100.0%")
    #expect(TaskText.value(Share(part: 0, whole: 1)) == "0.0%")
    #expect(TaskText.value(Share(part: 950, whole: 100_000)) == "1.0%")
    #expect(TaskText.value(Share(part: 949, whole: 100_000)) == "0.9%")
    #expect(TaskText.value(nil) == "\u{2013}")
  }
}
