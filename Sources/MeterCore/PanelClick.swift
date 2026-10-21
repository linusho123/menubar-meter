/// What the panel does when the user clicks the End, or Force Quit, button of a row.
public enum PanelClick {
  /// Presses the row's button. A click on a row whose task was replaced or has gone sends
  /// nothing, and the list is measured afresh at once, past the sampler's minimum interval
  /// (the visionary's ruling 2026-10-20, Q4). Returns whether the list was measured afresh,
  /// so the panel redraws it.
  @discardableResult
  public static func end(
    _ id: TaskID, ender: TaskEnder, sampler: TaskSampler, now: Double
  ) -> Bool {
    guard ender.press(id, now: now) == .stale else { return false }
    return sampler.sample(now: now, force: true)
  }
}
