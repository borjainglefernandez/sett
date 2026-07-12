import Foundation
import SwiftData
import SwiftUI
import SettCore
@preconcurrency import ActivityKit

/// Owns the active workout lifecycle: start, log, rest timer, finish → Power Scan summary.
/// Presented app-wide as a fullScreenCover so it survives tab switches.
@MainActor
@Observable
public final class WorkoutSessionStore {
    public private(set) var activeWorkout: Workout?
    public var isPresentingWorkout: Bool = false
    public var completedSummary: WorkoutSummaryData?
    /// A SwiftData write on the session path failed — drives a diegetic "write fault"
    /// banner so a lost set is visible, not silent. Cleared by the next good save.
    public private(set) var saveFault = false
    /// The most recent log's readback payload, staged at LOG time for the REST
    /// overlay (or the zero-rest in-place overlay) to render. Internal — its type
    /// lives in the app module, not SettCore.
    var lastReadback: LoggedReadback?

    // Rest timer (tenet 1: rest runs itself)
    public private(set) var restEndsAt: Date?
    public private(set) var restTotalSeconds: Int = 0
    public var isResting: Bool { restEndsAt.map { $0 > .now } ?? false }
    /// The label carried into the rest-complete notification, kept so a ±time
    /// adjustment can reschedule the alert without the caller re-supplying it.
    private var restNextUp: String?
    /// The live rest countdown on the Dynamic Island + lock screen (stage 2).
    private var restActivity: Activity<RestActivityAttributes>?

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
        guard let ongoing = (try? context.fetch(descriptor))?.first else { return }
        // Abandoned? A workout with no activity for 6h+ was almost certainly left when
        // the app was killed mid-session. Seal it at its last logged set (or discard if
        // empty) instead of resuming a multi-day "session" that records a 72h duration.
        let lastActivity = ongoing.orderedExercises.flatMap { $0.orderedSets }.map(\.completedAt).max()
        let anchor = lastActivity ?? ongoing.startedAt
        if Date.now.timeIntervalSince(anchor) > 6 * 3600 {
            if lastActivity == nil {
                ongoing.deletedAt = .now          // empty + abandoned → discard
            } else {
                ongoing.endedAt = anchor          // seal at the last real activity
            }
            ongoing.updatedAt = .now
            ongoing.needsPush = true
            persist()
            return
        }
        activeWorkout = ongoing
        isPresentingWorkout = true
    }

    /// The lifter's most recent logged bodyweight, in grams — snapshotted onto each new
    /// workout so bodyweight lifts (pull-ups/dips) score against real mass rather than
    /// the 80 kg default. nil when they've never logged one (LoadMath then falls back).
    private func latestBodyweightGrams() -> Int? {
        var descriptor = FetchDescriptor<BodyweightEntry>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.weightGrams
    }

    public func quickStart(title: String = "Workout") {
        // Never orphan an in-progress workout: if one is live, resume it rather than
        // silently creating a second (which would vanish from every history query).
        if activeWorkout != nil { isPresentingWorkout = true; Haptics.medium(); return }
        let workout = Workout(title: title)
        workout.phaseRaw = settings.trainingPhase
        workout.bodyweightGrams = latestBodyweightGrams()
        context.insert(workout)
        persist()
        activeWorkout = workout
        isPresentingWorkout = true
        Haptics.medium()
    }

    public func start(routine: Routine) {
        if activeWorkout != nil { isPresentingWorkout = true; Haptics.medium(); return }
        let workout = Workout(title: routine.name)
        workout.routineID = routine.id
        workout.routineNameSnapshot = routine.name
        workout.domainRaw = routine.domainRaw   // the routine's realm (nil ⇒ app default)
        workout.phaseRaw = settings.trainingPhase
        workout.bodyweightGrams = latestBodyweightGrams()
        context.insert(workout)

        for (index, routineExercise) in routine.orderedExercises.enumerated() {
            guard let exercise = fetchExercise(id: routineExercise.exerciseID) else { continue }
            let workoutExercise = WorkoutExercise(orderIndex: index, exercise: exercise)
            workoutExercise.restSeconds = routineExercise.restSeconds
            workoutExercise.workout = workout
            context.insert(workoutExercise)
        }
        persist()
        activeWorkout = workout
        isPresentingWorkout = true
        Haptics.medium()
    }

    #if DEBUG
    /// DEBUG hook (env `SETT_DEBUG_OVERVIEW=1`): start the first routine and log a
    /// couple of sets — one noted — so the overview shows logged + planned + note rows
    /// for screenshotting. No-op if a workout is already live.
    public func debugStartOverviewDemo() {
        guard activeWorkout == nil else { isPresentingWorkout = true; return }
        let routines = (try? context.fetch(
            FetchDescriptor<Routine>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        guard let routine = routines.first else { return }
        start(routine: routine)
        // Insert directly (not logSet) so no rest timer / notification prompt fires.
        if let first = activeWorkout?.orderedExercises.first {
            let grams = Units.grams(fromDisplay: 135, unit: settings.unit)
            debugInsertSet(on: first, grams: grams, reps: 10, notes: "felt heavy, left side weaker")
            debugInsertSet(on: first, grams: grams, reps: 8, notes: nil)
            if let workout = activeWorkout { touchAndSave(workout) }
        }
    }

    private func debugInsertSet(on workoutExercise: WorkoutExercise, grams: Int, reps: Int, notes: String?) {
        let index = (workoutExercise.orderedSets.last?.orderIndex ?? -1) + 1
        let set = SetEntry(orderIndex: index, weightGrams: grams,
                           entryUnit: settings.unit, reps: reps, isWarmup: false)
        set.notes = notes
        set.workoutExercise = workoutExercise
        context.insert(set)
    }
    #endif

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
        startRest(seconds: workoutExercise.restSeconds ?? settings.defaultRestSeconds,
                  nextUp: workoutExercise.exerciseNameSnapshot)
        Haptics.light()
    }

    /// Fix a mis-logged set (wrong weight/reps/warmup). Mutates in place under the
    /// sync rules — the next progression recompute + reference fetch pick it up.
    public func editSet(_ set: SetEntry, weightGrams: Int, reps: Int, isWarmup: Bool) {
        set.weightGrams = weightGrams
        set.reps = reps
        set.isWarmup = isWarmup
        set.updatedAt = .now
        set.needsPush = true
        if let workout = set.workoutExercise?.workout ?? activeWorkout { touchAndSave(workout) }
        Haptics.selection()
    }

    /// Soft-delete a logged set (a fat-fingered 500 lb entry poisoned ghost autofill
    /// and the power level forever with no way to remove it).
    public func deleteSet(_ set: SetEntry) {
        set.deletedAt = .now
        set.updatedAt = .now
        set.needsPush = true
        if let workout = set.workoutExercise?.workout ?? activeWorkout { touchAndSave(workout) }
        Haptics.medium()
    }

    /// Duplicate a logged set (right-swipe / "Duplicate set"): clone it into the slot
    /// right after the original. Opens the slot FIRST — every sibling at or past the
    /// clone's index shifts +1 — so the clone and its old neighbour never collide, and
    /// `logSet`'s `last.orderIndex + 1` next-set assumption still holds after a
    /// mid-exercise copy. Clones `entryUnit` (NOT settings.unit — that would relabel an
    /// old kg set as lb), plus notes/setting/warm-up.
    public func duplicateSet(_ set: SetEntry) {
        guard let we = set.workoutExercise else { return }
        let insertIndex = set.orderIndex + 1
        for sibling in we.orderedSets where sibling.orderIndex >= insertIndex {
            sibling.orderIndex += 1
            sibling.updatedAt = .now
            sibling.needsPush = true
        }
        let copy = SetEntry(orderIndex: insertIndex, weightGrams: set.weightGrams,
                            entryUnit: set.entryUnit, reps: set.reps, isWarmup: set.isWarmup)
        copy.notes = set.notes
        copy.setting = set.setting
        copy.workoutExercise = we
        context.insert(copy)
        if let workout = we.workout ?? activeWorkout { touchAndSave(workout) }
        Haptics.medium()
    }

    /// Reorder sets WITHIN an exercise (`.onMove`). Densifies `orderIndex` 0..<n over the
    /// filtered/sorted `orderedSets`, stamping only rows whose index actually moved
    /// (which also self-heals any prior gaps).
    public func moveSet(in workoutExercise: WorkoutExercise, from source: IndexSet, to destination: Int) {
        var ordered = workoutExercise.orderedSets
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, set) in ordered.enumerated() where set.orderIndex != index {
            set.orderIndex = index
            set.updatedAt = .now
            set.needsPush = true
        }
        if let workout = workoutExercise.workout ?? activeWorkout { touchAndSave(workout) }
        Haptics.selection()
    }

    /// Reorder the exercise cards (`.onMove`). Same densify-and-stamp discipline over
    /// `orderedExercises`.
    public func moveExercise(in workout: Workout, from source: IndexSet, to destination: Int) {
        var ordered = workout.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in ordered.enumerated() where exercise.orderIndex != index {
            exercise.orderIndex = index
            exercise.updatedAt = .now
            exercise.needsPush = true
        }
        touchAndSave(workout)
        Haptics.selection()
    }

    public func startRest(seconds: Int, nextUp: String? = nil) {
        restTotalSeconds = seconds
        let ends = Date.now.addingTimeInterval(TimeInterval(seconds))
        restEndsAt = ends
        restNextUp = nextUp
        // Beyond the app boundary (tenet 1): schedule a lock-screen alert for when
        // rest ends. Auth is requested lazily here so the prompt lands in context.
        RestNotifier.requestAuthorizationIfNeeded()
        RestNotifier.scheduleRestComplete(at: ends, nextUp: nextUp)
        startOrUpdateRestActivity(endsAt: ends, nextUp: nextUp)
        Haptics.rigid()
    }

    // MARK: Rest Live Activity (Dynamic Island + lock-screen countdown)

    private func startOrUpdateRestActivity(endsAt: Date, nextUp: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(
            state: RestActivityAttributes.ContentState(endsAt: endsAt, nextUp: nextUp),
            staleDate: endsAt)
        if let activity = restActivity {
            Task { await activity.update(content) }
        } else {
            let attributes = RestActivityAttributes(workoutTitle: activeWorkout?.title ?? "Workout")
            restActivity = try? Activity.request(attributes: attributes, content: content)
        }
    }

    private func endRestActivity() {
        guard let activity = restActivity else { return }
        restActivity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    public func adjustRest(by delta: Int) {
        guard let ends = restEndsAt else { return }
        let newEnds = ends.addingTimeInterval(TimeInterval(delta))
        restEndsAt = newEnds
        restTotalSeconds = max(0, restTotalSeconds + delta)
        RestNotifier.scheduleRestComplete(at: newEnds, nextUp: restNextUp)   // reschedule
        startOrUpdateRestActivity(endsAt: newEnds, nextUp: restNextUp)
        Haptics.selection()
    }

    public func skipRest() {
        restEndsAt = nil
        RestNotifier.cancelRestComplete()
        endRestActivity()
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
        // e1RM scores EFFECTIVE load (bodyweight exercises add the lifter's bodyweight);
        // the weight/reps delta chips stay in ADDED terms (they narrate the plate change).
        let bw = workoutExercise.workout?.bodyweightGrams
        let equipment = workoutExercise.equipment
        let e1RM = ProgressEngine.e1RMGrams(
            weightGrams: LoadMath.effectiveWeightGrams(addedGrams: weightGrams, equipment: equipment, bodyweightGrams: bw),
            reps: reps)
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
        let refEquip = reference.workoutExercise?.equipment ?? equipment
        let refBW = reference.workoutExercise?.workout?.bodyweightGrams ?? bw
        let refE1RM = ProgressEngine.e1RMGrams(
            weightGrams: LoadMath.effectiveWeightGrams(addedGrams: reference.weightGrams, equipment: refEquip, bodyweightGrams: refBW),
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
                    let eff = LoadMath.effectiveWeightGrams(
                        addedGrams: set.weightGrams, equipment: we.equipment,
                        bodyweightGrams: workout.bodyweightGrams)
                    best = max(best, ProgressEngine.e1RMGrams(weightGrams: eff, reps: set.reps))
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

        // A cut reframes the whole session — its lines also cover low-energy days.
        if workout.phase == .cutting { return .cutting }

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
                let e1RM = ProgressEngine.e1RMGrams(
                    weightGrams: LoadMath.effectiveWeightGrams(addedGrams: set.weightGrams, equipment: we.equipment, bodyweightGrams: workout.bodyweightGrams),
                    reps: set.reps)
                let ref = refs[index]
                let refE1RM = ProgressEngine.e1RMGrams(
                    weightGrams: LoadMath.effectiveWeightGrams(addedGrams: ref.weightGrams, equipment: ref.workoutExercise?.equipment ?? we.equipment, bodyweightGrams: ref.workoutExercise?.workout?.bodyweightGrams ?? workout.bodyweightGrams),
                    reps: ref.reps)
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

    /// In rotation mode, completing the routine that was "next up" advances the split
    /// pointer to the next routine (day-agnostic). Off-rotation workouts don't advance.
    private func advanceRotationIfNeeded(finished workout: Workout) {
        guard settings.scheduleMode == .rotation, let routineID = workout.routineID else { return }
        let all = (try? context.fetch(FetchDescriptor<Routine>(
            predicate: #Predicate { $0.deletedAt == nil && !$0.isArchived }))) ?? []
        let active = Scheduling.orderedActive(all)
        guard !active.isEmpty else { return }
        // Only advance when the completed workout WAS the routine the cursor pointed at;
        // then move the identity cursor to the next routine in order (wrapping).
        guard Scheduling.nextRoutine(all, settings: settings)?.id == routineID,
              let idx = active.firstIndex(where: { $0.id == routineID }) else { return }
        settings.rotationRoutineID = active[(idx + 1) % active.count].id.uuidString
    }

    public func finishWorkout() {
        guard let workout = activeWorkout else { return }
        // Prune exercises opened but never logged into — they'd clutter history and
        // the recap with empty entries.
        for we in workout.orderedExercises where we.orderedSets.isEmpty {
            we.deletedAt = .now
            we.updatedAt = .now
            we.needsPush = true
        }
        let plBefore = progression.snapshotPowerLevel

        // Seal the workout FIRST and require the write to land. If it fails, keep the
        // session presented so the write-fault banner offers retrySave — do NOT credit
        // PL/XP/badges or present the summary against a workout whose endedAt never
        // persisted (which resumeOngoingWorkoutIfAny would otherwise resurrect).
        workout.endedAt = .now
        workout.updatedAt = .now
        workout.needsPush = true
        guard persist() else { return }
        advanceRotationIfNeeded(finished: workout)

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
        persist()

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
        RestNotifier.cancelRestComplete()
        endRestActivity()
        Haptics.success()
    }

    public func cancelWorkout() {
        guard let workout = activeWorkout else { return }
        workout.deletedAt = .now
        touchAndSave(workout)
        activeWorkout = nil
        isPresentingWorkout = false
        restEndsAt = nil
        RestNotifier.cancelRestComplete()
        endRestActivity()
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
        persist()
    }

    /// Save, surfacing failures instead of swallowing them (the old `try? save()` let
    /// the rest timer start and the ceremony play while nothing persisted). Sets
    /// `saveFault` on failure; a good save clears it. The banner offers a retry.
    @discardableResult
    private func persist() -> Bool {
        do {
            try context.save()
            if saveFault { saveFault = false }
            return true
        } catch {
            #if DEBUG
            print("⚠️ SwiftData save failed:", error)
            #endif
            saveFault = true
            return false
        }
    }

    /// Retry the last failed save (from the write-fault banner).
    public func retrySave() { persist() }
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
