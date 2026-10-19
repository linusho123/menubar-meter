import Foundation

/// The menu bar text: `CPU 100%  GPU   7%  RAM  93%   98°C`. Each number is
/// a whole number, right-aligned in a slot three characters wide; a reading
/// with nothing fresh for three seconds shows a dash in its slot.
public enum Readout {
    /// A reading older than this shows as a dash: with one pass a second,
    /// the third missed pass is the first to see it this old.
    public static let staleAfter: TimeInterval = 2.5
    public static let dash = "–"

    /// The widest text the item can ever show; the item's fixed width is
    /// sized to it.
    public static let widest = "CPU 100%  GPU 100%  RAM 100%  105°C"

    public static func text(cpu: Reading?, gpu: Reading?, ram: Reading?,
                            temperature: Reading?, now: Date) -> String {
        "CPU \(slot(cpu, now, 0...100))%  GPU \(slot(gpu, now, 0...100))%  "
            + "RAM \(slot(ram, now, 0...100))%  \(slot(temperature, now, -99...999))°C"
    }

    /// Nearest whole number, a half rounding up.
    public static func whole(_ v: Double) -> Int {
        Int((v + 0.5).rounded(.down))
    }

    static func slot(_ r: Reading?, _ now: Date, _ range: ClosedRange<Int>) -> String {
        guard let r, now.timeIntervalSince(r.at) < staleAfter, r.value.isFinite else {
            return pad(dash)
        }
        return pad(String(min(max(whole(r.value), range.lowerBound), range.upperBound)))
    }

    static func pad(_ s: String) -> String {
        String(repeating: " ", count: max(0, 3 - s.count)) + s
    }
}
