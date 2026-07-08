import Foundation
import SwiftData
import SwiftUI
import SettCore

/// Owns the active workout lifecycle: start, log, rest timer, finish → Power Scan summary.
/// Presented app-wide as a fullScreenCover so it survives tab switches.
@MainActor
@Observable
public final class WorkoutSessionStore {
    public private(set) var activeWorkout: Workout?
    public var isPresentingWorkout: Bool = false
    public var completedSummary: WorkoutSummaryData?

    // Rest timer (tenet 1: rest runs itself)
    public private(set) var restEndsAt: Date?
    public private(set) var restTotalSeconds: Int = 0
    public var isResting: Bool { restEndsAt.map { $0 > .now } ?? false }

    private let container: ModelContainer
    private let settings: UserSettingsStore
    private let progression: ProgressionStore

    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer, settings: UserSettingsStore, progression: ProgressionStore) {
        self.container = container
        self.settings = settings
        self.progression = progression
        resumeOngoingWorkoutIfAny()
    }

    // MARK: Lifecycle

    private func resumeOngoingWorkoutIfAny() {
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil })
        if let ongoing = (try? context.fetch(descriptor))?.first {
            activeWorkout = ongoing
            isPresentingWorkout = true
        }
    }

    public func quickStart(title: String = "Workout") {
        let workout = Workout(title: title)
        context.insert(workout)
        try? context.save()
        activeWorkout = workout
        isPresentingWorkout = true
        Haptics.medium()
    }

    public func start(routine: Routine) {
        let workout = Workout(title: routine.name)
        workout.routineID = routine.id
        workout.routineNameSnapshot = routine.name
        context.insert(workout)

        for (index, routineExercise) in routine.orderedExercises.enumerated() {
            guard let exercise = fetchExercise(id: routineExercise.exerciseID) else { continue }
            let workoutExercise = WorkoutExercise(orderIndex: index, exercise: exercise)
            workoutExercise.restSeconds = routineExercise.restSeconds
            workoutExercise.workout = workout
            context.insert(workoutExercise)
        }
        try? context.save()
        activeWorkout = workout
        isPresentingWorkout = true
        Haptics.medium()
    }

    public func addExercise(_ exercise: Exercise) {
        guard let workout = activeWorkout else { return }
        let index = (workout.orderedExercises.last?.orderIndex ?? -1) + 1
        let workoutExercise = WorkoutExercise(orderIndex: index, exercise: exercise)
        workoutExercise.workout = workout
        context.insert(workoutExercise)
        touchAndSave(workout)
    }

    /// Commit a set (tenet 2: one tap of the checkmark) and auto-start rest (tenet 1).
    /// `notes` is the optional per-set note staged in the entry row's note sheet.
    public func logSet(on workoutExercise: WorkoutExercise, weightGrams: Int, reps: Int,
                       isWarmup: Bool = false, notes: String? = nil) {
        let index = (workoutExercise.orderedSets.last?.orderIndex ?? -1) + 1
        let set = SetEntry(orderIndex: index, weightGrams: weightGrams,
                           entryUnit: settings.unit, reps: reps, isWarmup: isWarmup)
        set.notes = notes
        set.workoutExercise = workoutExercise
        context.insert(set)
        if let workout = activeWorkout { touchAndSave(workout) }
        startRest(seconds: workoutExercise.restSeconds ?? settings.defaultRestSeconds)
        Haptics.light()
    }

    public func startRest(seconds: Int) {
        restTotalSeconds = seconds
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(seconds))
        Haptics.rigid()
    }

    public func adjustRest(by delta: Int) {
        guard let ends = restEndsAt else { return }
        restEndsAt = ends.addingTimeInterval(TimeInterval(delta))
        restTotalSeconds = max(0, restTotalSeconds + delta)
        Haptics.selection()
    }

    public func skipRest() {
        restEndsAt = nil
    }

    // MARK: Set Player queue support (v3.1 — all derived, nothing stored)

    /// Ghost values for `slot` of `workoutExercise` — the ONE resolution order shared
    /// by the Set Player and the legacy `SetEntryRow`: reference set at the same index
    /// (most recent finished workout with this exercise), else the last set logged this
    /// session, else the last reference set, else the routine's planned target, else a
    /// bare 0 g × 10 default.
    public func ghostValues(for workoutExercise: WorkoutExercise, slot: Int) -> (weightGrams: Int, reps: Int) {
        let references = previousSets(exerciseID: workoutExercise.exerciseID,
                                      excluding: workoutExercise.workout?.id)
        if slot >= 0 && slot < references.count {
            return (references[slot].weightGrams, references[slot].reps)
        }
        if let last = workoutExercise.orderedSets.last {
            return (last.weightGrams, last.reps)
        }
        if let reference = references.last {
            return (reference.weightGrams, reference.reps)
        }
        if let planned = plannedTarget(for: workoutExercise, at: slot) {
            return planned
        }
        return (0, 10)
    }

    /// Planned-set count from the source routine — 0 for quick-start workouts or
    /// exercises added mid-session that the routine never planned.
    public func plannedSetCount(for workoutExercise: WorkoutExercise) -> Int {
        routineExercise(for: workoutExercise)?.orderedPlannedSets.count ?? 0
    }

    /// The routine's PlannedSet target for `slot` (its last one when past the plan).
    /// nil when the workout is plan-less or the exercise isn't in the routine.
    public func plannedTarget(for workoutExercise: WorkoutExercise, at slot: Int) -> (weightGrams: Int, reps: Int)? {
        guard let routineExercise = routineExercise(for: workoutExercise) else { return nil }
        let planned = routineExercise.orderedPlannedSets
        guard !planned.isEmpty else { return nil }
        let target = slot >= 0 && slot < planned.count ? planned[slot] : planned[planned.count - 1]
        return (target.targetWeightGrams ?? 0, target.targetReps)
    }

    /// Resolve the RoutineExercise behind a WorkoutExercise: fetch the Routine by the
    /// workout's loose `routineID`, match by exerciseID (orderIndex as fallback).
    private func routineExercise(for workoutExercise: WorkoutExercise) -> RoutineExercise? {
        guard let workout = workoutExercise.workout,
              let routineID = workout.routineID else { return nil }
        var descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == routineID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        guard let routine = (try? context.fetch(descriptor))?.first else { return nil }

        let exerciseID = workoutExercise.exerciseID
        let orderIndex = workoutExercise.orderIndex
        return routine.orderedExercises.first { $0.exerciseID == exerciseID }
            ?? routine.orderedExercises.first { $0.orderIndex == orderIndex }
    }

    /// The reference workout for ghost autofill: most recent finished workout containing this exercise.
    public func previousSets(exerciseID: UUID, excluding workoutID: UUID?) -> [SetEntry] {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let workouts = (try? context.fetch(descriptor)) ?? []
        for workout in workouts where workout.deletedAt == nil && workout.endedAt != nil && workout.id != workoutID {
            if let match = workout.orderedExercises.first(where: { $0.exerciseID == exerciseID }) {
                let sets = match.orderedSets.filter { !$0.isWarmup }
                if !sets.isEmpty { return sets }
            }
        }
        return []
    }

    public func finishWorkout() {
        guard let workout = activeWorkout else { return }
        let plBefore = progression.snapshotPowerLevel

        workout.endedAt = .now
        touchAndSave(workout)

        // Transformation tier of the ACTIVE character: same before/after diff as
        // badges/XP — the summary's ceiling-break stage keys off this delta.
        let activeCharacter = context.saiyanState().characterKey
        let tierBefore = progression.tier(for: activeCharacter)

        let badgesBefore = earnedBadgeKeys()
        let xpBefore = progression.snapshot?.characterXP ?? [:]
        progression.recompute(context: context)
        let badgesAfter = earnedBadgeKeys()
        let newBadges = badgesAfter.subtracting(badgesBefore).sorted()
        let tierAfter = progression.tier(for: activeCharacter)

        // XP transparency: same before/after diff as badges, per character.
        let xpAfter = progression.snapshot?.characterXP ?? [:]
        var xpEarned: [CharacterKey: Int] = [:]
        for (character, xp) in xpAfter {
            let delta = xp - (xpBefore[character] ?? 0)
            if delta > 0 { xpEarned[character] = delta }
        }

        // Net vs previous same-exercise sessions (workout-level rollup).
        let samples = SampleExtractor.setSamples(context: context)
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: workout.id)

        let facts = CommentaryFacts(
            title: workout.title,
            netReps: net.reps,
            netVolumeGrams: net.volumeGrams,
            netIsNew: net.isNew,
            newBadgeCount: newBadges.count,
            powerLevelDelta: progression.snapshotPowerLevel - plBefore
        )
        let (commentary, source) = CommentaryFallback.generate(facts: facts)

        let insight = AIInsight(kind: .postWorkout, periodStart: workout.startedAt,
                                periodEnd: workout.endedAt ?? .now, workoutID: workout.id,
                                body: commentary, source: source)
        context.insert(insight)
        try? context.save()

        let duration = Int((workout.endedAt ?? .now).timeIntervalSince(workout.startedAt)) - workout.pausedSeconds

        completedSummary = WorkoutSummaryData(
            id: workout.id,
            title: workout.title,
            durationSeconds: max(0, duration),
            powerLevelBefore: plBefore,
            powerLevelAfter: progression.snapshotPowerLevel,
            tierBefore: tierBefore.rawValue,
            tierAfter: tierAfter.rawValue,
            netReps: net.reps,
            netVolumeGrams: net.volumeGrams,
            netIsNew: net.isNew,
            newBadgeKeys: newBadges,
            xpEarned: xpEarned,
            commentary: commentary,
            commentarySource: source
        )
        activeWorkout = nil
        isPresentingWorkout = false
        restEndsAt = nil
        Haptics.success()
    }

    public func cancelWorkout() {
        guard let workout = activeWorkout else { return }
        workout.deletedAt = .now
        touchAndSave(workout)
        activeWorkout = nil
        isPresentingWorkout = false
        restEndsAt = nil
    }

    // MARK: Helpers

    /// Resolve the Exercise row behind a loose `exerciseID` reference (public so
    /// session views can surface Exercise-level fields like the machine setup).
    public func fetchExercise(id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func earnedBadgeKeys() -> Set<String> {
        let awards = (try? context.fetch(FetchDescriptor<BadgeAward>())) ?? []
        return Set(awards.filter { $0.deletedAt == nil }.map(\.badgeKey))
    }

    private func touchAndSave(_ workout: Workout) {
        workout.updatedAt = .now
        workout.needsPush = true
        try? context.save()
    }
}
