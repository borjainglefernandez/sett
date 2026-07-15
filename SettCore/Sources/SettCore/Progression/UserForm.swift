import Foundation

// MARK: - Transformation Forms (the USER's endless ladder — pure function of PL)

/// The user-level transformation ladder that replaces per-character tiers as the
/// headline progression: fixed Power-Level thresholds up to Zenith, then an ENDLESS
/// run of Zenith II, III, … every 7,500 PL — there is always a next form.
///
/// Thresholds: Base 0 → Kindled 2,000 → Ascendant 5,000 → Radiant 9,000 (the
/// "over 9000" beat, aligned with the Scanner-Breaker badge) → Zenith 15,000 →
/// Zenith II 22,500 → +7,500 each thereafter.
public struct UserForm: Equatable, Sendable {
    /// 0-based rung on the ladder (Base = 0).
    public let index: Int
    /// Display name — "KINDLED", "ZENITH II", …
    public let title: String
    /// The PL floor of this form.
    public let floorPL: Int
    /// The PL that unlocks the next form. Never nil — the ladder is endless.
    public let nextPL: Int

    public static let namedThresholds: [(title: String, floor: Int)] = [
        ("BASE", 0),
        ("KINDLED", 2_000),
        ("ASCENDANT", 5_000),
        ("RADIANT", 9_000),
        ("ZENITH", 15_000),
    ]
    public static let zenithStep = 7_500

    /// The form a given Power Level currently holds.
    public static func form(forPL pl: Int) -> UserForm {
        let pl = max(0, pl)
        // Named rungs first.
        for (offset, entry) in namedThresholds.enumerated().reversed() {
            if pl >= entry.floor {
                if offset == namedThresholds.count - 1 {
                    // At or past Zenith — roll into the endless Zenith II, III, … run.
                    let over = pl - entry.floor
                    let extra = over / zenithStep
                    let floorPL = entry.floor + extra * zenithStep
                    return UserForm(index: offset + extra,
                                    title: extra == 0 ? entry.title
                                                      : "\(entry.title) \(roman(extra + 1))",
                                    floorPL: floorPL,
                                    nextPL: floorPL + zenithStep)
                }
                return UserForm(index: offset,
                                title: entry.title,
                                floorPL: entry.floor,
                                nextPL: namedThresholds[offset + 1].floor)
            }
        }
        return UserForm(index: 0, title: "BASE", floorPL: 0, nextPL: namedThresholds[1].floor)
    }

    /// Progress through the current form, 0…1.
    public var progress: (Int) -> Double {
        { pl in
            let span = Double(nextPL - floorPL)
            guard span > 0 else { return 0 }
            return min(1, max(0, Double(pl - floorPL) / span))
        }
    }

    /// II, III, IV … (no form ever needs more than a handful of numerals, but the
    /// subtractive rule is cheap to do right).
    static func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
                                      (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
                                      (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, out = ""
        for (value, glyph) in table {
            while n >= value {
                out += glyph
                n -= value
            }
        }
        return out
    }
}
