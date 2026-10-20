import Foundation
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
  }

  @Test("a path that is empty or not absolute names no program: system (fail safe)")
  func relativePath() {
    #expect(isSystem(path: "System/Library/x"))
    #expect(isSystem(path: ""))
    #expect(isSystem(path: "loginwindow"))
    #expect(isSystem(path: "./Dock"))
    #expect(isSystem(path: "node"))
  }

  @Test("macOS's service folders /usr/libexec, /usr/sbin and /sbin are system (ruled 2026-10-20)")
  func serviceFolders() {
    #expect(isSystem(path: "/usr/libexec/trustd"))
    #expect(isSystem(path: "/usr/sbin/sharingd"))
    #expect(isSystem(path: "/sbin/launchd"))
    #expect(isSystem(path: "/USR/libexec/cfprefsd"))
    #expect(isSystem(path: "/usr/../sbin/x"))
  }

  @Test("/bin and /usr/bin stay the user's, and lookalikes of the service folders do not match")
  func commandFolders() {
    #expect(!isSystem(path: "/bin/zsh"))
    #expect(!isSystem(path: "/usr/bin/caffeinate"))
    #expect(!isSystem(path: "/usr/local/bin/node"))
    #expect(!isSystem(path: "/usr/local/sbin/x"))
    #expect(!isSystem(path: "/usr/libexecs/x"))
    #expect(!isSystem(path: "/usr/sbinx/x"))
    #expect(!isSystem(path: "/sbinx/x"))
    #expect(!isSystem(path: "/Users/me/usr/libexec/x"))
    #expect(!isSystem(path: "/Users/me/sbin/x"))
  }

  private let cryptex = "/System/Volumes/Preboot/Cryptexes/App"

  @Test("apps inside the App cryptex are normal apps: Safari and its helpers keep End")
  func appCryptex() {
    let safari = cryptex + "/System/Applications/Safari.app/Contents/MacOS/Safari"
    #expect(!isSystem(path: safari))
    #expect(
      !isSystem(
        path: cryptex + "/System/Applications/Safari.app/Contents/XPCServices/"
          + "com.apple.Safari.SandboxBroker.xpc/Contents/MacOS/com.apple.Safari.SandboxBroker"))
    #expect(
      !isSystem(
        path: cryptex + "/System/Applications/Safari.app/Contents/Extensions/"
          + "SafariLinkExtension.appex/Contents/MacOS/SafariLinkExtension"))
    #expect(!isSystem(path: cryptex.lowercased() + "/System/Applications/Safari.app/x"))
    #expect(
      !isSystem(
        path: "/Applications/Safari.app/Contents/MacOS/Safari",
        links: [
          "/Applications/Safari.app/Contents/MacOS/Safari": safari
        ]))
  }

  @Test("the cryptex's agents and other non-app programs stay system")
  func cryptexAgents() {
    #expect(isSystem(path: cryptex + "/usr/libexec/webpushd"))
    #expect(isSystem(path: cryptex + "/usr/libexec/AuthenticationServicesAgent"))
    #expect(isSystem(path: cryptex + "/usr/libexec/PasswordBreachAgent"))
    #expect(isSystem(path: cryptex + "/usr/bin/safaridriver"))
    #expect(isSystem(path: cryptex + "/System/Applications/Safari"))
    #expect(isSystem(path: cryptex + "/System/Library/CoreServices/Web App.app/x"))
    #expect(isSystem(path: cryptex + "/Library/Google/Chrome/Foo.app/x"))
    #expect(isSystem(path: cryptex + "/System/Applications/Foo.appx/Contents/MacOS/Foo"))
    #expect(isSystem(path: cryptex + "/System/Applications/Foo/Bar.app/x"))
    #expect(isSystem(path: cryptex + "/System/Applications/../Library/Foo.app/x"))
    #expect(
      isSystem(
        path: "/Applications/Fake",
        links: ["/Applications/Fake": cryptex + "/usr/libexec/webpushd"]))
  }

  @Test("no other /System path rides on the cryptex exception")
  func cryptexLookalikes() {
    let preboot = "/System/Volumes/Preboot"
    #expect(isSystem(path: cryptex))
    #expect(isSystem(path: cryptex + "s/System/Applications/Safari.app/x"))
    #expect(isSystem(path: preboot + "/Cryptexes/AppX/System/Applications/S.app/x"))
    #expect(isSystem(path: preboot + "/Cryptexes/OS/System/Applications/S.app/x"))
    #expect(isSystem(path: preboot + "/Cryptexes/App/../OS/System/Applications/S.app/x"))
    #expect(isSystem(path: preboot + "/Cryptexes/x/App/System/Applications/S.app/x"))
    #expect(isSystem(path: preboot + "/Other/Cryptexes/App/System/Applications/S.app/x"))
    #expect(isSystem(path: "/System/Volumes/Cryptexes/App/System/Applications/S.app/x"))
    // The link /System/Cryptexes/App is never a resolved path, so it earns no exception.
    #expect(isSystem(path: "/System/Cryptexes/App/System/Applications/Safari.app/x"))
    #expect(isSystem(path: "/System/Applications/Safari.app/x"))
    #expect(isSystem(path: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"))
    // A link out of the cryptex into /System proper is resolved first.
    #expect(
      isSystem(
        path: cryptex + "/System/Applications/Safari.app/link",
        links: [
          cryptex + "/System/Applications/Safari.app/link": "/System/Library/CoreServices/Dock"
        ]))
  }

  @Test("on this Mac, the real /Applications/Safari.app, resolved by realpath, is not system")
  func realSafari() throws {
    let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
    try #require(FileManager.default.fileExists(atPath: safari), "Safari is not installed")
    let real: (String) -> String? = { path in
      guard let resolved = realpath(path, nil) else { return nil }
      defer { free(resolved) }
      return String(cString: resolved)
    }
    #expect(
      !SystemTasks.isSystem(
        pid: 77, uid: 501, path: safari, userID: me, ownPID: meter, resolve: real))
    let agent = cryptex + "/usr/libexec/webpushd"
    if FileManager.default.fileExists(atPath: agent) {
      #expect(
        SystemTasks.isSystem(
          pid: 77, uid: 501, path: agent, userID: me, ownPID: meter, resolve: real))
    }
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
  var gpuTimes: [Int32: UInt64] = [:]
  var gpuBusy: Share?
  var cpuCores = 10
  var physicalMemory: UInt64 = 32 * gib
  var userID: UInt32 = 501
  var ownPID: Int32 = 4242
  func snapshot() -> TaskSnapshot? {
    list.map { TaskSnapshot(processes: $0, gpuTimes: gpuTimes, gpuBusy: gpuBusy) }
  }
  func resolve(path: String) -> String? { path }
}

private func process(
  _ pid: Int32, started: UInt64 = 1, cpu: UInt64 = 0, memory: UInt64 = 0,
  uid: UInt32 = 501, path: String? = "/Users/me/bin/task"
) -> ProcessSample {
  ProcessSample(
    id: TaskID(pid: pid, started: started), name: "task\(pid)", uid: uid, path: path,
    cpuTime: cpu, memory: memory)
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
    inputs.list = [process(7, cpu: 1_000, memory: memory)]
    inputs.gpuTimes = [7: 5]
    sampler.sample(now: 10)
    let cpu = UInt64(busyCores * seconds * 1_000_000_000)
    let gpuTime = UInt64(gpu * seconds * 1_000_000_000)
    inputs.list = [process(7, cpu: 1_000 + cpu, memory: memory)]
    inputs.gpuTimes = [7: 5 + gpuTime]
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

  @Test("with no busy figure from the GPU, a task's GPU is its own GPU time over the refresh")
  func gpuShare() {
    #expect(TaskText.value(measure(cores: 10, busyCores: 1, gpu: 0.123)?.gpu) == "12.3%")
  }

  /// Task 7's GPU after one refresh of half a second in which it used `task` ms of GPU time,
  /// WindowServer (another user's task, not in the list) `other` ms, and the GPU reported
  /// itself `busy` percent busy.
  private func gpu(task: UInt64, other: UInt64, busy: UInt64?) -> String {
    let inputs = FedTasks()
    let sampler = TaskSampler(inputs: inputs)
    inputs.gpuBusy = busy.flatMap { Share(part: $0, whole: 100) }
    inputs.list = [process(7)]
    inputs.gpuTimes = [7: 1_000, 423: 9_000]
    sampler.sample(now: 10)
    inputs.gpuTimes = [7: 1_000 + task * 1_000_000, 423: 9_000 + other * 1_000_000]
    sampler.sample(now: 10.5)
    return TaskText.value(sampler.tasks.first?.gpu)
  }

  @Test(
    "GPU is Activity Monitor's % GPU: the task's part of all clients' GPU time, of the GPU's busy figure",
    arguments: [
      // Light load: 50 ms of 500 is 10% of the time, yet the GPU says 30% busy and the task
      // took five sixths of its clients' time: 25.0%, as Activity Monitor reads it.
      (50, 10, 30, "25.0%"),
      // Heavy load: the GPU's figure and its clients' time agree.
      (400, 25, 85, "80.0%"),
      // Every client's time counts, the tasks the list cannot read included.
      (100, 100, 40, "20.0%"),
      (0, 100, 40, "0.0%"),
    ] as [(UInt64, UInt64, UInt64, String)])
  func gpuAsActivityMonitor(task: UInt64, other: UInt64, busy: UInt64, shown: String) {
    #expect(gpu(task: task, other: other, busy: busy) == shown)
  }

  @Test("a GPU with no client time over the refresh gives every task 0.0%")
  func gpuIdle() {
    #expect(gpu(task: 0, other: 0, busy: 7) == "0.0%")
  }

  @Test("a GPU client that closes does not count against the others")
  func gpuClientCloses() {
    let inputs = FedTasks()
    let sampler = TaskSampler(inputs: inputs)
    inputs.gpuBusy = Share(part: 50, whole: 100)
    inputs.list = [process(7)]
    inputs.gpuTimes = [7: 0, 423: 900_000_000]
    sampler.sample(now: 10)
    inputs.gpuTimes = [7: 100_000_000, 423: 0]
    sampler.sample(now: 10.5)
    #expect(TaskText.value(sampler.tasks.first?.gpu) == "50.0%")
  }

  @Test("the formula holds exactly at its rounding edge and never passes 100%")
  func gpuExact() {
    #expect(
      TaskText.value(
        GPUShare.of(task: 101, allClients: 1_000, busy: Share(part: 1, whole: 1), window: 1))
        == "10.1%")
    #expect(
      TaskText.value(
        GPUShare.of(task: 1_000, allClients: 1_000, busy: Share(part: 1, whole: 1), window: 1))
        == "100.0%")
    #expect(
      TaskText.value(
        GPUShare.of(
          task: UInt64.max / 2, allClients: UInt64.max / 2,
          busy: Share(part: 999_999, whole: 1_000_000),
          window: 1)) == "100.0%")
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
    let held = HeavyTasks.holding(xcode.id, at: 1, in: ranked, tasks: tasks)
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
    let held = HeavyTasks.holding(id, at: 2, in: ranked, tasks: tasks)
    #expect(names(held) == ["a", "b", "held", "c", "d"])
  }

  /// Five CPU rows, a GPU row and a RAM row; the pointer rests on the RAM row.
  private func crowded(ramHog: (String, Double), gpuHog: (String, Double)) -> [TaskUsage] {
    var tasks = [
      task("c1", cpu: 50), task("c2", cpu: 40), task("c3", cpu: 30), task("c4", cpu: 20),
      task("c5", cpu: 10),
    ]
    tasks.append(task("gpuHog", cpu: 0.5, gpu: 20))
    tasks.append(task("ramHog", cpu: 0.4, ram: 15))
    tasks.append(task(ramHog.0, cpu: 0.3, ram: ramHog.1))
    tasks.append(task(gpuHog.0, cpu: 0.2, gpu: gpuHog.1))
    return tasks
  }

  @Test("a held extra row that stops being a hog gives way: seven rows, no stale tag")
  func heldExtraRowStopsBeingAHog() {
    let before = HeavyTasks.rank(crowded(ramHog: ("other", 1), gpuHog: ("quiet", 0)))
    #expect(names(before) == ["c1", "c2", "c3", "c4", "c5", "gpuHog", "ramHog"])
    let held = before[6].task.id
    // The held task's RAM falls; `other` becomes the RAM hog.
    var tasks = crowded(ramHog: ("other", 12), gpuHog: ("quiet", 0))
    tasks = tasks.map {
      $0.name == "ramHog" ? task("ramHog", cpu: 0.4, ram: 1, pid: $0.id.pid) : $0
    }
    let rows = HeavyTasks.rank(tasks)
    #expect(names(rows) == ["c1", "c2", "c3", "c4", "c5", "gpuHog", "other"])
    let shown = HeavyTasks.holding(held, at: 6, in: rows, tasks: tasks)
    #expect(shown.count == 7)
    #expect(shown[6].task.id == held)
    #expect(shown[6].tags.isEmpty)
    #expect(shown.filter { $0.tags == [.ram] }.map(\.task.name) == ["other"])
    #expect(shown.filter { $0.tags == [.gpu] }.map(\.task.name) == ["gpuHog"])
  }

  @Test("the same for a held GPU row: seven rows, one row per tag, none stale")
  func heldGPURowStopsBeingAHog() {
    let before = HeavyTasks.rank(crowded(ramHog: ("quiet", 0), gpuHog: ("quiet2", 0)))
    let held = before[5].task.id
    var tasks = crowded(ramHog: ("quiet", 0), gpuHog: ("other", 30))
    tasks = tasks.map {
      $0.name == "gpuHog" ? task("gpuHog", cpu: 0.5, gpu: 1, pid: $0.id.pid) : $0
    }
    let rows = HeavyTasks.rank(tasks)
    let shown = HeavyTasks.holding(held, at: 5, in: rows, tasks: tasks)
    #expect(shown.count == 7)
    #expect(shown[5].task.id == held)
    #expect(shown[5].tags.isEmpty)
    #expect(shown.filter { $0.tags == [.gpu] }.map(\.task.name) == ["other"])
    #expect(shown.filter { $0.tags == [.ram] }.map(\.task.name) == ["ramHog"])
  }

  @Test("a held task that has left the Mac holds nothing")
  func gone() {
    let ranked = HeavyTasks.rank([task("a", cpu: 40), node])
    let held = HeavyTasks.holding(xcode.id, at: 0, in: ranked, tasks: [node])
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
