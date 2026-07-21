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
    /// `.legs` is a LEGACY case: old rows decode, but new pickers hide it — the
    /// lower body now splits into glutes / hamstrings / quadriceps / calves so
    /// weekly volume landmarks can be honest per group (a "legs day" that is all
    /// squats is zero hamstring sets, and the chart should say so).
    case chest, triceps, biceps, shoulders, back, legs, core, other
    case glutes, hamstrings, quadriceps, calves
}

extension Muscle {
    /// Human-readable name for detail rows and pickers.
    public var displayName: String {
        switch self {
        case .chest: "Chest"
        case .triceps: "Triceps"
        case .biceps: "Biceps"
        case .shoulders: "Shoulders"
        case .back: "Back"
        case .legs: "Legs (legacy)"
        case .core: "Core"
        case .other: "Other"
        case .glutes: "Glutes"
        case .hamstrings: "Hamstrings"
        case .quadriceps: "Quadriceps"
        case .calves: "Calves"
        }
    }

    /// Mono chip label — short enough for the tightest chips, so the split
    /// groups abbreviate ("QUADS", "HAMS") while the rest stay full.
    public var shortLabel: String {
        switch self {
        case .quadriceps: "QUADS"
        case .hamstrings: "HAMS"
        default: rawValue.uppercased()
        }
    }

    /// The ten muscle groups that carry weekly volume landmarks, in the order
    /// the Progress charts render them (big pushers first, lower body split last).
    /// `.legs` (legacy) and `.other` are deliberately absent — neither has a
    /// defensible evidence-based landmark.
    public static let volumeGroups: [Muscle] = [
        .chest, .back, .shoulders, .biceps, .triceps, .core,
        .quadriceps, .hamstrings, .glutes, .calves,
    ]

    /// Every case that fills the single lower-body STRENGTH bucket. The legacy
    /// `.legs` rides along so pre-split history scores identically to re-tagged
    /// history — PL stability is sacred.
    public static let lowerBody: Set<Muscle> = [
        .legs, .glutes, .hamstrings, .quadriceps, .calves,
    ]
}

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case dumbbell, barbell, cable, machine, bodyweight

    /// SF-symbol fallback for contexts that can't render custom views (Menus, Labels).
    /// The app's own surfaces draw `EquipmentGlyph` instead — SF has no real gym gear
    /// (the old picks read as a power plug and a pair of gears).
    public var symbolName: String {
        switch self {
        case .dumbbell: "dumbbell.fill"
        case .barbell: "figure.strengthtraining.traditional"
        case .cable: "point.topleft.down.curvedto.point.bottomright.up.fill"
        case .machine: "square.stack.3d.up.fill"
        case .bodyweight: "figure.core.training"
        }
    }
}

// MARK: - Training phase (cut / bulk / maintain)

/// The lens the app scores a session through. It changes the reward FRAME, not the
/// e1RM engine: a cut celebrates RETAINING strength (a realistic dip is not a
/// failure), a bulk expects growth, maintenance targets the flat line. Stamped
/// onto each Workout at start so history stays honestly phase-attributed.
public enum TrainingPhase: String, Codable, Sendable, CaseIterable, Identifiable {
    case cutting, bulking, maintaining

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cutting: "Cutting"
        case .bulking: "Bulking"
        case .maintaining: "Maintaining"
        }
    }

    /// The one-line creed shown on the phase badge / picker.
    public var creed: String {
        switch self {
        case .cutting: "Defend the ceiling"
        case .bulking: "Break the ceiling"
        case .maintaining: "Hold at altitude"
        }
    }

    public var symbolName: String {
        switch self {
        case .cutting: "arrow.down.right.circle.fill"
        case .bulking: "arrow.up.right.circle.fill"
        case .maintaining: "equal.circle.fill"
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
    case luma      // Luma Q. (the Genius Engineer) — sleep & recovery
    case zyn       // the Hidden-Power Kid — comebacks, night training, momentum

    public var displayName: String {
        switch self {
        case .vego: "Vego, the Ember Prince"
        case .gosi: "Gosi, the Bottomless"
        case .barok: "Barok the Mountain"
        case .nyra: "Nyra Voss"
        case .torren: "Torren Vex"
        case .luma: "Luma Q."
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
