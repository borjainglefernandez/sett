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
    /// The selected Time Chamber backdrop (`ChamberBackground.rawValue`).
    public var chamberBackground: String {
        didSet { UserDefaults.standard.set(chamberBackground, forKey: "sett.chamberBackground") }
    }
    /// The current training phase (`TrainingPhase.rawValue`) — the scoring lens
    /// stamped onto each new workout.
    public var trainingPhase: String {
        didSet { UserDefaults.standard.set(trainingPhase, forKey: "sett.trainingPhase") }
    }
    /// Whether the user has picked a phase yet (drives the first-launch prompt).
    public var hasChosenPhase: Bool {
        didSet { UserDefaults.standard.set(hasChosenPhase, forKey: "sett.hasChosenPhase") }
    }
    /// Which surface a workout opens on: the full-screen Scanner (false, default) or
    /// the Overview list (true).
    public var startsInList: Bool {
        didSet { UserDefaults.standard.set(startsInList, forKey: "sett.startsInList") }
    }
    /// How routines are scheduled: `.weekday` (fixed days) or `.rotation` (an ordered
    /// split that advances one step per completed workout, day-agnostic).
    public var scheduleMode: ScheduleMode {
        didSet { UserDefaults.standard.set(scheduleMode.rawValue, forKey: "sett.scheduleMode") }
    }
    /// The rotation pointer — LEGACY positional index, kept only to migrate old installs.
    public var rotationIndex: Int {
        didSet { UserDefaults.standard.set(rotationIndex, forKey: "sett.rotationIndex") }
    }
    /// The next-up routine in rotation mode, by id. Identity-based so reordering or
    /// deleting routines never drifts the cursor to the wrong plan (nil ⇒ start of order).
    public var rotationRoutineID: String? {
        didSet { UserDefaults.standard.set(rotationRoutineID, forKey: "sett.rotationRoutineID") }
    }

    /// Resolved current phase (defaults to maintaining).
    public var phase: TrainingPhase {
        TrainingPhase(rawValue: trainingPhase) ?? .maintaining
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
        self.chamberBackground = defaults.string(forKey: "sett.chamberBackground") ?? "nebula"
        self.trainingPhase = defaults.string(forKey: "sett.trainingPhase") ?? TrainingPhase.maintaining.rawValue
        self.hasChosenPhase = defaults.bool(forKey: "sett.hasChosenPhase")
        self.startsInList = defaults.bool(forKey: "sett.startsInList")
        self.scheduleMode = ScheduleMode(rawValue: defaults.string(forKey: "sett.scheduleMode") ?? "") ?? .weekday
        self.rotationIndex = defaults.integer(forKey: "sett.rotationIndex")
        self.rotationRoutineID = defaults.string(forKey: "sett.rotationRoutineID")
    }

    public func displayWeight(_ grams: Int) -> String {
        WeightFormat.compactWithUnit(grams: grams, unit: unit)
    }
}

// MARK: - Routine scheduling

public enum ScheduleMode: String, CaseIterable, Identifiable, Sendable {
    case weekday   // fixed days of the week (daysOfWeekMask)
    case rotation  // an ordered split that advances one step per completed workout
    public var id: String { rawValue }
    public var title: String { self == .weekday ? "Weekday" : "Rotation" }
}

/// Resolves "the routine you'd start now" for both schedule modes, so Home, the
/// directive panel, and the rotation advance can't disagree. `routines` should be the
/// active set; ordering is by `orderIndex`.
public enum Scheduling {
    public static func orderedActive(_ routines: [Routine]) -> [Routine] {
        routines.filter { $0.deletedAt == nil && !$0.isArchived }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    @MainActor
    public static func nextRoutine(_ routines: [Routine], settings: UserSettingsStore) -> Routine? {
        let active = orderedActive(routines)
        guard !active.isEmpty else { return nil }
        switch settings.scheduleMode {
        case .rotation:
            // Identity-based: return the routine the cursor names. If it was never set
            // or its routine was deleted, fall back to the migrated positional index,
            // then the start of the order — never a wrong-but-present routine.
            if let id = settings.rotationRoutineID,
               let match = active.first(where: { $0.id.uuidString == id }) {
                return match
            }
            let i = ((settings.rotationIndex % active.count) + active.count) % active.count
            return active[i]
        case .weekday:
            let weekday = Calendar.current.component(.weekday, from: .now) // 1=Sun … 7=Sat
            let mondayIndex = (weekday + 5) % 7                            // 0=Mon … 6=Sun
            return active.first { ($0.daysOfWeekMask >> mondayIndex) & 1 == 1 }
        }
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
    /// "Off the record" — the summary swaps the Net Progress card for a quiet
    /// OFF THE RECORD system message; PL/XP/badge stages are unchanged.
    public let isCasual: Bool
    /// The realm this workout ran in (ChamberBackground.rawValue); nil ⇒ default.
    public let domainRaw: String?

    public init(id: UUID, title: String, durationSeconds: Int,
                powerLevelBefore: Int, powerLevelAfter: Int,
                tierBefore: Int, tierAfter: Int,
                netReps: Int, netVolumeGrams: Int, netIsNew: Bool,
                newBadgeKeys: [String], xpEarned: [CharacterKey: Int],
                commentary: String, commentarySource: InsightSource,
                isCasual: Bool = false, domainRaw: String? = nil) {
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
        self.isCasual = isCasual
        self.domainRaw = domainRaw
    }
}
