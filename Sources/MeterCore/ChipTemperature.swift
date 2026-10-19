/// The chip temperature from the die sensors macOS exposes to the signed-in user (D87).
public enum ChipTemperature {
  /// Die sensors are named like "PMU tdie3" and "PMU2 tdie10".
  public static func isDieSensor(_ name: String) -> Bool {
    name.hasPrefix("PMU") && name.contains(" tdie")
  }

  /// A believable die temperature. Anything outside is a failed read, shown as a dash.
  public static let plausible: ClosedRange<Double> = 1...150

  /// The hottest die sensor, in whole degrees Celsius; nil when no die sensor reads sensibly.
  public static func celsius(sensors: [String: Double]) -> Int? {
    let dies = sensors.filter { isDieSensor($0.key) && plausible.contains($0.value) }
    guard let hottest = dies.values.max() else { return nil }
    return Rounding.wholeNumber(hottest)
  }
}
