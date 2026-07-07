import Foundation
import SwiftData

// MARK: - SplitMix64

/// Tiny deterministic RNG (SplitMix64) so demo data is reproducible on every run.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - DemoData

/// Seeds ~6 months of realistic, deterministic training history so every app surface has
/// data to show: routines with schedules, dense workout history with progressive overload,
/// a 24-day gap + comeback, a plateaued lift, nightly sleep, a bodyweight log, goals, gyms,
/// and a weekly digest.
@MainActor
public enum DemoData {

    /// DEBUG hook: seeds only when no finished workouts exist.
    public static func seedIfRequested(context: ModelContext) {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt != nil && $0.deletedAt == nil }
        )
        let finished = (try? context.fetchCount(descriptor)) ?? 0
        guard finished == 0 else { return }
        seed(context: context, monthsBack: 6)
    }

    /// ~`monthsBack` months of history ending yesterday. Deterministic (seeded RNG).
    public static func seed(context: ModelContext, monthsBack: Int) {
        var rng = SplitMix64(seed: 0x5E77_DA7A_0000_0001)

        // 1. The exercise catalog first — routines and history reference it by name.
        try? SeedLoader.seedExercises(into: context)
        let catalog = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        func exercise(named name: String, equipment: Equipment) -> Exercise? {
            catalog.first { $0.name == name && $0.equipmentRaw == equipment.rawValue && $0.deletedAt == nil }
        }
        let resolved: [[Exercise?]] = routineSpecs.map { spec in
            spec.lifts.map { exercise(named: $0.name, equipment: $0.equipment) }
        }

        // Timeline: rolling weeks ending yesterday, Monday-first calendar in local time.
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        let today = cal.startOfDay(for: .now)
        let weeks = max(4, Int((Double(monthsBack) * 52.0 / 12.0).rounded()))
        let totalDays = weeks * 7
        guard let endDay = cal.date(byAdding: .day, value: -1, to: today),
              let startDay = cal.date(byAdding: .day, value: -(totalDays - 1), to: endDay) else { return }
        func day(at offset: Int) -> Date? { cal.date(byAdding: .day, value: offset, to: startDay) }

        // The 24-day gap ends ~6 weeks before yesterday (midpoint ~8 weeks back).
        // Only applied when the window is long enough to hold it.
        let gapRange: ClosedRange<Int>? = {
            let upper = totalDays - 44
            let lower = upper - 23
            return lower > 7 ? lower...upper : nil
        }()

        // Bench plateaus: flat working weight across the final 4 weeks.
        let plateauFromOffset = max(0, totalDays - 28)
        func weightGrams(routineIndex: Int, liftIndex: Int, dayOffset: Int) -> Int {
            let lift = routineSpecs[routineIndex].lifts[liftIndex]
            var steps = progressionSteps(dayOffset: dayOffset, gapRange: gapRange)
            if routineIndex == 0 && liftIndex == 0 && dayOffset >= plateauFromOffset {
                steps = min(steps, progressionSteps(dayOffset: plateauFromOffset, gapRange: gapRange))
            }
            return lift.baseGrams + steps * 1134 // +2.5 lb plate jump every ~2 training weeks
        }

        // 2. Gyms — home gym plus an occasional hotel gym with Chamber Log fields.
        let homeGym = Gym(name: "Iron Temple", latitude: 40.4168, longitude: -3.7038, isHome: true)
        homeGym.needsPush = false
        context.insert(homeGym)
        let hotelGym = Gym(name: "Hotel Chamber", latitude: 40.4210, longitude: -3.6935)
        hotelGym.dayPassPriceCents = 1500
        hotelGym.quickRating = 4
        hotelGym.needsPush = false
        context.insert(hotelGym)

        // 3. Routines with day-of-week masks and per-set plans.
        var routines: [Routine] = []
        for (routineIndex, spec) in routineSpecs.enumerated() {
            let routine = Routine(name: spec.name, daysOfWeekMask: spec.daysOfWeekMask, orderIndex: routineIndex)
            routine.needsPush = false
            context.insert(routine)
            for (liftIndex, lift) in spec.lifts.enumerated() {
                guard let ex = resolved[routineIndex][liftIndex] else { continue }
                let routineExercise = RoutineExercise(orderIndex: liftIndex, exercise: ex)
                routineExercise.restSeconds = lift.equipment == .barbell ? 150 : 90
                routineExercise.needsPush = false
                routineExercise.routine = routine
                context.insert(routineExercise)
                let target = weightGrams(routineIndex: routineIndex, liftIndex: liftIndex, dayOffset: totalDays - 1)
                for setIndex in 0..<3 {
                    let planned = PlannedSet(orderIndex: setIndex, targetReps: 10 - setIndex,
                                             targetWeightGrams: target)
                    planned.needsPush = false
                    planned.routineExercise = routineExercise
                    context.insert(planned)
                }
            }
            routines.append(routine)
        }

        // 4. Schedule: push Mon/Thu, pull Tue/Fri, legs Wed/Sat, Sunday rest;
        //    3-4 sessions per week, none inside the gap.
        var scheduled: [Slot] = []
        for week in 0..<weeks {
            var candidates: [Slot] = []
            for dayInWeek in 0..<7 {
                let offset = week * 7 + dayInWeek
                guard offset < totalDays, let date = day(at: offset) else { continue }
                let mondayZeroWeekday = (cal.component(.weekday, from: date) + 5) % 7
                guard mondayZeroWeekday < 6 else { continue } // Sunday = rest
                candidates.append(Slot(offset: offset, routineIndex: mondayZeroWeekday % 3))
            }
            let workoutsThisWeek = week.isMultiple(of: 2) ? 4 : 3
            let picked = candidates.shuffled(using: &rng)
                .prefix(workoutsThisWeek)
                .sorted { $0.offset < $1.offset }
            for slot in picked {
                if let gap = gapRange, gap.contains(slot.offset) { continue }
                scheduled.append(slot)
            }
        }

        // 5. Workouts following the routines, chronological.
        var benchBestE1RM = 0
        var workoutsSinceSave = 0
        for slot in scheduled {
            guard let dayStart = day(at: slot.offset) else { continue }
            let spec = routineSpecs[slot.routineIndex]
            let routine = routines[slot.routineIndex]

            let isMorning = Int.random(in: 0..<10, using: &rng) < 3
            let startMinutes = isMorning ? 7 * 60 + 10 : 18 * 60 + 30
            guard let startedAt = cal.date(byAdding: .minute, value: startMinutes, to: dayStart) else { continue }

            let workout = Workout(title: spec.name, startedAt: startedAt)
            workout.routineID = routine.id
            workout.routineNameSnapshot = routine.name
            let atHotel = Int.random(in: 0..<10, using: &rng) == 0
            let gym = atHotel ? hotelGym : homeGym
            workout.gymID = gym.id
            workout.gymNameSnapshot = gym.name
            workout.endedAt = startedAt.addingTimeInterval(TimeInterval((55 + Int.random(in: 0...20, using: &rng)) * 60))
            workout.ratingHalfStars = Int.random(in: 6...10, using: &rng)
            let drift = Int((sin(Double(slot.offset) / 14.0) * 700.0).rounded())
            let bodyweight = 79_400 + drift + Int.random(in: -200...200, using: &rng)
            workout.bodyweightGrams = bodyweight / 100 * 100
            if Int.random(in: 0..<100, using: &rng) < 15 {
                workout.notes = workoutNotes[Int.random(in: 0..<workoutNotes.count, using: &rng)]
            }
            workout.needsPush = false
            context.insert(workout)

            var setClock = startedAt
            for (liftIndex, lift) in spec.lifts.enumerated() {
                guard let ex = resolved[slot.routineIndex][liftIndex] else { continue }
                let workoutExercise = WorkoutExercise(orderIndex: liftIndex, exercise: ex)
                workoutExercise.restSeconds = lift.equipment == .barbell ? 150 : 90
                workoutExercise.needsPush = false
                workoutExercise.workout = workout
                context.insert(workoutExercise)

                let working = weightGrams(routineIndex: slot.routineIndex, liftIndex: liftIndex,
                                          dayOffset: slot.offset)
                var orderIndex = 0
                if liftIndex == 0 { // one warmup set on the first lift of the day
                    setClock.addTimeInterval(TimeInterval(Int.random(in: 120...240, using: &rng)))
                    let warmup = SetEntry(orderIndex: orderIndex, weightGrams: Int(Double(working) * 0.6) / 500 * 500,
                                          entryUnit: .lb, reps: 12, isWarmup: true, completedAt: setClock)
                    warmup.needsPush = false
                    warmup.workoutExercise = workoutExercise
                    context.insert(warmup)
                    orderIndex += 1
                }
                for _ in 0..<3 {
                    setClock.addTimeInterval(TimeInterval(Int.random(in: 120...240, using: &rng)))
                    let reps = repPool[Int.random(in: 0..<repPool.count, using: &rng)]
                    let set = SetEntry(orderIndex: orderIndex, weightGrams: working, entryUnit: .lb,
                                       reps: reps, isWarmup: false, completedAt: setClock)
                    set.needsPush = false
                    set.workoutExercise = workoutExercise
                    context.insert(set)
                    if slot.routineIndex == 0 && liftIndex == 0 {
                        benchBestE1RM = max(benchBestE1RM,
                                            ProgressEngine.e1RMGrams(weightGrams: working, reps: reps))
                    }
                    orderIndex += 1
                }
            }

            workoutsSinceSave += 1
            if workoutsSinceSave >= 20 {
                try? context.save()
                workoutsSinceSave = 0
            }
        }

        // 6. Sleep every night, loosely correlated with next-day training volume.
        let workoutOffsets = Set(scheduled.map { $0.offset })
        let legOffsets = Set(scheduled.filter { $0.routineIndex == 2 }.map { $0.offset })
        for offset in 0..<totalDays {
            guard let date = day(at: offset) else { continue }
            var score = 58 + Int.random(in: 0...22, using: &rng)
            if workoutOffsets.contains(offset) { score += 8 }
            if legOffsets.contains(offset) { score += 4 } // biggest sessions follow the best nights
            score = min(score, 95)
            let total = 19_800 + Int(Double(score - 55) / 40.0 * 9_000.0) + Int.random(in: 0...1_800, using: &rng)
            let sleep = SleepDay(
                dateKey: cal.dateKey(for: date),
                sleepScore: score,
                readinessScore: min(95, max(40, score - 5 + Int.random(in: 0...10, using: &rng))),
                totalSleepSeconds: total,
                deepSeconds: total * Int.random(in: 15...22, using: &rng) / 100,
                remSeconds: total * Int.random(in: 20...25, using: &rng) / 100,
                avgHRV: Double(45 + Int.random(in: 0...49, using: &rng)) + Double(Int.random(in: 0...9, using: &rng)) / 10.0,
                restingHR: 48 + Int.random(in: 0...14, using: &rng)
            )
            context.insert(sleep)
        }

        // 6b. Bodyweight log — ~3 morning weigh-ins per week across the whole range,
        //     drifting around 79.4 kg (±1 kg wave) with a slight downward trend.
        //     Separate RNG stream so the workout/sleep sequences above stay identical.
        var bodyweightRNG = SplitMix64(seed: 0x5E77_DA7A_0000_0002)
        for offset in 0..<totalDays {
            guard Int.random(in: 0..<7, using: &bodyweightRNG) < 3,
                  let date = day(at: offset),
                  let loggedAt = cal.date(byAdding: .minute, value: 7 * 60 + 45, to: date) else { continue }
            let progress = Double(offset) / Double(max(1, totalDays - 1))
            let trend = Int(((0.5 - progress) * 1_600.0).rounded())            // +0.8 kg → -0.8 kg
            let wave = Int((sin(Double(offset) / 12.0) * 600.0).rounded())     // slow ±0.6 kg oscillation
            let grams = 79_400 + trend + wave + Int.random(in: -250...250, using: &bodyweightRNG)
            let entry = BodyweightEntry(weightGrams: grams / 100 * 100, loggedAt: loggedAt)
            entry.needsPush = false
            context.insert(entry)
        }

        // 7. Goals: one completed, one active frequency, one PR target on the stalled lift.
        let fiveWeeksAgo = cal.date(byAdding: .day, value: -35, to: today) ?? today
        let completedGoal = Goal(kind: .frequency, targetValue: 3, startDate: startDay, endDate: fiveWeeksAgo)
        completedGoal.isActive = false
        completedGoal.completedAt = fiveWeeksAgo
        completedGoal.needsPush = false
        context.insert(completedGoal)

        let activeFrequency = Goal(kind: .frequency, targetValue: 3,
                                   startDate: cal.date(byAdding: .day, value: -28, to: today) ?? today)
        activeFrequency.needsPush = false
        context.insert(activeFrequency)

        if let bench = resolved[0][0], benchBestE1RM > 0 {
            let prGoal = Goal(kind: .prTarget,
                              targetValue: Int((Double(benchBestE1RM) * 1.05).rounded()),
                              exerciseID: bench.id, exerciseNameSnapshot: bench.name,
                              startDate: cal.date(byAdding: .day, value: -21, to: today) ?? today)
            prGoal.needsPush = false
            context.insert(prGoal)
        }

        // 8. Last week's digest.
        if let thisWeek = cal.dateInterval(of: .weekOfYear, for: today),
           let periodStart = cal.date(byAdding: .day, value: -7, to: thisWeek.start) {
            let digest = AIInsight(kind: .weeklyDigest, periodStart: periodStart, periodEnd: thisWeek.start,
                                   body: digestBody, source: .server)
            digest.needsPush = false
            context.insert(digest)
        }

        try? context.save()

        // 9. Bring the progression cache (SaiyanState, badges) in line with the history.
        do {
            let config = try ProgressionConfig.load()
            try ProgressionReconciler.reconcile(context: context, config: config)
        } catch {
            // The progression cache is derivable at any time; seeding must not fail on it.
        }
    }

    // MARK: - Plan

    private struct LiftSpec {
        let name: String
        let equipment: Equipment
        /// Base working weight in grams (lb-flavored so the +1134 g jumps stay on plate math).
        let baseGrams: Int
    }

    private struct RoutineSpec {
        let name: String
        /// Bitmask: bit 0 = Monday … bit 6 = Sunday.
        let daysOfWeekMask: Int
        let lifts: [LiftSpec]
    }

    private struct Slot {
        let offset: Int
        let routineIndex: Int
    }

    private static let routineSpecs: [RoutineSpec] = [
        RoutineSpec(name: "Push Day", daysOfWeekMask: 0b000_1001, lifts: [ // Mon + Thu
            LiftSpec(name: "Flat Bench Press", equipment: .barbell, baseGrams: 61_235),   // 135 lb
            LiftSpec(name: "Incline Bench Press", equipment: .dumbbell, baseGrams: 22_680), // 50 lb
            LiftSpec(name: "Shoulder Press", equipment: .dumbbell, baseGrams: 18_144),    // 40 lb
            LiftSpec(name: "Tricep Pushdown", equipment: .cable, baseGrams: 24_948),      // 55 lb
        ]),
        RoutineSpec(name: "Pull Day", daysOfWeekMask: 0b001_0010, lifts: [ // Tue + Fri
            LiftSpec(name: "Lat Pulldown", equipment: .cable, baseGrams: 54_431),         // 120 lb
            LiftSpec(name: "Bent Over Row", equipment: .barbell, baseGrams: 52_163),      // 115 lb
            LiftSpec(name: "Bicep Curl", equipment: .dumbbell, baseGrams: 13_608),        // 30 lb
            LiftSpec(name: "Face Pulls", equipment: .cable, baseGrams: 20_412),           // 45 lb
        ]),
        RoutineSpec(name: "Leg Day", daysOfWeekMask: 0b010_0100, lifts: [ // Wed + Sat
            LiftSpec(name: "Squat", equipment: .barbell, baseGrams: 83_915),              // 185 lb
            LiftSpec(name: "Romanian Deadlift", equipment: .barbell, baseGrams: 70_307),  // 155 lb
            LiftSpec(name: "Leg Extension", equipment: .machine, baseGrams: 45_359),      // 100 lb
        ]),
    ]

    /// Working reps 5-12, biased toward 8-10.
    private static let repPool = [8, 9, 10, 8, 9, 10, 7, 11, 6, 12, 5, 10]

    private static let workoutNotes = [
        "Felt strong today — bar speed was crisp.",
        "Shoulder a bit cranky on the last pressing set.",
        "Gym was packed, longer rests than planned.",
        "Slept badly; kept the accessories light.",
        "Great pump. The Chamber delivers.",
        "New gym playlist did numbers today.",
    ]

    private static let digestBody = """
    Four sessions logged, every scheduled lift touched. Here's the read on last week.

    ## Sleep × Performance
    Sessions that followed 7h+ nights moved about 6% more volume than the short-sleep days. \
    Your two strongest lifts of the week both landed the morning after your highest sleep scores.

    ## Plateau Watch
    Flat Bench Press has held the same working weight for 4 straight weeks. Estimated 1RM is \
    flat while your other pressing lifts keep climbing — a classic stall, not a recovery problem.

    ## Deload Advice
    Take bench to ~85% of the working weight for one week, keep reps at 8, then rebuild in \
    2.5 lb jumps. Leave squats and pulls loaded — only the stalled lift needs the reset.

    ## Goal Check
    Frequency goal: 3/3 training days hit — on pace. The PR target on Flat Bench Press sits \
    about 5% away; the deload week is the fastest route to it.
    """

    /// One +1134 g step every ~2 training weeks. The 24-day gap pauses the clock, and the two
    /// weeks after it ramp back up (-2 steps, then -1) before normal progression resumes.
    private static func progressionSteps(dayOffset: Int, gapRange: ClosedRange<Int>?) -> Int {
        var trainingDays = dayOffset
        var comebackPenalty = 0
        if let gap = gapRange {
            let elapsedGapDays = max(0, min(dayOffset, gap.upperBound + 1) - gap.lowerBound)
            trainingDays -= elapsedGapDays
            if dayOffset > gap.upperBound {
                let sinceComeback = dayOffset - gap.upperBound
                comebackPenalty = sinceComeback <= 7 ? 2 : (sinceComeback <= 14 ? 1 : 0)
            }
        }
        return max(0, trainingDays / 14 - comebackPenalty)
    }
}
