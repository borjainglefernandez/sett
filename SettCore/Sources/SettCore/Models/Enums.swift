import Foundation

// MARK: - Units

public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kg, lb

    /// Grams per one display unit.
    public var gramsPerUnit: Double { self == .kg ? 1000.0 : 453.59237 }

    /// Default plate increment expressed in grams (1.25 kg / 2.5 lb).
    public var defaultIncrementGrams: Int { self == .kg ? 1250 : 1134 }

    public var symbol: String { rawValue }
}

public enum Muscle: String, Codable, Sendable, CaseIterable {
    case chest, triceps, biceps, shoulders, back, legs, core, other
}

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case dumbbell, barbell, cable, machine, bodyweight

    public var symbolName: String {
        switch self {
        case .dumbbell: "dumbbell.fill"
        case .barbell: "figure.strengthtraining.traditional"
        case .cable: "cable.connector"
        case .machine: "gearshape.2.fill"
        case .bodyweight: "figure.core.training"
        }
    }
}

// MARK: - Goals

public enum GoalKind: String, Codable, Sendable, CaseIterable {
    /// N qualifying-workout days per ISO week. targetValue = days/week.
    case frequency
    /// Verified e1RM target on one exercise. targetValue = grams.
    case prTarget = "pr_target"
    /// Effective tonnage in a window. targetValue = grams·reps (volume load in grams).
    case volumeTarget = "volume_target"
}

// MARK: - Insights

public enum InsightKind: String, Codable, Sendable {
    case postWorkout, weeklyDigest
}

public enum InsightSource: String, Codable, Sendable {
    case onDevice, server, fallbackTemplate
}

// MARK: - Progression

public enum BadgeRarity: String, Codable, Sendable, CaseIterable {
    case bronze, silver, gold, legendary
}

public enum CharacterKey: String, Codable, Sendable, CaseIterable {
    case vego      // the Ember Prince — main, receives workout XP (the Proud Prince)
    case gosi      // the Bottomless (the Cheerful Powerhouse) — breadth & dawn
    case barok     // the Mountain (the Legendary Giant) — volume & tonnage
    case nyra      // Nyra Voss (the Tireless Android) — streaks & consistency
    case torren    // Torren Vex (the Stern Mentor) — goals & adherence
    case zia       // Zia Q. (the Genius Engineer) — sleep & recovery
    case zyn       // the Hidden-Power Kid — comebacks, night training, momentum

    public var displayName: String {
        switch self {
        case .vego: "Vego, the Ember Prince"
        case .gosi: "Gosi, the Bottomless"
        case .barok: "Barok the Mountain"
        case .nyra: "Nyra Voss"
        case .torren: "Torren Vex"
        case .zia: "Zia Q."
        case .zyn: "Zyn"
        }
    }
}

/// Transformation tiers inside the Hypertrophic Time Chamber.
public enum TransformationTier: Int, Codable, Sendable, CaseIterable, Comparable {
    case base = 0, kindled, ascendant, radiant, zenith

    public var displayName: String {
        switch self {
        case .base: "Base"
        case .kindled: "Kindled"
        case .ascendant: "Ascendant"
        case .radiant: "Radiant"
        case .zenith: "Zenith"
        }
    }

    /// Time-dilation flavor: "a year of gains in a day" at Zenith.
    public var dilation: Int {
        switch self {
        case .base: 1
        case .kindled: 7
        case .ascendant: 30
        case .radiant: 120
        case .zenith: 365
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Unit helpers

public enum Units {
    public static let gramsPerPound = 453.59237

    public static func pounds(fromGrams grams: Int) -> Double {
        Double(grams) / gramsPerPound
    }

    /// Round grams to the nearest displayable step of the given unit (0.25 kg / 0.25 lb granularity for display round-trips).
    public static func displayValue(grams: Int, unit: WeightUnit) -> Double {
        let raw = Double(grams) / unit.gramsPerUnit
        return (raw * 4).rounded() / 4
    }

    public static func grams(fromDisplay value: Double, unit: WeightUnit) -> Int {
        Int((value * unit.gramsPerUnit).rounded())
    }
}
