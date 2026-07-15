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

    /// Big-tonnage readout: exact integer until 10,000, then "12.4k". Used by the
    /// history summary and the weekly net strip — kept off `Units.displayValue`'s
    /// 0.25-step rounding so a raw sum reads true.
    static func compactTonnage(grams: Int, unit: WeightUnit) -> String {
        let value = Double(grams) / unit.gramsPerUnit
        return value >= 10_000 ? "\((value / 1000).formatted(.number.precision(.fractionLength(1))))k"
                               : Int(value.rounded()).formatted()
    }
}
