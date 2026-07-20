import Foundation
import Testing
@testable import SettCore

@Suite("PatronUnlocks")
struct PatronUnlocksTests {

    /// The full canonical badge catalog, spelled out independently of the
    /// partition table so a rename on either side fails loudly here instead of
    /// silently locking a patron forever.
    private static let canonicalKeys: [String] = [
        // vego — PRs & ceilings
        "new_ceiling", "limit_break", "walking_legend",
        "triple_threat", "perfect_form", "scanner_breaker",
        // barok — tonnage
        "twenty_ton_day", "hundred_grand", "million_pound_club", "ten_million",
        // nyra — streaks
        "ignition", "steady_flame", "chamber_regular", "chamber_resident", "unbroken_year",
        // torren — goals
        "goal_getter", "marksman", "serial_achiever", "by_the_book", "planners_pride",
        // zia — sleep & recovery
        "lab_partner", "well_rested", "recovery_protocol",
        // gosi — variety & dawn
        "explorer", "full_arsenal", "dawn_patrol",
        // zyn — comebacks, night, momentum
        "momentum", "midnight_oil", "return_to_form", "reforged",
    ]

    @Test("Vego is awake with no badges at all")
    func vegoAlwaysUnlocked() {
        #expect(PatronUnlocks.unlockedPatrons(badgeKeys: [String]()) == [.vego])
    }

    @Test("One badge per domain wakes exactly that patron (plus Vego)")
    func oneKeyPerDomain() {
        let representatives: [(key: String, patron: CharacterKey)] = [
            ("new_ceiling", .vego),
            ("twenty_ton_day", .barok),
            ("ignition", .nyra),
            ("goal_getter", .torren),
            ("lab_partner", .zia),
            ("explorer", .gosi),
            ("momentum", .zyn),
        ]
        for (key, patron) in representatives {
            #expect(PatronUnlocks.patron(forBadgeKey: key) == patron)
            #expect(PatronUnlocks.unlockedPatrons(badgeKeys: [key]) == [.vego, patron])
        }
    }

    @Test("Unknown badge keys are ignored, never trapped")
    func unknownKeysIgnored() {
        #expect(PatronUnlocks.patron(forBadgeKey: "not_a_badge") == nil)
        #expect(PatronUnlocks.unlockedPatrons(badgeKeys: ["not_a_badge", ""]) == [.vego])
        // Unknown keys alongside real ones change nothing.
        #expect(PatronUnlocks.unlockedPatrons(badgeKeys: ["ignition", "mystery_badge"])
                == [.vego, .nyra])
    }

    @Test("Every canonical badge key maps to a patron (exhaustive partition)")
    func exhaustivePartition() {
        for key in Self.canonicalKeys {
            #expect(PatronUnlocks.patron(forBadgeKey: key) != nil,
                    "badge key \(key) fell out of the partition")
        }
        // The full catalog together wakes the entire cast.
        #expect(PatronUnlocks.unlockedPatrons(badgeKeys: Self.canonicalKeys)
                == Set(CharacterKey.allCases))
    }

    @Test("Live config badge catalog stays inside the partition")
    func configKeysCovered() throws {
        // A badge renamed in progression_config.json without a matching partition
        // update must break here, not silently strand a patron behind a dead key.
        let config = try ProgressionConfig.load()
        for def in config.badges {
            #expect(PatronUnlocks.patron(forBadgeKey: def.key) != nil,
                    "config badge \(def.key) has no patron domain")
        }
    }

    @Test("Locked-card copy exists for every patron")
    func requirementCopy() {
        for patron in CharacterKey.allCases {
            let copy = PatronUnlocks.requirement(for: patron)
            #expect(!copy.isEmpty)
            #expect(!copy.contains("!")) // story voice: no exclamation marks
        }
    }
}
