import Foundation
import SwiftData

// MARK: - Periods & buckets

public enum Period: String, CaseIterable, Sendable, Identifiable {
    case week, month, year
    public var id: String { rawValue }
}

/// A strict calendar bucket (ISO week / month / year) in the user's calendar.
public struct BucketKey: Hashable, Sendable, Comparable {
    public let period: Period
    /// week: yearForWeekOfYear*100+weekOfYear · month: year*100+month · year: year
    public let ordinal: Int

    public init(period: Period, ordinal: Int) {
        self.period = period
        self.ordinal = ordinal
    }

    public static func < (lhs: BucketKey, rhs: BucketKey) -> Bool { lhs.ordinal < rhs.ordinal }
}

// MARK: - Samples (Sendable value snapshots of the store; engines never touch @Model)

public struct SetSample: Sendable, Hashable {
    public let exerciseID: UUID
    public let muscle: Muscle
    public let weightGrams: Int
    public let reps: Int
    public let isWarmup: Bool
    public let completedAt: Date
    public let workoutID: UUID
    /// Set belongs to an "off the record" workout — excluded from net-progress only.
    public let isCasual: Bool
    /// Set belongs to a workout started with the rested surge armed (first qualifying
    /// session after a full rest day). The engine weights its volume by the config's
    /// surge multiplier while it sits in the volume window; display sums ignore it.
    public let isRestedSurge: Bool

    public init(exerciseID: UUID, muscle: Muscle, weightGrams: Int, reps: Int,
                isWarmup: Bool, completedAt: Date, workoutID: UUID, isCasual: Bool = false,
                isRestedSurge: Bool = false) {
        self.exerciseID = exerciseID
        self.muscle = muscle
        self.weightGrams = weightGrams
        self.reps = reps
        self.isWarmup = isWarmup
        self.completedAt = completedAt
        self.workoutID = workoutID
        self.isCasual = isCasual
        self.isRestedSurge = isRestedSurge
    }
}

public struct WorkoutSample: Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let startedAt: Date
    public let endedAt: Date?
    public let bodyweightGrams: Int?
    public let routineID: UUID?
    /// "Off the record" / casual workout — excluded from net-progress only.
    public let isCasual: Bool

    public init(id: UUID, title: String, startedAt: Date, endedAt: Date?,
                bodyweightGrams: Int?, routineID: UUID?, isCasual: Bool = false) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.bodyweightGrams = bodyweightGrams
        self.routineID = routineID
        self.isCasual = isCasual
    }
}

public struct SleepSample: Sendable, Hashable {
    public let dateKey: Int
    public let sleepScore: Int?
    public let totalSleepSeconds: Int?

    public init(dateKey: Int, sleepScore: Int?, totalSleepSeconds: Int?) {
        self.dateKey = dateKey
        self.sleepScore = sleepScore
        self.totalSleepSeconds = totalSleepSeconds
    }
}

public struct GoalSample: Sendable, Hashable {
    public let id: UUID
    public let kind: GoalKind
    public let targetValue: Int
    public let exerciseID: UUID?
    public let startDate: Date
    public let endDate: Date?
    public let isActive: Bool
    public let completedAt: Date?
    public let createdAt: Date

    public init(id: UUID, kind: GoalKind, targetValue: Int, exerciseID: UUID?,
                startDate: Date, endDate: Date?, isActive: Bool, completedAt: Date?, createdAt: Date) {
        self.id = id
        self.kind = kind
        self.targetValue = targetValue
        self.exerciseID = exerciseID
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}

// MARK: - Engine outputs

public struct NetSummary: Sendable, Hashable {
    public let reps: Int
    /// Volume load delta in gram·reps.
    public let volumeGrams: Int
    /// True when the previous bucket had no sets — UI shows "NEW", not "+everything".
    public let isNew: Bool

    public init(reps: Int, volumeGrams: Int, isNew: Bool) {
        self.reps = reps
        self.volumeGrams = volumeGrams
        self.isNew = isNew
    }
}

public struct GoalProgress: Sendable, Hashable {
    public let goalID: UUID
    /// 0.0…1.0 for ring display.
    public let fraction: Double
    public let currentValue: Int
    public let targetValue: Int
    public let isComplete: Bool

    public init(goalID: UUID, fraction: Double, currentValue: Int, targetValue: Int, isComplete: Bool) {
        self.goalID = goalID
        self.fraction = fraction
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.isComplete = isComplete
    }
}

// MARK: - Sample extraction (main-actor bridge from SwiftData to Sendable inputs)

@MainActor
// MARK: - Effective load (bodyweight exercises add the lifter's bodyweight)

public enum LoadMath {
    /// Fallback bodyweight when a workout has no scale reading — a neutral adult mass
    /// (~176 lb) so a pull-up is never scored as 0 output.
    nonisolated public static let defaultBodyweightGrams = 80_000

    /// The effective load an exercise moved: bodyweight equipment adds the lifter's
    /// bodyweight to the added weight (so pull-ups/dips/weighted dips score real
    /// output); everything else is the added weight unchanged.
    nonisolated public static func effectiveWeightGrams(addedGrams: Int, equipment: Equipment,
                                                        bodyweightGrams: Int?) -> Int {
        guard equipment == .bodyweight else { return addedGrams }
        return addedGrams + (bodyweightGrams ?? defaultBodyweightGrams)
    }
}

public enum SampleExtractor {
    /// All non-deleted sets from finished, non-deleted workouts.
    public static func setSamples(context: ModelContext) -> [SetSample] {
        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        var samples: [SetSample] = []
        for workout in workouts where workout.deletedAt == nil && workout.endedAt != nil {
            for we in workout.exercises where we.deletedAt == nil {
                for set in we.sets where set.deletedAt == nil {
                    // Effective load: a bodyweight exercise adds the lifter's bodyweight,
                    // so pull-ups/dips score real output instead of 0.
                    let effective = LoadMath.effectiveWeightGrams(
                        addedGrams: set.weightGrams, equipment: we.equipment,
                        bodyweightGrams: workout.bodyweightGrams)
                    samples.append(SetSample(
                        exerciseID: we.exerciseID,
                        muscle: we.muscle,
                        weightGrams: effective,
                        reps: set.reps,
                        isWarmup: set.isWarmup,
                        completedAt: set.completedAt,
                        workoutID: workout.id,
                        isCasual: workout.isCasual,
                        isRestedSurge: workout.restedSurge
                    ))
                }
            }
        }
        return samples.sorted { $0.completedAt < $1.completedAt }
    }

    public static func workoutSamples(context: ModelContext) -> [WorkoutSample] {
        let workouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        return workouts
            .filter { $0.deletedAt == nil && $0.endedAt != nil }
            .map { WorkoutSample(id: $0.id, title: $0.title, startedAt: $0.startedAt,
                                 endedAt: $0.endedAt, bodyweightGrams: $0.bodyweightGrams,
                                 routineID: $0.routineID, isCasual: $0.isCasual) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    public static func sleepSamples(context: ModelContext) -> [SleepSample] {
        let days = (try? context.fetch(FetchDescriptor<SleepDay>())) ?? []
        return days.map { SleepSample(dateKey: $0.dateKey, sleepScore: $0.sleepScore,
                                      totalSleepSeconds: $0.totalSleepSeconds) }
            .sorted { $0.dateKey < $1.dateKey }
    }

    public static func goalSamples(context: ModelContext) -> [GoalSample] {
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        return goals.filter { $0.deletedAt == nil }.map {
            GoalSample(id: $0.id, kind: $0.kind, targetValue: $0.targetValue,
                       exerciseID: $0.exerciseID, startDate: $0.startDate, endDate: $0.endDate,
                       isActive: $0.isActive, completedAt: $0.completedAt, createdAt: $0.createdAt)
        }
    }
}

// MARK: - Date helpers shared by engines

public extension Calendar {
    /// dateKey (yyyyMMdd) for sleep pairing, in this calendar's time zone.
    func dateKey(for date: Date) -> Int {
        let c = dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }
}
