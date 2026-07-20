import Foundation

/// Which patron each badge belongs to — and therefore when each patron awakens.
///
/// Cast law: patrons are voices and witnesses, not parallel ladders. A patron
/// wakes the moment the user earns their FIRST badge in that patron's domain;
/// Vego, the starter patron, is always awake. Unlocks are derived from the set
/// of earned badge keys on every recompute — no new persisted model — which
/// makes them idempotent and fully retroactive for existing users.
public enum PatronUnlocks {

    /// The canonical badge→patron partition (exhaustive over the badge catalog,
    /// including keys retired from the live config — historical awards must keep
    /// counting). Every badge key appears in exactly one domain; this table is
    /// the single source of truth, and the tests hold it against the config so
    /// a badge rename breaks a test, not the feature.
    static let domains: [CharacterKey: Set<String>] = [
        .vego:   ["new_ceiling", "limit_break", "walking_legend",
                  "triple_threat", "perfect_form", "scanner_breaker"],
        .barok:  ["twenty_ton_day", "hundred_grand", "million_pound_club", "ten_million"],
        .nyra:   ["ignition", "steady_flame", "chamber_regular",
                  "chamber_resident", "unbroken_year"],
        .torren: ["goal_getter", "marksman", "serial_achiever",
                  "by_the_book", "planners_pride"],
        .luma:    ["lab_partner", "well_rested", "recovery_protocol"],
        .gosi:   ["explorer", "full_arsenal", "dawn_patrol"],
        .zyn:    ["momentum", "midnight_oil", "return_to_form", "reforged"],
    ]

    /// Reverse index built once from the partition so per-badge lookups stay O(1)
    /// on the recompute hot path.
    private static let patronByBadgeKey: [String: CharacterKey] = {
        var map: [String: CharacterKey] = [:]
        for (patron, keys) in domains {
            for key in keys { map[key] = patron }
        }
        return map
    }()

    /// The patron whose domain contains `key`, or nil for unknown keys.
    /// Unknown keys are ignored rather than trapped — a config/app version skew
    /// must never take patron unlocks down with it.
    public static func patron(forBadgeKey key: String) -> CharacterKey? {
        patronByBadgeKey[key]
    }

    /// Every patron awake given the earned badge keys. Always includes .vego
    /// (the starter patron); unknown keys contribute nothing.
    public static func unlockedPatrons(badgeKeys: some Sequence<String>) -> Set<CharacterKey> {
        var unlocked: Set<CharacterKey> = [.vego]
        for key in badgeKeys {
            if let patron = patronByBadgeKey[key] {
                unlocked.insert(patron)
            }
        }
        return unlocked
    }

    /// One-line story-voice hint for a locked patron card. Vego is never shown
    /// locked, but returns sane copy anyway so callers need no special case.
    public static func requirement(for patron: CharacterKey) -> String {
        switch patron {
        case .vego:   "The Ember Prince walks with you from the first scan."
        case .gosi:   "Wander the arsenal — your first variety badge wakes the Bottomless."
        case .barok:  "Move real tonnage — your first tonnage badge wakes the Mountain."
        case .nyra:   "String the weeks together — your first streak badge wakes Nyra."
        case .torren: "Set a goal and hit it — your first goal badge wakes Torren."
        case .luma:    "Let recovery power a lift — your first sleep badge wakes Luma."
        case .zyn:    "Come back stronger — your first comeback badge wakes Zyn."
        }
    }
}
