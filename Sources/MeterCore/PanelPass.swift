/// What the panel does with a pass of the engine (or with a request to redraw), given whether it is
/// open. Held in MeterCore so a test can pin it: while the panel is closed, a pass forgets the
/// ending state of each task that has gone and draws nothing (D40, P4's head review); deleting that
/// call from the controller leaves an empty case, which does not compile.
public enum PanelPass: Equatable {
  /// Closed, and a pass has run: forget the tasks that have gone, ask nothing else, draw nothing.
  case forgetGone
  /// Redraw the graph and the legend as of `at`; nil means the engine's latest.
  case redraw(at: Double?)

  /// `now` is the pass that just ran; nil means a redraw at the engine's latest reading (the panel
  /// has just opened).
  public static func plan(isOpen: Bool, now: Double?) -> PanelPass {
    guard isOpen || now == nil else { return .forgetGone }
    return .redraw(at: now)
  }
}
