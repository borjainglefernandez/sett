import Foundation
import SwiftData

// Sync conventions shared by every synced model:
// - `id`: client-generated UUID, globally unique across devices and server.
// - `updatedAt`: last-writer-wins conflict key; bump on every mutation via `touch()`.
// - `deletedAt`: soft-delete tombstone; UI predicates must filter `deletedAt == nil`.
// - `needsPush`: dirty flag cleared by the sync engine on ack.

// MARK: - Exercise

@Model
public final class Exercise {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var muscleRaw: String
    public var equipmentRaw: String
    public var isCustom: Bool
    public var isArchived: Bool
    public var instructions: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public var muscle: Muscle {
        get { Muscle(rawValue: muscleRaw) ?? .other }
        set { muscleRaw = newValue.rawValue }
    }
    public var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .machine }
        set { equipmentRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), name: String, muscle: Muscle, equipment: Equipment,
                isCustom: Bool = false, now: Date = .now) {
        self.id = id
        self.name = name
        self.muscleRaw = muscle.rawValue
        self.equipmentRaw = equipment.rawValue
        self.isCustom = isCustom
        self.isArchived = false
        self.instructions = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
    }
}

// MARK: - Workout

@Model
public final class Workout {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var startedAt: Date
    /// nil ⇒ in progress. At most one workout may have endedAt == nil.
    public var endedAt: Date?
    public var pausedSeconds: Int
    public var bodyweightGrams: Int?
    /// 0…10 half stars (nil = unrated).
    public var ratingHalfStars: Int?
    public var notes: String?
    /// "Off the record" / casual: still counts for streaks, XP, PL, volume charts,
    /// e1RM & PRs — excluded ONLY from net-progress comparisons (no nets of its own,
    /// never a reference/baseline for another workout). The STORED default is what
    /// lets SwiftData lightweight migration backfill existing rows — an init-only
    /// default is not enough and crashes old stores at container creation.
    public var isCasual: Bool = false
    /// Loose reference — never a relationship, so deleting a routine can't touch history.
    public var routineID: UUID?
    public var routineNameSnapshot: String?
    /// Loose gym reference, same pattern.
    public var gymID: UUID?
    public var gymNameSnapshot: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    public var exercises: [WorkoutExercise]

    public var isOngoing: Bool { endedAt == nil && deletedAt == nil }

    public var orderedExercises: [WorkoutExercise] {
        exercises.filter { $0.deletedAt == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    public init(id: UUID = UUID(), title: String, startedAt: Date = .now,
                isCasual: Bool = false, now: Date = .now) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = nil
        self.pausedSeconds = 0
        self.bodyweightGrams = nil
        self.ratingHalfStars = nil
        self.notes = nil
        self.isCasual = isCasual
        self.routineID = nil
        self.routineNameSnapshot = nil
        self.gymID = nil
        self.gymNameSnapshot = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
        self.exercises = []
    }
}

// MARK: - WorkoutExercise

@Model
public final class WorkoutExercise {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    /// Denormalized so history/analytics never break if the Exercise row changes.
    public var exerciseID: UUID
    public var exerciseNameSnapshot: String
    public var muscleRaw: String
    public var notes: String?
    public var restSeconds: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.workoutExercise)
    public var sets: [SetEntry]

    public var muscle: Muscle { Muscle(rawValue: muscleRaw) ?? .other }

    public var orderedSets: [SetEntry] {
        sets.filter { $0.deletedAt == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    public init(id: UUID = UUID(), orderIndex: Int, exercise: Exercise, now: Date = .now) {
        self.id = id
        self.orderIndex = orderIndex
        self.exerciseID = exercise.id
        self.exerciseNameSnapshot = exercise.name
        self.muscleRaw = exercise.muscleRaw
        self.notes = nil
        self.restSeconds = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
        self.sets = []
    }
}

// MARK: - SetEntry ("a sett")

@Model
public final class SetEntry {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    /// Canonical weight in integer grams. 0 for pure bodyweight sets. Never a float.
    public var weightGrams: Int
    public var entryUnitRaw: String
    public var reps: Int
    public var isWarmup: Bool
    /// Per-set timestamp — drives pairing, buckets, and badges.
    public var completedAt: Date
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public var workoutExercise: WorkoutExercise?

    public var entryUnit: WeightUnit {
        get { WeightUnit(rawValue: entryUnitRaw) ?? .lb }
        set { entryUnitRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), orderIndex: Int, weightGrams: Int, entryUnit: WeightUnit,
                reps: Int, isWarmup: Bool = false, completedAt: Date = .now, now: Date = .now) {
        self.id = id
        self.orderIndex = orderIndex
        self.weightGrams = weightGrams
        self.entryUnitRaw = entryUnit.rawValue
        self.reps = reps
        self.isWarmup = isWarmup
        self.completedAt = completedAt
        self.notes = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
    }
}

// MARK: - Routine (templates; user story 2)

@Model
public final class Routine {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// Bitmask: bit 0 = Monday … bit 6 = Sunday.
    public var daysOfWeekMask: Int
    public var orderIndex: Int
    public var notes: String?
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    public var exercises: [RoutineExercise]

    public var orderedExercises: [RoutineExercise] {
        exercises.filter { $0.deletedAt == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    public init(id: UUID = UUID(), name: String, daysOfWeekMask: Int = 0, orderIndex: Int = 0, now: Date = .now) {
        self.id = id
        self.name = name
        self.daysOfWeekMask = daysOfWeekMask
        self.orderIndex = orderIndex
        self.notes = nil
        self.isArchived = false
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
        self.exercises = []
    }
}

@Model
public final class RoutineExercise {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    public var exerciseID: UUID
    public var exerciseNameSnapshot: String
    public var muscleRaw: String
    public var restSeconds: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public var routine: Routine?

    @Relationship(deleteRule: .cascade, inverse: \PlannedSet.routineExercise)
    public var plannedSets: [PlannedSet]

    public var orderedPlannedSets: [PlannedSet] {
        plannedSets.filter { $0.deletedAt == nil }.sorted { $0.orderIndex < $1.orderIndex }
    }

    public init(id: UUID = UUID(), orderIndex: Int, exercise: Exercise, now: Date = .now) {
        self.id = id
        self.orderIndex = orderIndex
        self.exerciseID = exercise.id
        self.exerciseNameSnapshot = exercise.name
        self.muscleRaw = exercise.muscleRaw
        self.restSeconds = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
        self.plannedSets = []
    }
}

@Model
public final class PlannedSet {
    @Attribute(.unique) public var id: UUID
    public var orderIndex: Int
    public var targetReps: Int
    /// nil ⇒ "use last time's weight" (autofill from history).
    public var targetWeightGrams: Int?
    public var isWarmup: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public var routineExercise: RoutineExercise?

    public init(id: UUID = UUID(), orderIndex: Int, targetReps: Int,
                targetWeightGrams: Int? = nil, isWarmup: Bool = false, now: Date = .now) {
        self.id = id
        self.orderIndex = orderIndex
        self.targetReps = targetReps
        self.targetWeightGrams = targetWeightGrams
        self.isWarmup = isWarmup
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
    }
}

// MARK: - Goal (user story 7)

@Model
public final class Goal {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    /// frequency: days/week · prTarget: grams · volumeTarget: gram-reps volume load.
    public var targetValue: Int
    public var exerciseID: UUID?
    public var exerciseNameSnapshot: String?
    public var startDate: Date
    public var endDate: Date?
    public var isActive: Bool
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .frequency }
        set { kindRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), kind: GoalKind, targetValue: Int,
                exerciseID: UUID? = nil, exerciseNameSnapshot: String? = nil,
                startDate: Date = .now, endDate: Date? = nil, now: Date = .now) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.targetValue = targetValue
        self.exerciseID = exerciseID
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = true
        self.completedAt = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
    }
}

// MARK: - BadgeAward (catalog lives in code + progression_config.json)

@Model
public final class BadgeAward {
    @Attribute(.unique) public var id: UUID
    public var badgeKey: String
    public var tier: Int
    public var earnedAt: Date
    public var workoutID: UUID?
    public var exerciseID: UUID?
    /// The number that earned it (grams, reps, streak weeks…).
    public var valueSnapshot: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public init(id: UUID = UUID(), badgeKey: String, tier: Int = 1, earnedAt: Date,
                workoutID: UUID? = nil, exerciseID: UUID? = nil, valueSnapshot: Int = 0, now: Date = .now) {
        self.id = id
        self.badgeKey = badgeKey
        self.tier = tier
        self.earnedAt = earnedAt
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.valueSnapshot = valueSnapshot
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
    }
}

// MARK: - SaiyanState (display cache — always recomputable, never source of truth)

@Model
public final class SaiyanState {
    @Attribute(.unique) public var id: UUID
    public var powerLevel: Int
    public var allTimePeakPL: Int
    public var characterKeyRaw: String
    public var transformationTierRaw: Int
    /// Cached character XP totals as JSON `{characterKey: xp}` for widget/rankings display.
    public var characterXPJSON: String
    public var updatedAt: Date
    public var needsPush: Bool

    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11A")!

    public var characterKey: CharacterKey {
        get { CharacterKey(rawValue: characterKeyRaw) ?? .vego }
        set { characterKeyRaw = newValue.rawValue }
    }
    public var transformationTier: TransformationTier {
        get { TransformationTier(rawValue: transformationTierRaw) ?? .base }
        set { transformationTierRaw = newValue.rawValue }
    }

    public init(now: Date = .now) {
        self.id = Self.singletonID
        self.powerLevel = 0
        self.allTimePeakPL = 0
        self.characterKeyRaw = CharacterKey.vego.rawValue
        self.transformationTierRaw = TransformationTier.base.rawValue
        self.characterXPJSON = "{}"
        self.updatedAt = now
        self.needsPush = true
    }
}

// MARK: - SleepDay (server-owned cache, pull-only)

@Model
public final class SleepDay {
    /// yyyyMMdd in the user's home time zone — no Date ambiguity.
    @Attribute(.unique) public var dateKey: Int
    public var sleepScore: Int?
    public var readinessScore: Int?
    public var totalSleepSeconds: Int?
    public var deepSeconds: Int?
    public var remSeconds: Int?
    public var avgHRV: Double?
    public var restingHR: Int?
    public var fetchedAt: Date

    public init(dateKey: Int, sleepScore: Int? = nil, readinessScore: Int? = nil,
                totalSleepSeconds: Int? = nil, deepSeconds: Int? = nil, remSeconds: Int? = nil,
                avgHRV: Double? = nil, restingHR: Int? = nil, fetchedAt: Date = .now) {
        self.dateKey = dateKey
        self.sleepScore = sleepScore
        self.readinessScore = readinessScore
        self.totalSleepSeconds = totalSleepSeconds
        self.deepSeconds = deepSeconds
        self.remSeconds = remSeconds
        self.avgHRV = avgHRV
        self.restingHR = restingHR
        self.fetchedAt = fetchedAt
    }
}

// MARK: - AIInsight

@Model
public final class AIInsight {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var periodStart: Date
    public var periodEnd: Date
    public var workoutID: UUID?
    /// Markdown body.
    public var body: String
    public var sourceRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public var kind: InsightKind {
        get { InsightKind(rawValue: kindRaw) ?? .postWorkout }
        set { kindRaw = newValue.rawValue }
    }
    public var source: InsightSource {
        get { InsightSource(rawValue: sourceRaw) ?? .fallbackTemplate }
        set { sourceRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), kind: InsightKind, periodStart: Date, periodEnd: Date,
                workoutID: UUID? = nil, body: String, source: InsightSource, now: Date = .now) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.workoutID = workoutID
        self.body = body
        self.sourceRaw = source.rawValue
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = kind == .postWorkout
    }
}

// MARK: - Gym (location logging + Chamber Logs)

@Model
public final class Gym {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var isHome: Bool
    public var notes: String?
    /// Chamber Log fields (optional community review).
    public var dayPassPriceCents: Int?
    public var quickRating: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double,
                isHome: Bool = false, now: Date = .now) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isHome = isHome
        self.notes = nil
        self.dayPassPriceCents = nil
        self.quickRating = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
    }
}

// MARK: - BodyweightEntry (standalone bodyweight track)

/// A quick scale reading, independent of any workout. `Workout.bodyweightGrams`
/// stays as the per-session snapshot; this is the longitudinal track.
@Model
public final class BodyweightEntry {
    @Attribute(.unique) public var id: UUID
    /// Canonical weight in integer grams. Never a float.
    public var weightGrams: Int
    public var loggedAt: Date
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var needsPush: Bool

    public init(id: UUID = UUID(), weightGrams: Int, loggedAt: Date = .now, now: Date = .now) {
        self.id = id
        self.weightGrams = weightGrams
        self.loggedAt = loggedAt
        self.notes = nil
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
        self.needsPush = true
    }
}

// MARK: - SyncState (local-only)

@Model
public final class SyncState {
    @Attribute(.unique) public var id: UUID
    public var lastServerSeq: Int64
    public var lastPushAt: Date?
    public var lastPullAt: Date?

    public static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-0000000057AC")!

    public init() {
        self.id = Self.singletonID
        self.lastServerSeq = 0
        self.lastPushAt = nil
        self.lastPullAt = nil
    }
}

// MARK: - Schema

public enum SettSchema {
    public static var allModels: [any PersistentModel.Type] {
        [Exercise.self, Workout.self, WorkoutExercise.self, SetEntry.self,
         Routine.self, RoutineExercise.self, PlannedSet.self,
         Goal.self, BadgeAward.self, SaiyanState.self,
         SleepDay.self, AIInsight.self, Gym.self, BodyweightEntry.self, SyncState.self]
    }
}
