import Foundation

/// Typed access to progression_config.json. All tuning constants live in the JSON so
/// client and server share one file; nothing here is hardcoded logic.
public struct ProgressionConfig {
    public let raw: [String: Any]

    // Typed sub-configs the engines use on hot paths.
    public struct EffectiveSet: Sendable {
        public let minReps: Int, maxReps: Int
        public let minFractionOfBestE1RM: Double
        public let maxSetsPerExercisePerWorkout: Int, maxSetsPerWorkout: Int
    }
    public struct QualifyingWorkout: Sendable {
        public let minEffectiveSets: Int, minDurationMinutes: Int
    }
    public struct E1RM: Sendable { public let repCap: Int, divisor: Int }
    public struct PowerLevel: Sendable {
        public let strengthWindowDays: Int, volumeWindowDays: Int
        public let strengthWeight: Double, volumeWeight: Double
        public let consistencyPerWeek: Double
        public let consistencyMaxWeeks: Int, streakMinDaysPerWeek: Int
    }
    public struct BadgeDef: Sendable, Hashable {
        public let key: String
        public let name: String
        public let rarity: BadgeRarity
        public let character: CharacterKey
        public let params: [String: Int]
    }

    public let effectiveSet: EffectiveSet
    public let qualifyingWorkout: QualifyingWorkout
    public let e1rm: E1RM
    public let powerLevel: PowerLevel
    public let badges: [BadgeDef]
    public let xp: [String: Any]
    public let tiers: [String: Any]
    public let rival: [String: Any]

    public static func load() throws -> ProgressionConfig {
        guard let url = Bundle.module.url(forResource: "progression_config", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return try ProgressionConfig(json: json)
    }

    public init(json: [String: Any]) throws {
        self.raw = json

        let es = json["effectiveSet"] as? [String: Any] ?? [:]
        self.effectiveSet = EffectiveSet(
            minReps: es["minReps"] as? Int ?? 1,
            maxReps: es["maxReps"] as? Int ?? 30,
            minFractionOfBestE1RM: es["minFractionOfBestE1RM"] as? Double ?? 0.4,
            maxSetsPerExercisePerWorkout: es["maxSetsPerExercisePerWorkout"] as? Int ?? 6,
            maxSetsPerWorkout: es["maxSetsPerWorkout"] as? Int ?? 30
        )
        let qw = json["qualifyingWorkout"] as? [String: Any] ?? [:]
        self.qualifyingWorkout = QualifyingWorkout(
            minEffectiveSets: qw["minEffectiveSets"] as? Int ?? 3,
            minDurationMinutes: qw["minDurationMinutes"] as? Int ?? 10
        )
        let e1 = json["e1rm"] as? [String: Any] ?? [:]
        self.e1rm = E1RM(repCap: e1["repCap"] as? Int ?? 12, divisor: e1["divisor"] as? Int ?? 30)

        let pl = json["powerLevel"] as? [String: Any] ?? [:]
        self.powerLevel = PowerLevel(
            strengthWindowDays: pl["strengthWindowDays"] as? Int ?? 90,
            volumeWindowDays: pl["volumeWindowDays"] as? Int ?? 28,
            strengthWeight: pl["strengthWeight"] as? Double ?? 4.0,
            volumeWeight: pl["volumeWeight"] as? Double ?? 8.0,
            consistencyPerWeek: pl["consistencyPerWeek"] as? Double ?? 0.05,
            consistencyMaxWeeks: pl["consistencyMaxWeeks"] as? Int ?? 10,
            streakMinDaysPerWeek: pl["streakMinDaysPerWeek"] as? Int ?? 2
        )

        var defs: [BadgeDef] = []
        if let badgeJSON = json["badges"] as? [String: [String: Any]] {
            for (key, body) in badgeJSON {
                let rarity = BadgeRarity(rawValue: body["rarity"] as? String ?? "bronze") ?? .bronze
                let character = CharacterKey(rawValue: body["character"] as? String ?? "vego") ?? .vego
                var params: [String: Int] = [:]
                for (k, v) in body {
                    if let i = v as? Int { params[k] = i }
                }
                defs.append(BadgeDef(key: key, name: body["name"] as? String ?? key,
                                     rarity: rarity, character: character, params: params))
            }
        }
        self.badges = defs.sorted { $0.key < $1.key }
        self.xp = json["xp"] as? [String: Any] ?? [:]
        self.tiers = json["tiers"] as? [String: Any] ?? [:]
        self.rival = json["rival"] as? [String: Any] ?? [:]
    }

    public func badge(_ key: String) -> BadgeDef? {
        badges.first { $0.key == key }
    }

    public func badgeXP(rarity: BadgeRarity) -> Int {
        let table = xp["badgeXP"] as? [String: Int]
        return table?[rarity.rawValue] ?? 0
    }
}

// `raw`/`xp`/`tiers`/`rival` hold [String: Any] parsed once at startup and never mutated;
// the type is safe to pass across actors in practice.
extension ProgressionConfig: @unchecked Sendable {}
