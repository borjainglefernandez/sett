import Foundation
import SwiftData
import SwiftUI
import SettCore

// MARK: - Service root (injected via .environment)

@MainActor
@Observable
public final class AppServices {
    public let container: ModelContainer
    public let session: WorkoutSessionStore
    public let progression: ProgressionStore
    public let settings: UserSettingsStore

    public init(container: ModelContainer) {
        self.container = container
        let settings = UserSettingsStore()
        let progression = ProgressionStore()
        self.settings = settings
        self.progression = progression
        self.session = WorkoutSessionStore(container: container, settings: settings, progression: progression)
    }
}

// MARK: - User settings (local-only prefs)

@MainActor
@Observable
public final class UserSettingsStore {
    public var unit: WeightUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: "sett.unit") }
    }
    public var incrementGrams: Int {
        didSet { UserDefaults.standard.set(incrementGrams, forKey: "sett.incrementGrams") }
    }
    public var defaultRestSeconds: Int {
        didSet { UserDefaults.standard.set(defaultRestSeconds, forKey: "sett.defaultRest") }
    }
    public var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "sett.hasOnboarded") }
    }

    public init() {
        let defaults = UserDefaults.standard
        let unit = WeightUnit(rawValue: defaults.string(forKey: "sett.unit") ?? "") ?? .lb
        self.unit = unit
        let increment = defaults.integer(forKey: "sett.incrementGrams")
        self.incrementGrams = increment > 0 ? increment : unit.defaultIncrementGrams
        let rest = defaults.integer(forKey: "sett.defaultRest")
        self.defaultRestSeconds = rest > 0 ? rest : 90
        self.hasOnboarded = defaults.bool(forKey: "sett.hasOnboarded")
    }

    public func displayWeight(_ grams: Int) -> String {
        WeightFormat.compactWithUnit(grams: grams, unit: unit)
    }
}

// MARK: - Summary payload handed from session end to the Power Scan sheet

public struct WorkoutSummaryData: Identifiable, Sendable {
    public let id: UUID                 // workout id
    public let title: String
    public let durationSeconds: Int
    public let powerLevelBefore: Int
    public let powerLevelAfter: Int
    /// Active character's `TransformationTier.rawValue` before/after this workout's
    /// recompute — the summary's ceiling-break stage fires when `tierAfter > tierBefore`.
    public let tierBefore: Int
    public let tierAfter: Int
    public let netReps: Int
    public let netVolumeGrams: Int
    public let netIsNew: Bool
    public let newBadgeKeys: [String]
    /// XP gained by this workout, per character — only characters with a positive delta.
    public let xpEarned: [CharacterKey: Int]
    public let commentary: String
    public let commentarySource: InsightSource

    public init(id: UUID, title: String, durationSeconds: Int,
                powerLevelBefore: Int, powerLevelAfter: Int,
                tierBefore: Int, tierAfter: Int,
                netReps: Int, netVolumeGrams: Int, netIsNew: Bool,
                newBadgeKeys: [String], xpEarned: [CharacterKey: Int],
                commentary: String, commentarySource: InsightSource) {
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.powerLevelBefore = powerLevelBefore
        self.powerLevelAfter = powerLevelAfter
        self.tierBefore = tierBefore
        self.tierAfter = tierAfter
        self.netReps = netReps
        self.netVolumeGrams = netVolumeGrams
        self.netIsNew = netIsNew
        self.newBadgeKeys = newBadgeKeys
        self.xpEarned = xpEarned
        self.commentary = commentary
        self.commentarySource = commentarySource
    }
}
