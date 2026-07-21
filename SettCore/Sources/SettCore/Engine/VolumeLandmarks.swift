import Foundation

// MARK: - Weekly hard-set volume landmarks

/// Evidence-based WEEKLY hard-set landmarks per muscle group, for the Progress
/// charts: the floor a group needs to grow at all, the sweet spot most lifters
/// should live in, and the ceiling past which added sets are junk volume /
/// unrecoverable fatigue. Counted in hard WORKING sets per week; a compound
/// counts one set for each PRIME MOVER it trains (a squat is a quad set, not a
/// quad + glute + hamstring set).
///
/// Sources (the numbers are a synthesis, not a single table):
///  • Schoenfeld, Ogborn & Krieger 2017 (dose–response meta): clear volume
///    dose–response, 10+ weekly sets outgrow <5.
///  • Schoenfeld et al. 2019 (three-arm trial behind the 2019 position):
///    gains still rising into the teens for chest/quads in trained lifters.
///  • Baz-Valle et al. 2022 (systematic review): 12–20 weekly sets as the
///    pragmatic hypertrophy band, diminishing returns past ~20.
///  • Pelland, Remmert et al. 2024–25 meta-regressions: the marginal gain per
///    set keeps shrinking but stays positive far out, so the ceiling here is a
///    RECOVERY line, not a growth cliff.
///  • Current Renaissance Periodization MEV/MRV tables: per-muscle floors and
///    ceilings, notably the deliberately LOW hamstring numbers (hinge work
///    carries outsized per-set fatigue) and low maintenance doses everywhere.
///
/// NON-TOXIC framing: the floor is "where growth starts", never a shame line —
/// under-volume renders ash, and past the ceiling reads as recovery guidance.
public struct VolumeLandmarks: Sendable, Hashable {
    /// Minimum weekly hard sets for measurable growth (≈ MEV).
    public let floor: Int
    /// Lower edge of the sweet spot most lifters should occupy.
    public let sweetLow: Int
    /// Upper edge of the sweet spot — past here, returns thin out fast.
    public let sweetHigh: Int
    /// Junk-volume / recovery line (≈ MRV) — more sets, not more muscle.
    public let ceiling: Int
    /// Weekly sets that HOLD existing size (deload / life-happens weeks).
    public let maintenance: Int

    public init(floor: Int, sweetLow: Int, sweetHigh: Int, ceiling: Int, maintenance: Int) {
        self.floor = floor
        self.sweetLow = sweetLow
        self.sweetHigh = sweetHigh
        self.ceiling = ceiling
        self.maintenance = maintenance
    }

    /// Past ~10 hard sets for one muscle in one session, extra sets mostly add
    /// fatigue, not stimulus (RP per-session guidance) — the charts use this to
    /// nudge splitting a group across days rather than cramming one.
    public static let perSessionMax = 10

    /// Whole-body weekly range: below ~60 total hard sets a full split is
    /// under-fed; past ~100 most lifters are outrunning recovery.
    public static let weeklyTotalRange: ClosedRange<Int> = 60...100

    /// Landmarks for a muscle group, nil for `.other` and legacy `.legs` —
    /// neither is a real trainable group, so charts skip them rather than
    /// invent numbers.
    public static func landmarks(for muscle: Muscle) -> VolumeLandmarks? {
        switch muscle {
        case .chest:
            VolumeLandmarks(floor: 6, sweetLow: 10, sweetHigh: 16, ceiling: 20, maintenance: 4)
        case .back:
            // Highest band: back tolerates (and needs) the most volume — rows +
            // pulldowns spread load across a large musculature.
            VolumeLandmarks(floor: 8, sweetLow: 12, sweetHigh: 18, ceiling: 22, maintenance: 6)
        case .shoulders:
            // Delts recover fast (isolation-friendly), hence the high ceiling.
            VolumeLandmarks(floor: 6, sweetLow: 10, sweetHigh: 16, ceiling: 22, maintenance: 4)
        case .biceps:
            VolumeLandmarks(floor: 6, sweetLow: 10, sweetHigh: 16, ceiling: 20, maintenance: 4)
        case .triceps:
            // Slightly lower than biceps: every press already half-trains them.
            VolumeLandmarks(floor: 6, sweetLow: 8, sweetHigh: 14, ceiling: 18, maintenance: 4)
        case .core:
            VolumeLandmarks(floor: 4, sweetLow: 6, sweetHigh: 12, ceiling: 16, maintenance: 2)
        case .glutes:
            // Low floor: heavy compounds feed glutes constantly; direct work
            // tops them up rather than carrying them.
            VolumeLandmarks(floor: 4, sweetLow: 8, sweetHigh: 16, ceiling: 20, maintenance: 2)
        case .hamstrings:
            // Deliberately the LOWEST band (current RP): hinge work carries
            // outsized per-set fatigue, so few hard sets go a long way.
            VolumeLandmarks(floor: 4, sweetLow: 6, sweetHigh: 10, ceiling: 16, maintenance: 2)
        case .quadriceps:
            // Sweet spot mirrors chest but the ceiling closes sooner — heavy
            // squatting is systemically expensive.
            VolumeLandmarks(floor: 6, sweetLow: 10, sweetHigh: 16, ceiling: 18, maintenance: 4)
        case .calves:
            VolumeLandmarks(floor: 6, sweetLow: 8, sweetHigh: 14, ceiling: 18, maintenance: 4)
        case .legs, .other:
            nil
        }
    }
}

// MARK: - Legacy `.legs` → split-group remap

/// Remaps a `.legs`-tagged exercise to its split group by NAME — used by the
/// one-time store migration (catalog rows AND denormalized history snapshots)
/// and by any importer that meets pre-split data. Name-based on purpose: the
/// denormalized `exerciseNameSnapshot` is all history rows reliably carry.
public enum LegsMigration {

    /// The frozen catalog's 12 leg exercise names, mapped by prime mover.
    /// Exact (case-insensitive) match wins before any keyword scan so a rename
    /// of the RULES can never silently re-bucket a known catalog row.
    private static let catalog: [String: Muscle] = [
        "squat": .quadriceps,
        "hack squat": .quadriceps,
        "bulgarian split squat": .quadriceps,
        "leg extension": .quadriceps,
        "lunges": .quadriceps,
        "leg press": .quadriceps,
        "leg curl": .hamstrings,
        "romanian deadlift": .hamstrings,
        "hip thrust": .glutes,
        "sumo deadlift": .glutes,
        "kickbacks": .glutes,
        "standing calf raises": .calves,
        "seated calf raises": .calves,
    ]

    /// Keyword rules for CUSTOM exercise names, checked IN ORDER — order is
    /// load-bearing: the most specific tissue words run first so "Seated Calf
    /// Press" lands on calves (calf precedes press) and "Nordic Ham Curl" on
    /// hamstrings (nordic precedes curl). Case-insensitive substring match.
    private static let keywordRules: [(keyword: String, muscle: Muscle)] = [
        ("calf", .calves),
        ("calve", .calves),
        ("soleus", .calves),
        ("gastro", .calves),
        ("tibialis", .calves),
        ("glute ham", .hamstrings),   // before "glute": a GHR is hamstrings work
        ("nordic", .hamstrings),
        ("rdl", .hamstrings),
        ("romanian", .hamstrings),
        ("stiff", .hamstrings),
        ("good morning", .hamstrings),
        ("curl", .hamstrings),
        ("ham", .hamstrings),
        ("thrust", .glutes),
        ("glute", .glutes),
        ("bridge", .glutes),
        ("kickback", .glutes),
        ("kick back", .glutes),
        ("abduct", .glutes),
        ("hip ext", .glutes),
        ("pull through", .glutes),
        ("pull-through", .glutes),
        ("hyperextension", .glutes),
        ("sumo", .glutes),            // before "deadlift": sumo pulls hip-dominant
        ("deadlift", .glutes),
        ("hinge", .glutes),
        ("squat", .quadriceps),
        ("lunge", .quadriceps),
        ("extension", .quadriceps),
        ("sissy", .quadriceps),
        ("step", .quadriceps),
        ("press", .quadriceps),
        ("adduct", .quadriceps),
    ]

    /// The split group a legacy `.legs` exercise belongs to. Catalog names map
    /// exactly; custom names fall through the ordered keyword rules; anything
    /// unrecognizable defaults to `.quadriceps` (the statistically likeliest
    /// "leg exercise", and the group whose landmarks are closest to the old
    /// undifferentiated legs bucket).
    public static func remap(exerciseName: String) -> Muscle {
        let normalized = exerciseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let exact = catalog[normalized] { return exact }
        for rule in keywordRules where normalized.contains(rule.keyword) {
            return rule.muscle
        }
        return .quadriceps
    }
}
