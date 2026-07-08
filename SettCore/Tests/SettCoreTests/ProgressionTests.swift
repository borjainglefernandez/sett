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
        #expect(snapshot.characterXP[.vego] == 192)
        // Nyra: ignition badge (bronze 100), no completed streak weeks yet.
        #expect(snapshot.characterXP[.nyra] == 100)
        // Barok tonnage drip: 4,500 lb -> 4 XP, 6,429 lb -> 6 XP.
        #expect(snapshot.characterXP[.barok] == 10)
        #expect(snapshot.characterLevels[.vego] == 1)
        #expect(snapshot.tiers[.vego] == .base)

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

    @Test("Second workout of the same day yields no effective volume and decayed XP")
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
        #expect(snapshot.characterXP[.vego] == 95)
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
        #expect(first.characterXP == second.characterXP)
        #expect(first.characterLevels == second.characterLevels)
        #expect(first.tiers == second.tiers)
        #expect(first.rivalPL == second.rivalPL)
        #expect(first.rivalForm == second.rivalForm)
    }
}

// MARK: - Levels & tier gates

@Suite("ProgressionEngine — levels and tiers")
struct LevelTierTests {

    @Test("Level curve: cumulative 100 × L^1.8")
    func levelCurve() throws {
        let config = try loadConfig()
        let level5XP = Int((100.0 * pow(5.0, 1.8)).rounded())
        #expect(ProgressionEngine.level(forXP: 0, config: config) == 1)
        #expect(ProgressionEngine.level(forXP: level5XP - 1, config: config) == 4)
        #expect(ProgressionEngine.level(forXP: level5XP, config: config) == 5)
        #expect(ProgressionEngine.level(forXP: 10_000_000, config: config) == 40)
    }

    @Test("Tier gates require the keystone badge, not just the level")
    func tierGateNeedsKeystone() throws {
        let config = try loadConfig()
        // Vego's Kindled gate is L5 + new_ceiling.
        #expect(ProgressionEngine.tier(for: .vego, level: 5, earnedBadgeKeys: [],
                                       config: config) == .base)
        #expect(ProgressionEngine.tier(for: .vego, level: 5, earnedBadgeKeys: ["new_ceiling"],
                                       config: config) == .kindled)
        // The ladder is sequential: L12 without limit_break stays Kindled.
        #expect(ProgressionEngine.tier(for: .vego, level: 12, earnedBadgeKeys: ["new_ceiling"],
                                       config: config) == .kindled)
        #expect(ProgressionEngine.tier(for: .vego, level: 12,
                                       earnedBadgeKeys: ["new_ceiling", "limit_break"],
                                       config: config) == .ascendant)
        // Level alone is never enough below the first gate.
        #expect(ProgressionEngine.tier(for: .barok, level: 2, earnedBadgeKeys: [],
                                       config: config) == .base)
        // Zyn uses domain-badge counts instead of a fixed keystone.
        #expect(ProgressionEngine.tier(for: .zyn, level: 5, earnedBadgeKeys: [],
                                       config: config) == .kindled)
        #expect(ProgressionEngine.tier(for: .zyn, level: 5, earnedBadgeKeys: ["momentum"],
                                       config: config) == .ascendant)
    }
}

// MARK: - Reconciler (SwiftData bridge)

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
        #expect(state.characterXPJSON.contains("\"vego\""))
    }
}

// MARK: - Rested bonus

@Suite("ProgressionEngine — rested bonus")
struct RestedBonusTests {

    /// Two identical 3-set workouts. First workout: 50 + 3×2 + 25 (net) = 81 XP.
    /// Second (identical volume, no net bonus): 50 + 3×2 = 56 XP raw.
    private func twoWorkoutVegoXP(secondDay: Int, asOfDay: Int) throws -> Int {
        let config = try loadConfig()
        let w1 = workout(UUID(), start: date(2025, 6, 2, 18))          // Monday
        let w2 = workout(UUID(), start: date(2025, 6, secondDay, 18))
        let allSets = sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w1)
            + sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w2)
        let snapshot = ProgressionEngine.compute(
            input: input(workouts: [w1, w2], sets: allSets),
            config: config, calendar: madridCalendar(), asOf: date(2025, 6, asOfDay, 20))
        return snapshot.characterXP[.vego] ?? 0
    }

    @Test("A single rest day before an identical workout multiplies its XP by 1.25")
    func singleRestDayBoost() throws {
        // Rested: Mon + Wed (Tue is a true rest day inside an active period).
        // Second workout: round(56 × 1.25) = 70 -> vego 81 + 70 = 151.
        let rested = try twoWorkoutVegoXP(secondDay: 4, asOfDay: 4)
        #expect(rested == 151)
        // Consecutive: Mon + Tue -> 81 + 56 = 137. Delta = 14 = 0.25 × 56.
        let consecutive = try twoWorkoutVegoXP(secondDay: 3, asOfDay: 3)
        #expect(rested - consecutive == 14)
    }

    @Test("First workout after a 21-day gap earns no rested bonus")
    func longGapIsNotRested() throws {
        // Jun 2 -> Jun 23: Jun 22 was rest, but the trailing 14 days before it
        // (Jun 8–21) held zero qualifying workouts -> comeback, no bonus.
        #expect(try twoWorkoutVegoXP(secondDay: 23, asOfDay: 23) == 137)
        // Boundary: a 15-day gap (previous workout exactly 14 days before the
        // rest day) is still inside the active period -> bonus applies.
        #expect(try twoWorkoutVegoXP(secondDay: 17, asOfDay: 17) == 151)
        // A 16-day gap falls just outside -> no bonus.
        #expect(try twoWorkoutVegoXP(secondDay: 18, asOfDay: 18) == 137)
    }

    @Test("Consecutive training days earn no rested bonus")
    func consecutiveDaysNoBonus() throws {
        #expect(try twoWorkoutVegoXP(secondDay: 3, asOfDay: 3) == 137)
        // The very first workout ever has no preceding training -> no bonus:
        // 81, not round(81 × 1.25).
        let config = try loadConfig()
        let w1 = workout(UUID(), start: date(2025, 6, 2, 18))
        let allSets = sets(benchID, muscle: .chest, grams: 100_000, reps: 5, count: 3, workout: w1)
        let snapshot = ProgressionEngine.compute(
            input: input(workouts: [w1], sets: allSets),
            config: config, calendar: madridCalendar(), asOf: date(2025, 6, 2, 20))
        #expect(snapshot.characterXP[.vego] == 81)
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
