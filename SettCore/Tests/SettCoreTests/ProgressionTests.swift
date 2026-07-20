import Foundation
import SwiftData
import Testing
@testable import SettCore

// MARK: - Fixed clock & calendar (never Date.now for engine inputs)

/// Gregorian, Monday-first, ISO-style week rule, pinned to Madrid — the app's convention.
private func madridCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
    cal.firstWeekday = 2
    cal.minimumDaysInFirstWeek = 4
    return cal
}

private func date(_ year: Int, _ month: Int, _ day: Int,
                  _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var c = DateComponents()
    c.year = year
    c.month = month
    c.day = day
    c.hour = hour
    c.minute = minute
    return madridCalendar().date(from: c)!
}

// MARK: - Sample builders

private let benchID = UUID()
private let rowID = UUID()

private func workout(_ id: UUID, start: Date, minutes: Int = 60,
                     title: String = "Workout", routineID: UUID? = nil) -> WorkoutSample {
    WorkoutSample(id: id, title: title, startedAt: start,
                  endedAt: start.addingTimeInterval(Double(minutes) * 60),
                  bodyweightGrams: nil, routineID: routineID)
}

/// `count` identical working sets starting 5 minutes into the workout, 5 minutes apart.
private func sets(_ exerciseID: UUID, muscle: Muscle, grams: Int, reps: Int,
                  count: Int, workout: WorkoutSample) -> [SetSample] {
    (0..<count).map { index in
        SetSample(exerciseID: exerciseID, muscle: muscle, weightGrams: grams, reps: reps,
                  isWarmup: false,
                  completedAt: workout.startedAt.addingTimeInterval(Double(300 + index * 300)),
                  workoutID: workout.id)
    }
}

private func input(workouts: [WorkoutSample], sets: [SetSample],
                   sleep: [SleepSample] = [], goals: [GoalSample] = [],
                   previousPeakPL: Int = 0) -> ProgressionInput {
    ProgressionInput(sets: sets, workouts: workouts, sleep: sleep, goals: goals,
                     previousPeakPL: previousPeakPL,
                     firstWorkoutDate: workouts.map(\.startedAt).min())
}

private func loadConfig() throws -> ProgressionConfig {
    try ProgressionConfig.load()
}

// MARK: - Design-doc week-1 worked example

@Suite("ProgressionEngine — Power Level")
struct PowerLevelTests {

    /// Design doc §1.4: new user, week 1, 2 workouts (chest + back), PL ≈ 2,390.
    /// Bench 187.5 lb × 6 (e1RM 225 lb) × 4 sets; row 214.29 lb × 5 (e1RM 250 lb) × 6 sets.
    @Test("Week-1 worked example lands within ±5% of 2,390")
    func week1Example() throws {
        let config = try loadConfig()
        let cal = madridCalendar()

        let wA = workout(UUID(), start: date(2025, 6, 2, 18))   // Monday
        let wB = workout(UUID(), start: date(2025, 6, 4, 18))   // Wednesday
        let allSets = sets(benchID, muscle: .chest, grams: 85_049, reps: 6, count: 4, workout: wA)
            + sets(rowID, muscle: .back, grams: 97_198, reps: 5, count: 6, workout: wB)
        let asOf = date(2025, 6, 5, 20)                          // Thursday, same week

        let snapshot = ProgressionEngine.compute(input: input(workouts: [wA, wB], sets: allSets),
                                                 config: config, calendar: cal, asOf: asOf)

        // SS = 225 + 250 = 475 lb; WVL = 10,928.6 / 4 = 2,732 lb;
        // in-progress week already has 2 qualifying days -> streak 1, CM 1.05;
        // PL = round((4×475 + 8×√2732.1) × 1.05) = 2,434 — inside 2,390 ± 5%.
        #expect(abs(snapshot.powerLevel - 2390) <= Int(Double(2390) * 0.05))
        #expect(snapshot.strengthScore == 475)
        #expect(snapshot.weeklyVolumeLb == 2732)
        #expect(snapshot.streakWeeks == 1)
        #expect(abs(snapshot.consistencyMultiplier - 1.05) < 1e-9)
        #expect(snapshot.allTimePeakPL == snapshot.powerLevel)

        // First workout ever -> ignition (Nyra's bronze).
        #expect(snapshot.badges.contains { $0.key == "ignition" })
        #expect(!snapshot.badges.contains { $0.key == "new_ceiling" })

        // XP: day 1 = 50 + 4×2 + 25 = 83; day 2 = 50 + 6×2 + 25 = 87, and Wednesday
        // follows a true rest day (Tuesday) inside an active period, so the rested
        // bonus applies: round(87 × 1.25) = 109 -> vego 192.
        // Nyra: ignition badge (bronze 100), no completed streak weeks yet.
        // Barok tonnage drip: 4,500 lb -> 4 XP, 6,429 lb -> 6 XP.

        // Vexeth: 3 days since first workout -> week 0 -> startPL; user below him.
        #expect(snapshot.rivalPL == 3000)
        #expect(snapshot.rivalForm == 1)
    }

    @Test("No qualifying workouts -> PL 0 and rival at startPL")
    func emptyInput() throws {
        let config = try loadConfig()
        let snapshot = ProgressionEngine.compute(
            input: input(workouts: [], sets: []),
            config: config, calendar: madridCalendar(), asOf: date(2025, 6, 5))
        #expect(snapshot.powerLevel == 0)
        #expect(snapshot.badges.isEmpty)
        #expect(snapshot.rivalPL == 3000)
        #expect(snapshot.rivalForm == 1)
        // No training days -> nothing to plot.
        #expect(snapshot.powerLevelHistory.isEmpty)
    }

    @Test("powerLevelHistory: one point per training day, date-ordered, ends at live PL")
    func powerLevelHistoryShape() throws {
        let config = try loadConfig()
        let cal = madridCalendar()

        // Three qualifying days, TWO of them on the same calendar day (Monday) —
        // the same-day pair must collapse to one point, not two.
        let wMonAM = workout(UUID(), start: date(2025, 6, 2, 9))
        let wMonPM = workout(UUID(), start: date(2025, 6, 2, 18))
        let wWed = workout(UUID(), start: date(2025, 6, 4, 18))
        let wMon2 = workout(UUID(), start: date(2025, 6, 9, 18))   // next Monday
        let allSets =
            sets(benchID, muscle: .chest, grams: 85_049, reps: 6, count: 4, workout: wMonAM)
            + sets(rowID, muscle: .back, grams: 97_198, reps: 5, count: 6, workout: wMonPM)
            + sets(benchID, muscle: .chest, grams: 90_000, reps: 6, count: 4, workout: wWed)
            + sets(rowID, muscle: .back, grams: 100_000, reps: 5, count: 6, workout: wMon2)
        let asOf = date(2025, 6, 11, 20)

        let snapshot = ProgressionEngine.compute(
            input: input(workouts: [wMonAM, wMonPM, wWed, wMon2], sets: allSets),
            config: config, calendar: cal, asOf: asOf)

        let history = snapshot.powerLevelHistory
        // 3 distinct training days (Mon 6/2, Wed 6/4, Mon 6/9) collapse to 3 points;
        // the trailing asOf (6/11, no session) is its own day -> at most one extra.
        let dayKeys = history.map { cal.dateKey(for: $0.date) }
        #expect(Set(dayKeys).count == dayKeys.count)           // no duplicate days
        #expect(history.count >= 3)                            // the three training days survive
        // Chronological, oldest first.
        #expect(history.map(\.date) == history.map(\.date).sorted())
        // The last point is the live PL, and the series never exceeds the peak.
        #expect(history.last?.pl == snapshot.powerLevel)
        #expect(history.map(\.pl).max()! <= snapshot.allTimePeakPL)
    }
}

// MARK: - Junk-volume defenses

@Suite("ProgressionEngine — junk defenses")
struct JunkDefenseTests {

    /// 100-rep empty-bar sets are outside the rep bounds and never effective.
    @Test("A 100-rep set contributes no volume")
    func hundredRepSetIsNotEffective() throws {
        let config = try loadConfig()
        let w = workout(UUID(), start: date(2025, 6, 2, 18))
        var allSets = sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w)
        allSets.append(SetSample(exerciseID: benchID, muscle: .chest, weightGrams: 20_000,
                                 reps: 100, isWarmup: false,
                                 completedAt: w.startedAt.addingTimeInterval(1800),
                                 workoutID: w.id))
        let snapshot = ProgressionEngine.compute(input: input(workouts: [w], sets: allSets),
                                                 config: config, calendar: madridCalendar(),
                                                 asOf: date(2025, 6, 2, 20))
        // Only 3×100kg×5 = 1,500,000 g·reps = 3,306.9 lb -> WVL 827.
        #expect(snapshot.weeklyVolumeLb == 827)
    }

    @Test("The 7th set of an exercise in one workout is ignored")
    func seventhSetIgnored() throws {
        let config = try loadConfig()
        let w = workout(UUID(), start: date(2025, 6, 2, 18))
        let allSets = sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 7, workout: w)
        let snapshot = ProgressionEngine.compute(input: input(workouts: [w], sets: allSets),
                                                 config: config, calendar: madridCalendar(),
                                                 asOf: date(2025, 6, 2, 20))
        // 6 counted sets: 3,000,000 g·reps = 6,613.9 lb -> WVL 1,653.
        #expect(snapshot.weeklyVolumeLb == 1653)
    }

    @Test("Second workout of the same day yields no effective volume")
    func secondSameDayWorkout() throws {
        let config = try loadConfig()
        let w1 = workout(UUID(), start: date(2025, 6, 2, 10))
        let w2 = workout(UUID(), start: date(2025, 6, 2, 18))
        let allSets = sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w1)
            + sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w2)
        let snapshot = ProgressionEngine.compute(input: input(workouts: [w1, w2], sets: allSets),
                                                 config: config, calendar: madridCalendar(),
                                                 asOf: date(2025, 6, 2, 20))
        // Volume counts only the first qualifying workout of the day.
        #expect(snapshot.weeklyVolumeLb == 827)
        // One distinct qualifying day -> no streak yet.
        #expect(snapshot.streakWeeks == 0)
        // XP: w1 = 50 + 6 + 25 = 81; w2 nets zero vs w1 -> (50 + 6) × 0.25 = 14.
    }
}

// MARK: - PR verification pipeline

@Suite("ProgressionEngine — PR pipeline")
struct PRPipelineTests {

    /// A >15% jump is quarantined as provisional (no PR, excluded from SS) until a
    /// later distinct calendar day lands within 10% of it or higher.
    @Test("Provisional jump verifies on a later day")
    func provisionalThenVerified() throws {
        let config = try loadConfig()
        let cal = madridCalendar()

        var workouts: [WorkoutSample] = []
        var allSets: [SetSample] = []
        // 3 prior distinct-day sessions at 100 kg × 5 (e1RM 116,667 g).
        for day in 2...4 {
            let w = workout(UUID(), start: date(2025, 6, day, 18))
            workouts.append(w)
            allSets += sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w)
        }
        // Day 4: 140 kg × 5 -> e1RM 163,333 g = +40% -> provisional.
        let jump = workout(UUID(), start: date(2025, 6, 5, 18))
        workouts.append(jump)
        allSets += sets(benchID, muscle: .chest, grams: 140_000, reps: 5, count: 3, workout: jump)

        let afterJump = ProgressionEngine.compute(
            input: input(workouts: workouts, sets: allSets),
            config: config, calendar: cal, asOf: date(2025, 6, 5, 20))
        // Not yet a PR, and SS still uses the old verified best (116,667 g = 257 lb).
        #expect(!afterJump.badges.contains { $0.key == "new_ceiling" })
        #expect(afterJump.strengthScore == 257)

        // Day 5: 135 kg × 5 -> e1RM 157,500 g, within 10% of 163,333 -> verified.
        let confirm = workout(UUID(), start: date(2025, 6, 6, 18))
        workouts.append(confirm)
        allSets += sets(benchID, muscle: .chest, grams: 135_000, reps: 5, count: 3, workout: confirm)

        let afterConfirm = ProgressionEngine.compute(
            input: input(workouts: workouts, sets: allSets),
            config: config, calendar: cal, asOf: date(2025, 6, 6, 20))
        let grant = afterConfirm.badges.first { $0.key == "new_ceiling" }
        #expect(grant != nil)
        #expect(grant?.exerciseID == benchID)
        #expect(grant?.valueSnapshot == 1)
        // Verified on the confirmation day, not the provisional day.
        if let earnedAt = grant?.earnedAt {
            #expect(cal.dateKey(for: earnedAt) == 20_250_606)
        }
        // SS now uses the verified 163,333 g = 360 lb.
        #expect(afterConfirm.strengthScore == 360)
    }

    @Test("A provisional mis-log doesn't inflate weekly volume (or PL) until verified")
    func misLogQuarantinedFromVolume() throws {
        let config = try loadConfig()
        let cal = madridCalendar()

        // Three distinct legit days of bench, 100 kg × 5 × 3.
        func legit() -> ([WorkoutSample], [SetSample]) {
            var w: [WorkoutSample] = []
            var s: [SetSample] = []
            for day in 2...4 {
                let wk = workout(UUID(), start: date(2025, 6, day, 18))
                w.append(wk)
                s += sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: wk)
            }
            return (w, s)
        }

        let (cw, cs) = legit()
        let control = ProgressionEngine.compute(
            input: input(workouts: cw, sets: cs),
            config: config, calendar: cal, asOf: date(2025, 6, 4, 20))

        // Same history plus a fat-fingered 500 kg × 5 on day 4 — a huge single-day
        // outlier that never gets confirmed, so it stays provisional (verifiedAt nil).
        var (mw, ms) = legit()
        let misDay = workout(UUID(), start: date(2025, 6, 4, 19))
        mw.append(misDay)
        ms += sets(benchID, muscle: .chest, grams: 500_000, reps: 5, count: 1, workout: misDay)
        let withMislog = ProgressionEngine.compute(
            input: input(workouts: mw, sets: ms),
            config: config, calendar: cal, asOf: date(2025, 6, 4, 20))

        // The provisional 500 kg set contributes NOTHING to weekly volume or PL — the
        // quarantine that already protects the Strength Score now protects volume too.
        #expect(withMislog.weeklyVolumeLb == control.weeklyVolumeLb)
        #expect(withMislog.powerLevel == control.powerLevel)
        #expect(!withMislog.badges.contains { $0.key == "new_ceiling" })
    }
}

// MARK: - Idempotency

@Suite("ProgressionEngine — determinism")
struct DeterminismTests {

    @Test("Recomputing the same input twice yields identical snapshots")
    func idempotentRecompute() throws {
        let config = try loadConfig()
        let cal = madridCalendar()
        let wA = workout(UUID(), start: date(2025, 6, 2, 18))
        let wB = workout(UUID(), start: date(2025, 6, 4, 18))
        let allSets = sets(benchID, muscle: .chest, grams: 85_049, reps: 6, count: 4, workout: wA)
            + sets(rowID, muscle: .back, grams: 97_198, reps: 5, count: 6, workout: wB)
        let asOf = date(2025, 6, 5, 20)
        let payload = input(workouts: [wA, wB], sets: allSets)

        let first = ProgressionEngine.compute(input: payload, config: config, calendar: cal, asOf: asOf)
        let second = ProgressionEngine.compute(input: payload, config: config, calendar: cal, asOf: asOf)

        #expect(first.powerLevel == second.powerLevel)
        #expect(first.allTimePeakPL == second.allTimePeakPL)
        #expect(first.strengthScore == second.strengthScore)
        #expect(first.weeklyVolumeLb == second.weeklyVolumeLb)
        #expect(first.streakWeeks == second.streakWeeks)
        #expect(first.badges == second.badges)
        #expect(first.badgeCounts == second.badgeCounts)
        #expect(first.rivalPL == second.rivalPL)
        #expect(first.rivalForm == second.rivalForm)
    }
}

// MARK: - Levels & tier gates

@Suite("ProgressionReconciler")
struct ReconcilerTests {

    @Test("Awards are inserted once, then soft-deleted when evidence is removed")
    @MainActor
    func insertThenRevoke() throws {
        let container = try ModelContainer.settTest()
        let context = container.mainContext
        let config = try loadConfig()

        let exercise = Exercise(name: "Bench Press", muscle: .chest, equipment: .barbell)
        context.insert(exercise)
        let start = date(2025, 6, 2, 18)
        let workout = Workout(title: "Push", startedAt: start)
        workout.endedAt = start.addingTimeInterval(3600)
        context.insert(workout)
        let workoutExercise = WorkoutExercise(orderIndex: 0, exercise: exercise)
        workoutExercise.workout = workout
        context.insert(workoutExercise)
        for index in 0..<3 {
            let set = SetEntry(orderIndex: index, weightGrams: 100_000, entryUnit: .kg,
                               reps: 5, completedAt: start.addingTimeInterval(Double(300 + index * 300)))
            set.workoutExercise = workoutExercise
            context.insert(set)
        }
        try context.save()

        let snapshot = try ProgressionReconciler.reconcile(context: context, config: config)
        #expect(snapshot.badges.contains { $0.key == "ignition" })
        let awards = try context.fetch(FetchDescriptor<BadgeAward>())
        #expect(awards.contains { $0.badgeKey == "ignition" && $0.deletedAt == nil })

        // Idempotent: a second pass never duplicates rows.
        _ = try ProgressionReconciler.reconcile(context: context, config: config)
        let liveIgnitions = try context.fetch(FetchDescriptor<BadgeAward>())
            .filter { $0.badgeKey == "ignition" && $0.deletedAt == nil }
        #expect(liveIgnitions.count == 1)

        // Soft-delete the only workout -> the badge's evidence is gone -> revoked.
        workout.deletedAt = date(2025, 6, 7)
        workout.updatedAt = date(2025, 6, 7)
        try context.save()
        let revokedSnapshot = try ProgressionReconciler.reconcile(context: context, config: config)
        #expect(!revokedSnapshot.badges.contains { $0.key == "ignition" })
        let revoked = try context.fetch(FetchDescriptor<BadgeAward>())
            .filter { $0.badgeKey == "ignition" }
        #expect(!revoked.isEmpty)
        #expect(revoked.allSatisfy { $0.deletedAt != nil && $0.needsPush })

        // SaiyanState cache was refreshed.
        let state = context.saiyanState()
        #expect(state.powerLevel == revokedSnapshot.powerLevel)
        #expect(state.characterXPJSON == "{}")
    }
}

// MARK: - Rested bonus

@Suite("ProgressionEngine — rested bonus")
struct RestedBonusTests {

    /// Two identical 3-set workouts. First workout: 50 + 3×2 + 25 (net) = 81 XP.
    /// Second (identical volume, no net bonus): 50 + 3×2 = 56 XP raw.
    /// restedBonusActive evaluated on the given day, with one prior workout on Jun 2 —
    /// the XP economy is gone, but the REST-GAP RULES still gate the surge state.
    private func restedActive(onDay day: Int) throws -> Bool {
        let config = try loadConfig()
        let w1 = workout(UUID(), start: date(2025, 6, 2, 18))          // Monday
        let allSets = sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w1)
        let snapshot = ProgressionEngine.compute(
            input: input(workouts: [w1], sets: allSets),
            config: config, calendar: madridCalendar(), asOf: date(2025, 6, day, 10))
        return snapshot.restedBonusActive
    }

    @Test("Rest-gap rules: 2–15 day gaps arm the surge; longer or same-day do not")
    func restGapRules() throws {
        #expect(try restedActive(onDay: 3) == false)    // consecutive day — no rest yet
        #expect(try restedActive(onDay: 4) == true)     // one full rest day
        #expect(try restedActive(onDay: 17) == true)    // 15-day gap — still active period
        #expect(try restedActive(onDay: 18) == false)   // 16-day gap — a comeback, not a surge
        #expect(try restedActive(onDay: 23) == false)   // 21-day gap
    }

    @Test("restedBonusActive mirrors the predicate for the day containing asOf")
    func restedBonusActiveFlag() throws {
        let config = try loadConfig()
        let cal = madridCalendar()
        let w1 = workout(UUID(), start: date(2025, 6, 2, 18))
        let allSets = sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w1)
        let payload = input(workouts: [w1], sets: allSets)

        // Next day: no rest day in between -> inactive.
        let dayAfter = ProgressionEngine.compute(input: payload, config: config,
                                                 calendar: cal, asOf: date(2025, 6, 3, 10))
        #expect(!dayAfter.restedBonusActive)
        // Two days later: Jun 3 was a true rest day inside an active period -> active.
        let afterRest = ProgressionEngine.compute(input: payload, config: config,
                                                  calendar: cal, asOf: date(2025, 6, 4, 10))
        #expect(afterRest.restedBonusActive)
        // 21 days later: comeback, not rested.
        let afterGap = ProgressionEngine.compute(input: payload, config: config,
                                                 calendar: cal, asOf: date(2025, 6, 23, 10))
        #expect(!afterGap.restedBonusActive)
    }
}


// MARK: - UserForm ladder (endless)

@Suite("UserForm — the endless transformation ladder")
struct UserFormTests {
    @Test("Named rungs resolve at their floors")
    func namedRungs() {
        #expect(UserForm.form(forPL: 0).title == "BASE")
        #expect(UserForm.form(forPL: 1_999).title == "BASE")
        #expect(UserForm.form(forPL: 2_000).title == "KINDLED")
        #expect(UserForm.form(forPL: 5_000).title == "ASCENDANT")
        #expect(UserForm.form(forPL: 8_999).title == "ASCENDANT")
        #expect(UserForm.form(forPL: 9_000).title == "RADIANT")
        #expect(UserForm.form(forPL: 15_000).title == "ZENITH")
    }

    @Test("The ladder never ends — Zenith rolls into II, III, …")
    func endlessZenith() {
        #expect(UserForm.form(forPL: 22_499).title == "ZENITH")
        #expect(UserForm.form(forPL: 22_500).title == "ZENITH II")
        #expect(UserForm.form(forPL: 30_000).title == "ZENITH III")
        #expect(UserForm.form(forPL: 97_500).title == "ZENITH XII")
        #expect(UserForm.form(forPL: 97_500).nextPL == 105_000)
    }

    @Test("nextPL is always ahead and progress is 0…1")
    func nextAlwaysAhead() {
        for pl in [0, 1_500, 4_999, 9_000, 14_999, 15_000, 50_000, 250_000] {
            let form = UserForm.form(forPL: pl)
            #expect(form.nextPL > pl)
            let p = form.progress(pl)
            #expect(p >= 0 && p <= 1)
        }
    }

    @Test("Negative PL clamps to Base")
    func negativeClamps() {
        #expect(UserForm.form(forPL: -50).title == "BASE")
    }
}

// MARK: - Rested surge (volume weighted while in the window)

@Suite("ProgressionEngine — Rested surge")
struct RestedSurgeTests {

    /// A surge-armed workout's sets count extra toward WVL (config multiplier),
    /// while the strength score — an e1RM ceiling, not a volume — is untouched.
    @Test("Surged sets multiply weekly volume, not strength")
    func surgedVolume() throws {
        let config = try loadConfigForSurge()
        let cal = surgeCalendar()

        func run(surged: Bool) -> ProgressionSnapshot {
            let w = WorkoutSample(id: UUID(), title: "Workout",
                                  startedAt: surgeDate(2025, 6, 2, 18),
                                  endedAt: surgeDate(2025, 6, 2, 19),
                                  bodyweightGrams: nil, routineID: nil)
            let exercise = UUID()
            let sets = (0..<4).map { index in
                SetSample(exerciseID: exercise, muscle: .chest, weightGrams: 85_049, reps: 6,
                          isWarmup: false,
                          completedAt: w.startedAt.addingTimeInterval(Double(300 + index * 300)),
                          workoutID: w.id, isRestedSurge: surged)
            }
            let input = ProgressionInput(sets: sets, workouts: [w], sleep: [], goals: [],
                                         previousPeakPL: 0, firstWorkoutDate: w.startedAt)
            return ProgressionEngine.compute(input: input, config: config, calendar: cal,
                                             asOf: surgeDate(2025, 6, 3, 20))
        }

        let plain = run(surged: false)
        let surged = run(surged: true)
        // WVL scales by the multiplier (1.25 by default config).
        let expected = Int((Double(plain.weeklyVolumeLb) * config.powerLevel.restedSurgeMultiplier).rounded())
        #expect(abs(surged.weeklyVolumeLb - expected) <= 1)
        // Strength (best verified e1RM) is volume-independent.
        #expect(surged.strengthScore == plain.strengthScore)
        #expect(surged.powerLevel > plain.powerLevel)
    }
}

private func surgeCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
    cal.firstWeekday = 2
    cal.minimumDaysInFirstWeek = 4
    return cal
}

private func surgeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour
    return surgeCalendar().date(from: c)!
}

private func loadConfigForSurge() throws -> ProgressionConfig {
    try ProgressionConfig.load()
}

// MARK: - Power Level breakdown (composition + Shapley attribution)

@Suite("PowerLevelBreakdown — decomposition")
struct PowerLevelBreakdownTests {

    /// The two halves reconstruct the PL (within a rounding step), and the streak
    /// bonus is exactly pl − round(raw/cm) — with no streak (cm = 1) it's zero.
    @Test("Composition: strength + volume ≈ pl; streak bonus is pl − round(raw/cm)")
    func compositionReconstructs() throws {
        let config = try loadConfig()
        let plc = config.powerLevel
        let ss = 475, vol = 2732
        let cm = 1.05

        func raw(_ ss: Int, _ vol: Int, _ cm: Double) -> Double {
            (plc.strengthWeight * Double(ss) + plc.volumeWeight * Double(vol).squareRoot()) * cm
        }

        let comp = PowerLevelBreakdown.composition(strengthScore: ss, weeklyVolumeLb: vol,
                                                   consistencyMultiplier: cm, config: config)
        let pl = Int(raw(ss, vol, cm).rounded())
        // round(a) + round(b) is within 1 of round(a + b).
        #expect(abs((comp.strengthPL + comp.volumePL) - pl) <= 1)
        // Streak bonus is exactly the definition, and positive while cm > 1.
        #expect(comp.streakBonusPL == pl - Int((raw(ss, vol, cm) / cm).rounded()))
        #expect(comp.streakBonusPL > 0)
        // Shares split the base and sum to 1.
        #expect(abs(comp.strengthShare + comp.volumeShare - 1) < 1e-9)

        // No streak (cm = 1): raw/cm == raw, so the bonus vanishes.
        let flat = PowerLevelBreakdown.composition(strengthScore: ss, weeklyVolumeLb: vol,
                                                   consistencyMultiplier: 1.0, config: config)
        #expect(flat.streakBonusPL == 0)
    }

    /// Built from a real computed snapshot's rounded levers, the two halves land within
    /// a couple of PL of the live number — the receipt the user sees still balances.
    @Test("Composition rebuilds a computed snapshot's live PL")
    func compositionFromSnapshot() throws {
        let config = try loadConfig()
        let cal = madridCalendar()
        let wA = workout(UUID(), start: date(2025, 6, 2, 18))
        let wB = workout(UUID(), start: date(2025, 6, 4, 18))
        let allSets = sets(benchID, muscle: .chest, grams: 85_049, reps: 6, count: 4, workout: wA)
            + sets(rowID, muscle: .back, grams: 97_198, reps: 5, count: 6, workout: wB)
        let snapshot = ProgressionEngine.compute(
            input: input(workouts: [wA, wB], sets: allSets),
            config: config, calendar: cal, asOf: date(2025, 6, 5, 20))

        let comp = PowerLevelBreakdown.composition(
            strengthScore: snapshot.strengthScore, weeklyVolumeLb: snapshot.weeklyVolumeLb,
            consistencyMultiplier: snapshot.consistencyMultiplier, config: config)
        #expect(abs((comp.strengthPL + comp.volumePL) - snapshot.powerLevel) <= 3)
        #expect(comp.strengthPL > 0 && comp.volumePL > 0)
    }

    /// Shapley shares round (largest-remainder) to ints that sum EXACTLY to deltaPL,
    /// and deltaPL is measured on the rounded raw endpoints.
    @Test("Attribution: the three levers sum exactly to deltaPL")
    func attributionSumsExactly() throws {
        let config = try loadConfig()
        let plc = config.powerLevel
        let from = PLPoint(date: date(2025, 6, 2), pl: 2000, strengthScore: 400,
                           weeklyVolumeLb: 2000, consistencyMultiplier: 1.0)
        let to = PLPoint(date: date(2025, 6, 30), pl: 2600, strengthScore: 520,
                         weeklyVolumeLb: 2600, consistencyMultiplier: 1.10)

        let attr = PowerLevelBreakdown.attribution(from: from, to: to, config: config)
        #expect(attr.strength + attr.volume + attr.consistency == attr.deltaPL)
        #expect(attr.fromDate == from.date && attr.toDate == to.date)

        func raw(_ ss: Int, _ vol: Int, _ cm: Double) -> Double {
            (plc.strengthWeight * Double(ss) + plc.volumeWeight * Double(vol).squareRoot()) * cm
        }
        let expected = Int(raw(520, 2600, 1.10).rounded()) - Int(raw(400, 2000, 1.0).rounded())
        #expect(attr.deltaPL == expected)
    }

    /// Only volume grows: strength and consistency have exactly-zero marginals in every
    /// coalition, so volume carries the whole (positive) delta.
    @Test("Attribution: volume dominates when only volume grew")
    func volumeDominant() throws {
        let config = try loadConfig()
        let from = PLPoint(date: date(2025, 6, 1), pl: 0, strengthScore: 500,
                           weeklyVolumeLb: 1000, consistencyMultiplier: 1.05)
        let to = PLPoint(date: date(2025, 6, 28), pl: 0, strengthScore: 500,
                         weeklyVolumeLb: 3000, consistencyMultiplier: 1.05)

        let attr = PowerLevelBreakdown.attribution(from: from, to: to, config: config)
        #expect(attr.strength == 0)            // ss unchanged -> zero marginal
        #expect(attr.consistency == 0)         // cm unchanged -> zero marginal
        #expect(attr.volume == attr.deltaPL)   // volume carries the whole delta
        #expect(attr.volume > 0)
        #expect(attr.strength + attr.volume + attr.consistency == attr.deltaPL)
    }
}
