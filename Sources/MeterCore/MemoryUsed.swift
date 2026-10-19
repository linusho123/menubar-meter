/// The page counts the kernel reports (the fields `vm_stat` prints).
public struct MemoryPages: Equatable, Sendable {
  /// Anonymous pages (`internal_page_count`): app memory plus purgeable.
  public var anonymous: UInt64
  /// Purgeable pages: reusable cache, not app memory.
  public var purgeable: UInt64
  /// Wired pages.
  public var wired: UInt64
  /// Pages occupied by the compressor.
  public var compressed: UInt64
  /// File-backed pages: reusable cache.
  public var fileBacked: UInt64

  public init(
    anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64, fileBacked: UInt64
  ) {
    self.anonymous = anonymous
    self.purgeable = purgeable
    self.wired = wired
    self.compressed = compressed
    self.fileBacked = fileBacked
  }
}

/// Activity Monitor's Memory Used: App Memory + Wired Memory + Compressed, with the
/// reusable cache (file-backed and purgeable pages) left out (D47).
public enum MemoryUsed {
  public static func bytes(_ pages: MemoryPages, pageSize: UInt64) -> UInt64 {
    let appMemory = pages.anonymous - min(pages.purgeable, pages.anonymous)
    return (appMemory + pages.wired + pages.compressed) * pageSize
  }

  /// Memory Used as a whole percentage of the Mac's physical memory.
  public static func percent(_ pages: MemoryPages, pageSize: UInt64, physicalMemory: UInt64)
    -> Int?
  {
    Rounding.wholePercent(part: bytes(pages, pageSize: pageSize), whole: physicalMemory)
  }
}
