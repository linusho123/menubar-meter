/// The size of the bitmap the panel's graph is painted into, in pixels.
public struct BitmapSize: Equatable, Sendable {
  public var width: Int
  public var height: Int
  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  /// Bytes the bitmap holds: four a pixel.
  public var bytes: Int { width * height * 4 }
}

/// How the panel's graph bitmap is sized and when it is allocated afresh (D76, P7). Painted in
/// `draw(_:)` the graph cost about 45 MB of graphics memory; painted into one bitmap kept while the
/// view's size and scale stay the same, it costs this much and no more.
public enum GraphBitmap {
  public static func pixels(points: Double, scale: Double) -> Int {
    Int((points * scale).rounded())
  }

  public static func size(width: Double, height: Double, scale: Double) -> BitmapSize {
    BitmapSize(
      width: pixels(points: width, scale: scale), height: pixels(points: height, scale: scale))
  }

  /// Whether a bitmap of size `old` (nil: none yet) must be replaced by one of `new`: when there is
  /// none, or its size differs. The same size and scale reuse the bitmap.
  public static func needsNew(old: BitmapSize?, new: BitmapSize) -> Bool {
    old != new
  }
}

/// The panel's fixed layout in points, shared with the controller so a test can size the graph.
public enum PanelLayout {
  /// The panel is exactly as wide as the menu bar item it drops down from; this is the item's
  /// width at the standard menu bar font (13 pt).
  public static let nominalWidth: Double = 296
  public static let margin: Double = 6
  /// The room inside each of the panel's tiles, around what it holds.
  public static let tilePadding: Double = 8
  public static let scaleWidth: Double = 32
  public static let plotHeight: Double = 120
  /// The gap between the scale and the graph.
  public static let scaleGap: Double = 6
  /// The width inside a tile, for a panel `width` wide.
  public static func innerWidth(panel width: Double) -> Double {
    width - 2 * margin - 2 * tilePadding
  }
  /// The graph's width: the inside of its tile less the scale on its left and the gap after it.
  public static func plotWidth(panel width: Double) -> Double {
    innerWidth(panel: width) - scaleWidth - scaleGap
  }
}
