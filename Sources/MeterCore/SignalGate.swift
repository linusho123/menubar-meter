/// The last look before a signal goes out.
public enum SignalGate {
  /// Whether `id` may be signalled now: not process 0 or 1 (never a process group, a broadcast
  /// or launchd), and the task under its process id, as `startTime` reads it this moment, is
  /// the one started at `id.started`.
  public static func mayDeliver(_ id: TaskID, startTime: (Int32) -> UInt64?) -> Bool {
    guard id.pid > 1, let started = startTime(id.pid) else { return false }
    return started == id.started
  }
}
