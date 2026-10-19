/// What the menu bar item shows: whole numbers, or nil for a dash.
public struct Readout: Equatable, Sendable {
  public var cpu: Int?
  public var gpu: Int?
  public var ram: Int?
  public var temperature: Int?

  public init(cpu: Int?, gpu: Int?, ram: Int?, temperature: Int?) {
    self.cpu = cpu
    self.gpu = gpu
    self.ram = ram
    self.temperature = temperature
  }
}

/// The menu bar text: CPU, GPU, RAM, then the temperature, each number right-aligned in a
/// slot three digits wide so the labels, percent signs and degree sign never move (D89, D90).
public enum ReadoutText {
  public static let dash = "\u{2013}"
  public static let slotWidth = 3

  public static func text(_ readout: Readout) -> String {
    "CPU \(slot(readout.cpu))%  GPU \(slot(readout.gpu))%  RAM \(slot(readout.ram))%  "
      + "\(slot(readout.temperature))°C"
  }

  /// The widest text the item can ever show; the item's fixed width is measured from it.
  public static let widest = text(Readout(cpu: 100, gpu: 100, ram: 100, temperature: 888))

  /// A number right-aligned in three character cells, or a dash in the same cells.
  public static func slot(_ value: Int?) -> String {
    let shown: String
    if let value, (0...999).contains(value) {
      shown = String(value)
    } else {
      shown = dash
    }
    return String(repeating: " ", count: max(0, slotWidth - shown.count)) + shown
  }
}
