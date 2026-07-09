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
    /// The most recent log's readback payload, staged at LOG time for the REST
    /// overlay (or the zero-rest in-place overlay) to render. Internal — its type
    /// lives in the app module, not SettCore.
    var lastReadback: LoggedReadback?

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
        workout.domainRaw = routine.domainRaw   // the routine's realm (nil ⇒ app default)
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
                       isWarmup: Bool = false, notes: String? = nil, setting: String? = nil) {
        let index = (workoutExercise.orderedSets.last?.orderIndex ?? -1) + 1
        let set = SetEntry(orderIndex: index, weightGrams: weightGrams,
                           entryUnit: settings.unit, reps: reps, isWarmup: isWarmup)
        set.notes = notes
        set.setting = setting
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
    /// by the Set Player and the legacy `SetEntryRow`. Routines carry NO targets, so
    /// this is pure history: reference set at the same index (most recent finished
    /// workout with this exercise), else the last set logged this session, else the
    /// last reference set, else a bare 0 g × 10 default. Nothing to beat but yourself.
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
        return (0, 10)
    }

    /// Everything the Set Player needs about the previous session's set at this slot:
    /// the reference weight/reps (for the live aura preview), the note and machine
    /// setting to AUTO-POPULATE, and the all-time prior best e1RM (for the PR line).
    /// One resolution, fetched once when the pane loads. `weightGrams == nil` ⇒ no
    /// reference at this slot; note/setting still fall back to the most recent set.
    struct SlotReference: Equatable {
        var weightGrams: Int?
        var reps: Int?
        var note: String?
        var setting: String?
        var priorBestE1RMGrams: Int
        var hasReference: Bool { weightGrams != nil }
    }

    func slotReference(for workoutExercise: WorkoutExercise, slot: Int) -> SlotReference {
        let references = previousSets(exerciseID: workoutExercise.exerciseID,
                                      excluding: workoutExercise.workout?.id)
        let priorBest = bestPriorE1RMGrams(exerciseID: workoutExercise.exerciseID,
                                           excluding: workoutExercise.workout?.id)
        if slot >= 0 && slot < references.count {
            let r = references[slot]
            return SlotReference(weightGrams: r.weightGrams, reps: r.reps,
                                 note: r.notes, setting: r.setting,
                                 priorBestE1RMGrams: priorBest)
        }
        let last = references.last
        return SlotReference(weightGrams: nil, reps: nil,
                             note: last?.notes, setting: last?.setting,
                             priorBestE1RMGrams: priorBest)
    }

    /// The number of sets the source routine plans for this exercise — the authoritative
    /// `RoutineExercise.plannedSetCount`. 0 for quick-start workouts or exercises added
    /// mid-session that the routine never planned (the queue then follows logged+1).
    public func plannedSetCount(for workoutExercise: WorkoutExercise) -> Int {
        guard let re = routineExercise(for: workoutExercise) else { return 0 }
        // Legacy rows may predate plannedSetCount; fall back to old PlannedSet rows.
        return re.plannedSetCount > 0 ? re.plannedSetCount : re.orderedPlannedSets.count
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
        for workout in workouts where workout.deletedAt == nil && workout.endedAt != nil
            && !workout.isCasual && workout.id != workoutID {
            if let match = workout.orderedExercises.first(where: { $0.exerciseID == exerciseID }) {
                let sets = match.orderedSets.filter { !$0.isWarmup }
                if !sets.isEmpty { return sets }
            }
        }
        return []
    }

    // MARK: Set readback (item 4 — delta vs the reference set at the same slot)

    /// A just-logged set's delta against the reference (previous same-exercise
    /// session) set at the same slot — the mirror of the crit reference rule.
    /// `isBaseline` when there is no reference at that slot. Compute BEFORE logging.
    func readback(for workoutExercise: WorkoutExercise, slot: Int,
                  weightGrams: Int, reps: Int) -> SetReadback {
        let e1RM = ProgressEngine.e1RMGrams(weightGrams: weightGrams, reps: reps)
        let priorBest = bestPriorE1RMGrams(exerciseID: workoutExercise.exerciseID,
                                           excluding: workoutExercise.workout?.id)
        let isPR = e1RM > priorBest
        let references = previousSets(exerciseID: workoutExercise.exerciseID,
                                      excluding: workoutExercise.workout?.id)
        guard slot >= 0 && slot < references.count else {
            return SetReadback(weightDeltaGrams: nil, repsDelta: nil, isBaseline: true,
                               e1RMGrams: e1RM, referenceE1RMGrams: nil,
                               e1RMDeltaGrams: nil, isPersonalBest: isPR)
        }
        let reference = references[slot]
        let refE1RM = ProgressEngine.e1RMGrams(weightGrams: reference.weightGrams,
                                               reps: reference.reps)
        return SetReadback(weightDeltaGrams: weightGrams - reference.weightGrams,
                           repsDelta: reps - reference.reps,
                           isBaseline: false,
                           e1RMGrams: e1RM, referenceE1RMGrams: refE1RM,
                           e1RMDeltaGrams: e1RM - refE1RM, isPersonalBest: isPR)
    }

    /// Best e1RM ever recorded for this exercise across finished, non-casual,
    /// non-warmup sets (excluding the in-progress workout) — the PR baseline.
    /// 0 when the exercise has no prior history.
    private func bestPriorE1RMGrams(exerciseID: UUID, excluding workoutID: UUID?) -> Int {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)])
        let workouts = (try? context.fetch(descriptor)) ?? []
        var best = 0
        for workout in workouts
        where workout.deletedAt == nil && workout.endedAt != nil
            && !workout.isCasual && workout.id != workoutID {
            for we in workout.orderedExercises where we.exerciseID == exerciseID {
                for set in we.orderedSets where !set.isWarmup {
                    best = max(best, ProgressEngine.e1RMGrams(weightGrams: set.weightGrams,
                                                              reps: set.reps))
                }
            }
        }
        return best
    }

    // MARK: Motivation context (between-exercise quotes)

    /// Reads the lifter's situation for a between-exercise line: a long layoff,
    /// short sleep, low readiness, or a session that's grinding — else just push.
    func motivationContext() -> MotivationContext {
        guard let workout = activeWorkout else { return .push }

        // Comeback: > 14 days since the last finished, non-casual workout.
        if let prevEnd = lastFinishedWorkoutEnd(before: workout),
           workout.startedAt.timeIntervalSince(prevEnd) > 14 * 86_400 {
            return .comeback
        }

        // Sleep / readiness (Oura), keyed to the workout's day.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let key = cal.dateKey(for: workout.startedAt)
        var descriptor = FetchDescriptor<SleepDay>(predicate: #Predicate { $0.dateKey == key })
        descriptor.fetchLimit = 1
        if let sleep = (try? context.fetch(descriptor))?.first {
            if let score = sleep.sleepScore, score < 60 { return .lowSleep }
            if let readiness = sleep.readinessScore, readiness < 60 { return .offDay }
        }

        // The session itself is grinding — majority of scored sets down vs last time.
        if isSessionUnderperforming(workout) { return .offDay }
        return .push
    }

    private func lastFinishedWorkoutEnd(before workout: Workout) -> Date? {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let workouts = (try? context.fetch(descriptor)) ?? []
        for candidate in workouts
        where candidate.deletedAt == nil && candidate.endedAt != nil && !candidate.isCasual
            && candidate.id != workout.id && candidate.startedAt < workout.startedAt {
            return candidate.endedAt
        }
        return nil
    }

    private func isSessionUnderperforming(_ workout: Workout) -> Bool {
        var scored = 0, down = 0
        for we in workout.orderedExercises {
            let refs = previousSets(exerciseID: we.exerciseID, excluding: workout.id)
            let working = we.orderedSets.filter { !$0.isWarmup }
            for (index, set) in working.enumerated() where index < refs.count {
                scored += 1
                let e1RM = ProgressEngine.e1RMGrams(weightGrams: set.weightGrams, reps: set.reps)
                let refE1RM = ProgressEngine.e1RMGrams(weightGrams: refs[index].weightGrams,
                                                       reps: refs[index].reps)
                if e1RM < refE1RM { down += 1 }
            }
        }
        return scored >= 2 && down * 2 > scored
    }

    // MARK: Off the record (item 6 — casual toggle)

    /// Flip the active workout's casual flag under the standard sync rules. Turning
    /// on is confirmed by the caller; turning off is silent.
    func setCasual(_ isCasual: Bool) {
        guard let workout = activeWorkout, workout.isCasual != isCasual else { return }
        workout.isCasual = isCasual
        touchAndSave(workout)
        Haptics.selection()
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

        // Net vs previous same-exercise sessions (workout-level rollup). Casual
        // ("off the record") workouts skip net computation entirely — no nets of
        // their own, never a baseline for another workout.
        let isCasual = workout.isCasual
        let netReps: Int
        let netVolumeGrams: Int
        let netIsNew: Bool
        if isCasual {
            netReps = 0
            netVolumeGrams = 0
            netIsNew = false
        } else {
            let samples = SampleExtractor.setSamples(context: context)
            let net = ProgressEngine.workoutNet(samples: samples, workoutID: workout.id)
            netReps = net.reps
            netVolumeGrams = net.volumeGrams
            netIsNew = net.isNew
        }

        let facts = CommentaryFacts(
            title: workout.title,
            netReps: netReps,
            netVolumeGrams: netVolumeGrams,
            netIsNew: netIsNew,
            newBadgeCount: newBadges.count,
            powerLevelDelta: progression.snapshotPowerLevel - plBefore,
            isCasual: isCasual
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
            netReps: netReps,
            netVolumeGrams: netVolumeGrams,
            netIsNew: netIsNew,
            newBadgeKeys: newBadges,
            xpEarned: xpEarned,
            commentary: commentary,
            commentarySource: source,
            isCasual: isCasual,
            domainRaw: workout.domainRaw
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

// MARK: - Set readback payload

/// A logged set's comparison against the reference set at the same slot.
///
/// Per-set SCORING is driven by `e1RMDeltaGrams` — the single combined number that
/// prices the weight↔reps trade (a rep is worth ~w/(30+r) on the bar). The raw
/// `weightDeltaGrams`/`repsDelta` are kept only as human-readable narration chips.
/// `nil` deltas with `isBaseline == true` mean there was no reference to compare.
struct SetReadback: Equatable {
    let weightDeltaGrams: Int?
    let repsDelta: Int?
    let isBaseline: Bool
    /// This set's estimated 1RM (rep-capped Epley) — the per-set "output" scalar.
    let e1RMGrams: Int
    /// The reference set's e1RM; nil when baseline.
    let referenceE1RMGrams: Int?
    /// e1RMGrams − referenceE1RMGrams; nil when baseline. The scoring signal.
    let e1RMDeltaGrams: Int?
    /// This set's e1RM strictly exceeds the best PRIOR e1RM for this exercise
    /// (finished, non-casual, non-warmup sets). Drives the crit / gold PR moment.
    let isPersonalBest: Bool
}
