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
    public func logSet(on workoutExercise: WorkoutExercise, weightGrams: Int, reps: Int, isWarmup: Bool = false) {
        let index = (workoutExercise.orderedSets.last?.orderIndex ?? -1) + 1
        let set = SetEntry(orderIndex: index, weightGrams: weightGrams,
                           entryUnit: settings.unit, reps: reps, isWarmup: isWarmup)
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

        let badgesBefore = earnedBadgeKeys()
        progression.recompute(context: context)
        let badgesAfter = earnedBadgeKeys()
        let newBadges = badgesAfter.subtracting(badgesBefore).sorted()

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
            netReps: net.reps,
            netVolumeGrams: net.volumeGrams,
            netIsNew: net.isNew,
            newBadgeKeys: newBadges,
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

    private func fetchExercise(id: UUID) -> Exercise? {
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
