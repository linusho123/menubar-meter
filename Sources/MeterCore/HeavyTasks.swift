/// Why a row beyond the five CPU rows is listed: the plain tag it carries (D108, D110).
public enum RowTag: Equatable, Sendable {
  case gpu
  case ram

  public var text: String {
    switch self {
    case .gpu: "GPU"
    case .ram: "RAM"
    }
  }
}

/// One row of the heavy-tasks list.
public struct HeavyRow: Equatable, Sendable {
  public var task: TaskUsage
  /// Empty for the five CPU rows; `GPU` or `RAM` for an extra row.
  public var tags: [RowTag]

  public init(task: TaskUsage, tags: [RowTag]) {
    self.task = task
    self.tags = tags
  }

  /// The words the row carries beyond its name and values (D110): its reason tags, then
  /// `system` where a task has no End button (D99, D57).
  public var words: [String] {
    tags.map(\.text) + (task.isSystem ? [HeavyTasks.systemTag] : [])
  }
}

/// The heavy-tasks list (D108, D109, D58, D100): the top five by CPU, then the biggest GPU user
/// and the biggest RAM user when either is a real hog and not already among the five.
public enum HeavyTasks {
  public static let cpuRows = 5
  public static let systemTag = "system"

  /// The list, in order: five rows by CPU, ties broken alphabetically by name, then the GPU
  /// row, then the RAM row. A task measured with no CPU load is not ranked.
  public static func rank(_ tasks: [TaskUsage]) -> [HeavyRow] {
    let byCPU = tasks.filter { $0.cpu != nil }.sorted(by: higherCPU)
    var rows = byCPU.prefix(cpuRows).map { HeavyRow(task: $0, tags: []) }
    let listed = Set(rows.map(\.task.id))
    for (tag, value) in [(RowTag.gpu, \TaskUsage.gpu), (RowTag.ram, \TaskUsage.ram)] {
      guard let biggest = biggest(tasks, by: value), !listed.contains(biggest.id),
        let share = biggest[keyPath: value], isHog(share)
      else { continue }
      if let index = rows.firstIndex(where: { $0.task.id == biggest.id }) {
        rows[index].tags.append(tag)
      } else {
        rows.append(HeavyRow(task: biggest, tags: [tag]))
      }
    }
    return rows
  }

  /// A real hog uses over a tenth of the GPU or of the Mac's memory (D109): exactly a tenth is
  /// not over it.
  public static func isHog(_ share: Share) -> Bool {
    let (tenTimes, overflow) = share.part.multipliedReportingOverflow(by: 10)
    return overflow || tenTimes > share.whole
  }

  /// The order of the CPU rows: the higher CPU value as the user reads it (to one decimal)
  /// first; a tie goes to the name that comes first in the alphabet (D58).
  public static func higherCPU(_ a: TaskUsage, _ b: TaskUsage) -> Bool {
    let left = a.cpu?.tenthsOfPercent ?? -1
    let right = b.cpu?.tenthsOfPercent ?? -1
    if left != right { return left > right }
    return alphabetically(a, b)
  }

  /// Name order, ignoring case, then the exact name, then the process id, so the order is
  /// always the same for the same tasks.
  public static func alphabetically(_ a: TaskUsage, _ b: TaskUsage) -> Bool {
    let left = a.name.lowercased()
    let right = b.name.lowercased()
    if left != right { return left < right }
    if a.name != b.name { return a.name < b.name }
    return a.id.pid < b.id.pid
  }

  /// The task using the most of `value`, ties broken alphabetically.
  public static func biggest(_ tasks: [TaskUsage], by value: KeyPath<TaskUsage, Share?>)
    -> TaskUsage?
  {
    var best: TaskUsage?
    var bestFraction = -1.0
    for task in tasks {
      guard let share = task[keyPath: value] else { continue }
      let fraction = Double(share.part) / Double(share.whole)
      let tiedEarlier = fraction == bestFraction && best.map { alphabetically(task, $0) } == true
      if fraction > bestFraction || tiedEarlier {
        best = task
        bestFraction = fraction
      }
    }
    return best
  }

  /// The list as shown while the pointer rests on the End button of row `index` (D100, D101):
  /// that row keeps the task `held`, with its numbers updated from `tasks`, and every other row
  /// takes its place in rank order around it. A held task that has left the Mac holds nothing.
  public static func holding(
    _ held: TaskID, at index: Int, tags: [RowTag], in rows: [HeavyRow], tasks: [TaskUsage]
  ) -> [HeavyRow] {
    var shown = rows
    let row: HeavyRow
    if let current = shown.firstIndex(where: { $0.task.id == held }) {
      row = shown.remove(at: current)
    } else if let task = tasks.first(where: { $0.id == held }) {
      row = HeavyRow(task: task, tags: tags)
      // It has dropped out of the list: the lowest CPU row gives up its place for it.
      if tags.isEmpty, let last = shown.lastIndex(where: { $0.tags.isEmpty }),
        shown.filter({ $0.tags.isEmpty }).count >= cpuRows
      {
        shown.remove(at: last)
      }
    } else {
      return rows
    }
    shown.insert(row, at: min(max(0, index), shown.count))
    return shown
  }
}

/// A task's value as its row shows it (D18, D19): one decimal place and a percent sign, or a
/// dash when there is no reading.
public enum TaskText {
  public static func value(_ share: Share?) -> String {
    guard let share else { return ReadoutText.dash }
    return Legend.oneDecimal(share.tenthsOfPercent) + "%"
  }
}
