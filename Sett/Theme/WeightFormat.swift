import Foundation
import SettCore

/// Compact weight strings, app-wide: "147.5", "140" — never "147.50" or "140.".
/// Wraps `Units.displayValue` (0.25-step display rounding) and strips the noise
/// `%.2f` leaves behind, so set rows / steppers / chips all read the same.
enum WeightFormat {
    /// "147.5", "140" — display value with trailing zeros (and a trailing '.') stripped.
    static func compact(grams: Int, unit: WeightUnit) -> String {
        let value = Units.displayValue(grams: grams, unit: unit)
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// "147.5 lb", "140 kg".
    static func compactWithUnit(grams: Int, unit: WeightUnit) -> String {
        "\(compact(grams: grams, unit: unit)) \(unit.symbol)"
    }
}
