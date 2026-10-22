import Testing

@testable import MeterCore

@Suite("what the panel does with a pass")
struct PanelPassTests {
  @Test("closed, a pass forgets the tasks that have gone and draws nothing")
  func closedForgets() {
    #expect(PanelPass.plan(isOpen: false, now: 12.5) == .forgetGone)
  }

  @Test("open, a pass redraws as of that pass")
  func openRedraws() {
    #expect(PanelPass.plan(isOpen: true, now: 12.5) == .redraw(at: 12.5))
  }

  @Test("a redraw with no pass (the panel just opened) uses the engine's latest, open or not")
  func noPassRedraws() {
    #expect(PanelPass.plan(isOpen: true, now: nil) == .redraw(at: nil))
    #expect(PanelPass.plan(isOpen: false, now: nil) == .redraw(at: nil))
  }
}
