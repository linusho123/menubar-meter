import Testing

@testable import MeterCore

@Suite("the panel's graph bitmap")
struct GraphBitmapTests {
  /// The graph's width in a panel as wide as the item at the standard menu bar font.
  private static let plotWidth = PanelLayout.plotWidth(panel: PanelLayout.nominalWidth)
  private let plot = GraphBitmap.size(
    width: Self.plotWidth, height: PanelLayout.plotHeight, scale: 2)

  @Test("the same size and scale reuse the bitmap")
  func reuses() {
    let again = GraphBitmap.size(
      width: Self.plotWidth, height: PanelLayout.plotHeight, scale: 2)
    #expect(!GraphBitmap.needsNew(old: plot, new: again))
  }

  @Test("the first paint, a size change and a scale change allocate afresh")
  func reallocates() {
    #expect(GraphBitmap.needsNew(old: nil, new: plot))
    let wider = GraphBitmap.size(
      width: Self.plotWidth + 1, height: PanelLayout.plotHeight, scale: 2)
    #expect(GraphBitmap.needsNew(old: plot, new: wider))
    let retina1x = GraphBitmap.size(
      width: Self.plotWidth, height: PanelLayout.plotHeight, scale: 1)
    #expect(GraphBitmap.needsNew(old: plot, new: retina1x))
  }

  @Test("the graph at 2x is 460 by 240 pixels and under 1 MB")
  func underOneMegabyte() {
    #expect(plot == BitmapSize(width: 460, height: 240))
    #expect(plot.bytes < 1_048_576)
    // At 3x it is still under 2 MB: nothing grows with time.
    #expect(
      GraphBitmap.size(width: Self.plotWidth, height: PanelLayout.plotHeight, scale: 3).bytes
        < 2 * 1_048_576)
  }

  @Test("pixels round points times scale")
  func rounding() {
    #expect(GraphBitmap.pixels(points: 320, scale: 2) == 640)
    #expect(GraphBitmap.pixels(points: 100.4, scale: 1) == 100)
    #expect(GraphBitmap.pixels(points: 100.5, scale: 1) == 101)
  }
}
