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
  public static let width: Double = 384
  public static let margin: Double = 12
  public static let scaleWidth: Double = 34
  public static let plotHeight: Double = 120
  /// The gap between the scale and the graph.
  public static let scaleGap: Double = 6
  /// The graph's width: the panel less its margins, the scale on its left and the gap after it.
  public static var plotWidth: Double { width - 2 * margin - scaleWidth - scaleGap }
}
