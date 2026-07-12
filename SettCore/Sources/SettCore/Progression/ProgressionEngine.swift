import Foundation

// MARK: - Public API types (CONTRACTS.md — Progression API)

/// One currently-earned badge, derived from raw data (idempotent).
public struct BadgeGrant: Sendable, Hashable {
    public let key: String
    public let earnedAt: Date
    public let valueSnapshot: Int
    public let workoutID: UUID?
    public let exerciseID: UUID?

    public init(key: String, earnedAt: Date, valueSnapshot: Int,
                workoutID: UUID? = nil, exerciseID: UUID? = nil) {
        self.key = key
        self.earnedAt = earnedAt
        self.valueSnapshot = valueSnapshot
        self.workoutID = workoutID
        self.exerciseID = exerciseID
    }
}

/// The full derived progression state at a moment in time.
public struct ProgressionSnapshot: Sendable {
    public let powerLevel: Int
    public let allTimePeakPL: Int          // max(previous peak, current)
    public let strengthScore: Int
    public let weeklyVolumeLb: Int
    public let consistencyMultiplier: Double
    public let streakWeeks: Int
    public let characterXP: [CharacterKey: Int]
    public let characterLevels: [CharacterKey: Int]  // from 100 * L^1.8 cumulative curve
    public let tiers: [CharacterKey: TransformationTier]
    public let badges: [BadgeGrant]        // ALL currently-earned badges (derived, idempotent)
    public let rivalPL: Int                // Vexeth's scripted PL as of now
    public let rivalForm: Int              // 1...3
    /// True when a qualifying workout started now would earn the rested bonus
    /// (see ProgressionEngine.isRested for the exact predicate). Defaulted so
    /// existing call sites keep compiling.
    public let restedBonusActive: Bool

    public init(powerLevel: Int, allTimePeakPL: Int, strengthScore: Int, weeklyVolumeLb: Int,
                consistencyMultiplier: Double, streakWeeks: Int,
                characterXP: [CharacterKey: Int], characterLevels: [CharacterKey: Int],
                tiers: [CharacterKey: TransformationTier], badges: [BadgeGrant],
                rivalPL: Int, rivalForm: Int, restedBonusActive: Bool = false) {
        self.powerLevel = powerLevel
        self.allTimePeakPL = allTimePeakPL
        self.strengthScore = strengthScore
        self.weeklyVolumeLb = weeklyVolumeLb
        self.consistencyMultiplier = consistencyMultiplier
        self.streakWeeks = streakWeeks
        self.characterXP = characterXP
        self.characterLevels = characterLevels
        self.tiers = tiers
        self.badges = badges
        self.rivalPL = rivalPL
        self.rivalForm = rivalForm
        self.restedBonusActive = restedBonusActive
    }
}

/// Value-type snapshot of the local store the engine computes from.
public struct ProgressionInput: Sendable {
    public let sets: [SetSample]
    public let workouts: [WorkoutSample]
    public let sleep: [SleepSample]
    public let goals: [GoalSample]
    public let previousPeakPL: Int
    public let firstWorkoutDate: Date?     // anchors Vexeth's pacing script

    public init(sets: [SetSample], workouts: [WorkoutSample], sleep: [SleepSample],
                goals: [GoalSample], previousPeakPL: Int, firstWorkoutDate: Date?) {
        self.sets = sets
        self.workouts = workouts
        self.sleep = sleep
        self.goals = goals
        self.previousPeakPL = previousPeakPL
        self.firstWorkoutDate = firstWorkoutDate
    }
}

// MARK: - ProgressionEngine

/// Pure + deterministic implementation of the full gamification design doc:
/// effective sets, qualifying workouts, PR verification (provisional/verified),
/// PL = round((strengthWeight*SS + volumeWeight*sqrt(WVL)) * CM), the XP economy
/// with anti-cheese rules, all 30 badges, tier gates (level + keystone), and
/// Vexeth's scripted pacing. Every tuning constant comes from ProgressionConfig.
public enum ProgressionEngine {

    /// The six categories that feed the Strength Score.
    static let primaryMuscles: [Muscle] = [.chest, .triceps, .biceps, .shoulders, .back, .legs]

    public static func compute(input: ProgressionInput, config: ProgressionConfig,
                               calendar: Calendar, asOf: Date) -> ProgressionSnapshot {
        var analysis = analyze(input: input, config: config, calendar: calendar, asOf: asOf)
        analysis.effectiveSets.sort { $0.sample.completedAt < $1.sample.completedAt }
        analysis.prEvents.sort { $0.date < $1.date }

        let qualifying = analysis.sessions.filter(\.isFirstQualifyingOfDay)

        // Net-vs-previous per session (workout-level rollup), cached once.
        var netPositive: [UUID: Bool] = [:]
        for session in analysis.sessions {
            netPositive[session.workout.id] = ProgressEngine
                .workoutNet(samples: analysis.workingSets, workoutID: session.workout.id)
                .volumeGrams > 0
        }

        // PL at every recomputation point (after each qualifying workout + now) —
        // drives scanner_breaker's "at any recomputation" clause and the peak.
        var plEvals: [(date: Date, pl: Int)] = []
        for session in qualifying {
            let breakdown = plBreakdown(at: session.endedAt, analysis: analysis,
                                        config: config, calendar: calendar)
            plEvals.append((session.endedAt, breakdown.pl))
        }
        let current = plBreakdown(at: asOf, analysis: analysis, config: config, calendar: calendar)
        plEvals.append((asOf, current.pl))

        let evaluator = BadgeEvaluator(analysis: analysis, qualifying: qualifying,
                                       plEvals: plEvals, netPositive: netPositive,
                                       input: input, config: config,
                                       calendar: calendar, asOf: asOf)
        var badges: [BadgeGrant] = []
        for def in config.badges {
            if let grant = evaluator.grant(for: def) { badges.append(grant) }
        }
        badges.sort { ($0.earnedAt, $0.key) < ($1.earnedAt, $1.key) }
        let earnedKeys = Set(badges.map(\.key))

        let characterXP = computeXP(analysis: analysis, qualifying: qualifying,
                                    badges: badges, netPositive: netPositive,
                                    input: input, config: config,
                                    calendar: calendar, asOf: asOf)

        var characterLevels: [CharacterKey: Int] = [:]
        var tiers: [CharacterKey: TransformationTier] = [:]
        for character in CharacterKey.allCases {
            let characterLevel = level(forXP: characterXP[character] ?? 0, config: config)
            characterLevels[character] = characterLevel
            tiers[character] = tier(for: character, level: characterLevel,
                                    earnedBadgeKeys: earnedKeys, config: config)
        }

        let peak = max(input.previousPeakPL, plEvals.map { $0.pl }.max() ?? 0)

        // Vexeth pacing script.
        let rival = config.rival
        let startPL = rival["startPL"] as? Int ?? 0
        let weeklyGrowth = rival["weeklyGrowth"] as? Int ?? 0
        let forms = rival["forms"] as? Int ?? 3
        let leadPL = rival["formRevealLeadPL"] as? Int ?? 0
        var rivalWeeks = 0
        if let first = input.firstWorkoutDate, first <= asOf {
            rivalWeeks = max(0, daysBetween(first, asOf, calendar: calendar) / 7)
        }
        let rivalPL = startPL + weeklyGrowth * rivalWeeks
        let rivalForm = min(forms, 1
                            + (current.pl > rivalPL ? 1 : 0)
                            + (peak > rivalPL + leadPL ? 1 : 0))

        // Would a qualifying workout started right now earn the rested bonus?
        // Same predicate as the XP economy, evaluated for the day containing asOf.
        let todayStart = calendar.startOfDay(for: asOf)
        let priorTrainedDay = distinctQualifyingDayStarts(qualifying: qualifying)
            .last { $0 < todayStart }
        let restedActive = isRested(dayStart: todayStart,
                                    previousQualifyingDayStart: priorTrainedDay,
                                    calendar: calendar)

        return ProgressionSnapshot(
            powerLevel: current.pl,
            allTimePeakPL: peak,
            strengthScore: Int(current.ssLb.rounded()),
            weeklyVolumeLb: Int(current.wvlLb.rounded()),
            consistencyMultiplier: current.cm,
            streakWeeks: current.streak,
            characterXP: characterXP,
            characterLevels: characterLevels,
            tiers: tiers,
            badges: badges,
            rivalPL: rivalPL,
            rivalForm: rivalForm,
            restedBonusActive: restedActive
        )
    }

    // MARK: - Rested bonus

    /// RESTED BONUS predicate — exact rule. Let X be the most recent local
    /// calendar day strictly before day D that had at least one qualifying
    /// workout. Day D's workout XP earns the rested bonus iff:
    ///   (1) X exists and D − X ≥ 2 days — i.e. the day immediately preceding D
    ///       (D − 1) had ZERO qualifying workouts (a true rest day), AND
    ///   (2) X falls within the trailing 14 days before that rest day —
    ///       (D − 1) − X ≤ 14, equivalently D − X ≤ 15 — an intentional rest
    ///       inside an active training period. A comeback after a longer gap
    ///       (D − X ≥ 16) earns NO bonus.
    /// The multiplier applies to the workout-XP components (base + sets + net
    /// + PR) BEFORE same-day decay and the daily cap; the cap still caps the
    /// boosted result.
    static func isRested(dayStart: Date, previousQualifyingDayStart: Date?,
                         calendar: Calendar) -> Bool {
        guard let previous = previousQualifyingDayStart else { return false }
        let gap = daysBetween(previous, dayStart, calendar: calendar)
        return gap >= 2 && gap <= 15
    }

    // MARK: - Chronological analysis (effective sets, qualifying sessions, PR pipeline)

    struct EffectiveSetRecord {
        let sample: SetSample
        let e1RMGrams: Int
        /// nil while the reading is provisional (unconfirmed jump); set to the
        /// confirmation moment when a later distinct-day session verifies it.
        var verifiedAt: Date?
    }

    struct Session {
        let workout: WorkoutSample
        let endedAt: Date
        let dayKey: Int
        let dayStart: Date
        /// Sets passing the per-set filters (rep bounds, e1RM floor, per-exercise
        /// and per-workout caps) regardless of the first-of-day rule.
        let candidateSetCount: Int
        /// Only the first qualifying workout of a local calendar day produces
        /// effective sets; later ones exist solely for the XP decay rule.
        let isFirstQualifyingOfDay: Bool
        let effectiveTonnageGrams: Int
        let effectiveExerciseIDs: Set<UUID>
    }

    struct PREvent {
        let date: Date
        let exerciseID: UUID
        let muscle: Muscle
        let workoutID: UUID
        let e1RMGrams: Int
    }

    struct Analysis {
        var effectiveSets: [EffectiveSetRecord] = []
        var sessions: [Session] = []       // chronological, session-qualifying only
        var prEvents: [PREvent] = []
        var workingSets: [SetSample] = []  // all non-warmup sets up to asOf
    }

    private struct PRTracker {
        var verifiedBestGrams = 0          // 0 = no verified history yet
        var hasPending = false
        var pendingGrams = 0
        var pendingDayKey = 0
        var pendingIndices: [Int] = []
        var sessionDayCount = 0
        var lastDayKey = -1
    }

    static func analyze(input: ProgressionInput, config: ProgressionConfig,
                        calendar: Calendar, asOf: Date) -> Analysis {
        var analysis = Analysis()
        let working = input.sets
            .filter { !$0.isWarmup && $0.completedAt <= asOf }
            .sorted { $0.completedAt < $1.completedAt }
        analysis.workingSets = working
        let setsByWorkout = Dictionary(grouping: working, by: \.workoutID)
        let workouts = input.workouts
            .filter { $0.endedAt != nil && $0.startedAt <= asOf }
            .sorted { $0.startedAt < $1.startedAt }

        let es = config.effectiveSet
        let minDuration = Double(config.qualifyingWorkout.minDurationMinutes) * 60.0
        let pr = config.prVerificationValues
        var trackers: [UUID: PRTracker] = [:]
        var daysWithQualifying: Set<Int> = []

        for workout in workouts {
            guard let endedAt = workout.endedAt else { continue }
            let sets = setsByWorkout[workout.id] ?? []

            // Per-set filters: rep bounds, 40% floor vs best verified e1RM once
            // history exists, first N per exercise, first M per workout (completedAt order).
            var perExerciseCount: [UUID: Int] = [:]
            var totalCount = 0
            var candidates: [SetSample] = []
            for set in sets {
                guard set.reps >= es.minReps, set.reps <= es.maxReps else { continue }
                if let best = trackers[set.exerciseID]?.verifiedBestGrams, best > 0,
                   Double(set.weightGrams) < es.minFractionOfBestE1RM * Double(best) {
                    continue
                }
                let exerciseCount = perExerciseCount[set.exerciseID, default: 0]
                guard exerciseCount < es.maxSetsPerExercisePerWorkout,
                      totalCount < es.maxSetsPerWorkout else { continue }
                perExerciseCount[set.exerciseID] = exerciseCount + 1
                totalCount += 1
                candidates.append(set)
            }

            guard endedAt.timeIntervalSince(workout.startedAt) >= minDuration,
                  candidates.count >= config.qualifyingWorkout.minEffectiveSets else { continue }

            let dayKey = calendar.dateKey(for: workout.startedAt)
            let isFirst = !daysWithQualifying.contains(dayKey)
            daysWithQualifying.insert(dayKey)

            var tonnage = 0
            var exerciseIDs: Set<UUID> = []
            if isFirst {
                var order: [UUID] = []
                var groups: [UUID: [SetSample]] = [:]
                for set in candidates {
                    if groups[set.exerciseID] == nil { order.append(set.exerciseID) }
                    groups[set.exerciseID, default: []].append(set)
                    tonnage += set.weightGrams * set.reps
                    exerciseIDs.insert(set.exerciseID)
                }
                for exerciseID in order {
                    processExerciseDay(sets: groups[exerciseID] ?? [], exerciseID: exerciseID,
                                       dayKey: dayKey, workoutID: workout.id,
                                       tracker: &trackers[exerciseID, default: PRTracker()],
                                       into: &analysis, pr: pr)
                }
            }

            analysis.sessions.append(Session(
                workout: workout,
                endedAt: endedAt,
                dayKey: dayKey,
                dayStart: calendar.startOfDay(for: workout.startedAt),
                candidateSetCount: candidates.count,
                isFirstQualifyingOfDay: isFirst,
                effectiveTonnageGrams: tonnage,
                effectiveExerciseIDs: exerciseIDs
            ))
        }
        return analysis
    }

    /// PR pipeline for one exercise on one calendar day (day granularity matches
    /// the design's "a later workout on a different calendar day" verification rule).
    private static func processExerciseDay(sets: [SetSample], exerciseID: UUID, dayKey: Int,
                                           workoutID: UUID, tracker: inout PRTracker,
                                           into analysis: inout Analysis,
                                           pr: (provisionalAboveFraction: Double,
                                                verifyWithinFraction: Double,
                                                minPriorSessions: Int)) {
        guard !sets.isEmpty else { return }
        let records = sets.map { ($0, ProgressEngine.e1RMGrams(weightGrams: $0.weightGrams, reps: $0.reps)) }
        var bestIndex = 0
        for (index, record) in records.enumerated() where record.1 > records[bestIndex].1 {
            bestIndex = index
        }
        let dayBest = records[bestIndex].1
        let bestSample = records[bestIndex].0
        let priorDays = tracker.sessionDayCount
        let baseIndex = analysis.effectiveSets.count

        let confirmsPending = tracker.hasPending
            && tracker.pendingDayKey != dayKey
            && Double(dayBest) >= Double(tracker.pendingGrams) * (1.0 - pr.verifyWithinFraction)

        if confirmsPending {
            for record in records {
                analysis.effectiveSets.append(EffectiveSetRecord(
                    sample: record.0, e1RMGrams: record.1, verifiedAt: record.0.completedAt))
            }
            let confirmDate = bestSample.completedAt
            for index in tracker.pendingIndices {
                analysis.effectiveSets[index].verifiedAt = confirmDate
            }
            let newBest = max(tracker.pendingGrams, dayBest)
            if newBest > tracker.verifiedBestGrams {
                if priorDays >= pr.minPriorSessions {
                    analysis.prEvents.append(PREvent(date: confirmDate, exerciseID: exerciseID,
                                                     muscle: bestSample.muscle,
                                                     workoutID: workoutID, e1RMGrams: newBest))
                }
                tracker.verifiedBestGrams = newBest
            }
            tracker.hasPending = false
            tracker.pendingIndices = []
        } else if tracker.verifiedBestGrams > 0,
                  Double(dayBest) > Double(tracker.verifiedBestGrams) * (1.0 + pr.provisionalAboveFraction) {
            // Unconfirmed jump: quarantine the readings above the verified best.
            // The most recent provisional candidate replaces any stale pending
            // claim, so a typo'd entry can never block future verification.
            var indices: [Int] = []
            for (offset, record) in records.enumerated() {
                let verified = record.1 <= tracker.verifiedBestGrams
                analysis.effectiveSets.append(EffectiveSetRecord(
                    sample: record.0, e1RMGrams: record.1,
                    verifiedAt: verified ? record.0.completedAt : nil))
                if !verified { indices.append(baseIndex + offset) }
            }
            tracker.hasPending = true
            tracker.pendingGrams = dayBest
            tracker.pendingDayKey = dayKey
            tracker.pendingIndices = indices
        } else {
            for record in records {
                analysis.effectiveSets.append(EffectiveSetRecord(
                    sample: record.0, e1RMGrams: record.1, verifiedAt: record.0.completedAt))
            }
            if tracker.verifiedBestGrams == 0 {
                tracker.verifiedBestGrams = dayBest  // bootstrap: first exposure sets the baseline
            } else if dayBest > tracker.verifiedBestGrams {
                tracker.verifiedBestGrams = dayBest
                if priorDays >= pr.minPriorSessions {
                    analysis.prEvents.append(PREvent(date: bestSample.completedAt,
                                                     exerciseID: exerciseID,
                                                     muscle: bestSample.muscle,
                                                     workoutID: workoutID, e1RMGrams: dayBest))
                }
            }
        }
        if tracker.lastDayKey != dayKey {
            tracker.sessionDayCount += 1
            tracker.lastDayKey = dayKey
        }
    }

    // MARK: - Power Level

    struct PLBreakdown {
        let pl: Int
        let ssLb: Double
        let wvlLb: Double
        let cm: Double
        let streak: Int
    }

    static func plBreakdown(at moment: Date, analysis: Analysis,
                            config: ProgressionConfig, calendar: Calendar) -> PLBreakdown {
        let plc = config.powerLevel
        let ssStart = calendar.date(byAdding: .day, value: -plc.strengthWindowDays, to: moment) ?? moment
        var ssLb = 0.0
        for muscle in primaryMuscles {
            var best = 0
            for record in analysis.effectiveSets {
                guard record.sample.muscle == muscle,
                      record.sample.completedAt > ssStart,
                      record.sample.completedAt <= moment,
                      let verifiedAt = record.verifiedAt, verifiedAt <= moment else { continue }
                best = max(best, record.e1RMGrams)
            }
            ssLb += Units.pounds(fromGrams: best)
        }

        let volStart = calendar.date(byAdding: .day, value: -plc.volumeWindowDays, to: moment) ?? moment
        var tonnageGrams = 0
        for record in analysis.effectiveSets
        where record.sample.completedAt > volStart && record.sample.completedAt <= moment {
            // Same anti-cheese quarantine as the Strength Score: a provisional (not yet
            // verified) set — including a fat-fingered mis-log — doesn't count toward
            // volume (and thus PL + tonnage badges) until a later distinct-day session
            // confirms it.
            guard let verifiedAt = record.verifiedAt, verifiedAt <= moment else { continue }
            tonnageGrams += record.sample.weightGrams * record.sample.reps
        }
        let windowWeeks = Double(plc.volumeWindowDays) / 7.0
        let wvlLb = windowWeeks > 0 ? Units.pounds(fromGrams: tonnageGrams) / windowWeeks : 0

        let qualifyingDates = analysis.sessions
            .filter { $0.isFirstQualifyingOfDay && $0.workout.startedAt <= moment }
            .map(\.workout.startedAt)
        let streak = StreakEngine.streakWeeks(workoutDates: qualifyingDates,
                                              minDaysPerWeek: plc.streakMinDaysPerWeek,
                                              calendar: calendar, asOf: moment)
        let cm = 1.0 + plc.consistencyPerWeek * Double(min(streak, plc.consistencyMaxWeeks))
        let raw = (plc.strengthWeight * ssLb + plc.volumeWeight * wvlLb.squareRoot()) * cm
        let pl = qualifyingDates.isEmpty ? 0 : Int(raw.rounded())
        return PLBreakdown(pl: pl, ssLb: ssLb, wvlLb: wvlLb, cm: cm, streak: streak)
    }

    // MARK: - XP economy

    static func computeXP(analysis: Analysis, qualifying: [Session], badges: [BadgeGrant],
                          netPositive: [UUID: Bool], input: ProgressionInput,
                          config: ProgressionConfig, calendar: Calendar,
                          asOf: Date) -> [CharacterKey: Int] {
        var xp: [CharacterKey: Int] = [:]
        for character in CharacterKey.allCases { xp[character] = 0 }

        var prCountByWorkout: [UUID: Int] = [:]
        for event in analysis.prEvents {
            prCountByWorkout[event.workoutID, default: 0] += 1
        }

        // Workout XP -> vego, with same-day decay, daily cap, and the
        // max-XP-earning-days-per-rolling-7 rule.
        let base = config.xpInt("workoutBase", 50)
        let perSet = config.xpInt("perEffectiveSet", 2)
        let perSetCap = config.xpInt("perEffectiveSetCap", 60)
        let netBonus = config.xpInt("positiveNetBonus", 25)
        let perPR = config.xpInt("perVerifiedPR", 10)
        let prCap = config.xpInt("verifiedPRCapPerWorkout", 3)
        let secondFraction = config.xpDouble("secondWorkoutSameDayFraction", 0.25)
        let thirdFraction = config.xpDouble("thirdWorkoutSameDayFraction", 0.0)
        let maxDaysPer7 = config.xpInt("maxXPDaysPerRolling7", 6)
        let dailyCap = config.xpInt("dailyWorkoutXPCap", 300)
        let restedMultiplier = config.xpDouble("restedBonusMultiplier", 1.25)

        var earningDayStarts: [Date] = []
        var previousQualifyingDayStart: Date?
        var vegoXP = 0
        var index = 0
        let sessions = analysis.sessions
        while index < sessions.count {
            let dayKey = sessions[index].dayKey
            let dayStart = sessions[index].dayStart
            // Rested bonus (exact predicate documented on isRested): boosts the
            // workout-XP components before same-day decay; dailyCap still caps.
            let rested = isRested(dayStart: dayStart,
                                  previousQualifyingDayStart: previousQualifyingDayStart,
                                  calendar: calendar)
            var dayXP = 0
            var rank = 0
            var next = index
            while next < sessions.count, sessions[next].dayKey == dayKey {
                let session = sessions[next]
                rank += 1
                let fraction: Double = rank == 1 ? 1.0 : (rank == 2 ? secondFraction : thirdFraction)
                if fraction > 0 {
                    var raw = base
                    raw += min(perSet * session.candidateSetCount, perSetCap)
                    if netPositive[session.workout.id] == true { raw += netBonus }
                    raw += perPR * min(prCountByWorkout[session.workout.id] ?? 0, prCap)
                    let boosted = Double(raw) * (rested ? restedMultiplier : 1.0)
                    dayXP += Int((boosted * fraction).rounded())
                }
                next += 1
            }
            dayXP = min(dayXP, dailyCap)
            if dayXP > 0 {
                // Rolling 7-day window: this day plus the previous 6 may hold at
                // most `maxXPDaysPerRolling7` earning days.
                let rollingWindowDays = 7
                let recent = earningDayStarts.count {
                    daysBetween($0, dayStart, calendar: calendar) <= rollingWindowDays - 1
                }
                if recent + 1 <= maxDaysPer7 {
                    vegoXP += dayXP
                    earningDayStarts.append(dayStart)
                }
            }
            previousQualifyingDayStart = dayStart
            index = next
        }
        xp[.vego, default: 0] += vegoXP

        // Badge XP -> owning character.
        for grant in badges {
            guard let def = config.badge(grant.key) else { continue }
            xp[def.character, default: 0] += config.badgeXP(rarity: def.rarity)
        }

        // Goal completion XP -> vego, with a Torren echo.
        let qualDaysPerWeek = qualifyingDaysPerWeek(qualifying: qualifying, calendar: calendar)
        let torrenEcho = config.xpInt("goalTorrenEcho", 25)
        for goal in input.goals {
            guard let completedAt = goal.completedAt, completedAt <= asOf else { continue }
            switch goal.kind {
            case .frequency:
                var achievedWeeks = 0
                for weekStart in weekStarts(from: goal.startDate, upToWeekContaining: completedAt,
                                            calendar: calendar, includeFinal: true) {
                    let ordinal = weekOrdinal(weekStart, calendar: calendar)
                    if (qualDaysPerWeek[ordinal]?.count ?? 0) >= goal.targetValue { achievedWeeks += 1 }
                }
                xp[.vego, default: 0] += achievedWeeks * config.goalXPInt("frequency_week", 40)
                xp[.vego, default: 0] += config.goalXPInt("frequency_finish", 100)
            case .prTarget:
                xp[.vego, default: 0] += config.goalXPInt("pr_target", 150)
            case .volumeTarget:
                xp[.vego, default: 0] += config.goalXPInt("volume_target", 100)
            }
            xp[.torren, default: 0] += torrenEcho
        }

        // Domain drip.
        let barokPerK = config.dripInt("barokPer1000LbTonnage", 1)
        let barokCap = config.dripInt("barokPerWorkoutCap", 30)
        let torrenPerOnPlan = config.dripInt("torrenPerOnPlanWorkout", 15)
        let nyraPerWeek = config.dripInt("nyraPerStreakWeek", 30)
        let ziaPerNight = config.dripInt("ziaPerSleepNight", 2)
        let ziaWeeklyCap = config.dripInt("ziaSleepWeeklyCap", 14)
        let gosiPerNewExercise = config.dripInt("gosiPerNewExercise", 10)
        let zynPerOffHours = config.dripInt("zynPerOffHoursWorkout", 10)
        let zynPerComeback = config.dripInt("zynPerComeback", 50)
        let dawnBeforeHour = config.badge("dawn_patrol")?.params["beforeHour"] ?? 7
        let nightAfterHour = config.badge("midnight_oil")?.params["afterHour"] ?? 21
        let comebackGapDays = config.badge("return_to_form")?.params["gapDays"] ?? 21

        for session in qualifying {
            let tonnageLb = Units.pounds(fromGrams: session.effectiveTonnageGrams)
            xp[.barok, default: 0] += min(Int(tonnageLb / 1000.0) * barokPerK, barokCap)
            if session.workout.routineID != nil {
                xp[.torren, default: 0] += torrenPerOnPlan
            }
            let hour = calendar.component(.hour, from: session.workout.startedAt)
            if hour < dawnBeforeHour || hour >= nightAfterHour {
                xp[.zyn, default: 0] += zynPerOffHours
            }
        }

        // Nyra: completed weeks with enough distinct qualifying days.
        if let firstDate = qualifying.first?.workout.startedAt {
            for weekStart in weekStarts(from: firstDate, upToWeekContaining: asOf,
                                        calendar: calendar, includeFinal: false) {
                let ordinal = weekOrdinal(weekStart, calendar: calendar)
                if (qualDaysPerWeek[ordinal]?.count ?? 0) >= config.powerLevel.streakMinDaysPerWeek {
                    xp[.nyra, default: 0] += nyraPerWeek
                }
            }
        }

        // Zia: synced sleep nights, weekly-capped.
        let asOfDayKey = calendar.dateKey(for: asOf)
        var nightsPerWeek: [Int: Int] = [:]
        for night in input.sleep where night.dateKey <= asOfDayKey {
            guard let date = dateFromKey(night.dateKey, calendar: calendar) else { continue }
            nightsPerWeek[weekOrdinal(date, calendar: calendar), default: 0] += 1
        }
        for (_, count) in nightsPerWeek {
            xp[.zia, default: 0] += min(count * ziaPerNight, ziaWeeklyCap)
        }

        // Gosi: distinct exercises with at least one effective set.
        let distinctExercises = Set(analysis.effectiveSets.map(\.sample.exerciseID))
        xp[.gosi, default: 0] += distinctExercises.count * gosiPerNewExercise

        // Zyn: comeback events (first workout after a long gap).
        let trainedDays = distinctQualifyingDayStarts(qualifying: qualifying)
        for pairIndex in 0..<max(0, trainedDays.count - 1)
        where daysBetween(trainedDays[pairIndex], trainedDays[pairIndex + 1], calendar: calendar) >= comebackGapDays {
            xp[.zyn, default: 0] += zynPerComeback
        }

        return xp
    }

    // MARK: - Levels & tiers

    /// Highest level whose cumulative XP requirement (levelCurveBase * L^exponent)
    /// is met; the floor is level 1.
    static func level(forXP xp: Int, config: ProgressionConfig) -> Int {
        let base = config.xpDouble("levelCurveBase", 100.0)
        let exponent = config.xpDouble("levelCurveExponent", 1.8)
        let maxLevel = config.xpInt("maxLevel", 40)
        var level = 1
        var candidate = 1
        while candidate <= maxLevel {
            let needed = Int((base * pow(Double(candidate), exponent)).rounded())
            if xp >= needed {
                level = candidate
                candidate += 1
            } else {
                break
            }
        }
        return level
    }

    /// Walks the tier ladder in order; each gate needs the level AND its
    /// keystone badge (or domain-badge count). The first unmet gate stops the climb.
    static func tier(for character: CharacterKey, level: Int,
                     earnedBadgeKeys: Set<String>, config: ProgressionConfig) -> TransformationTier {
        guard let gates = config.tiers[character.rawValue] as? [String: Any] else { return .base }
        let domainCount = earnedBadgeKeys.count { config.badge($0)?.character == character }
        var result = TransformationTier.base
        for tier in TransformationTier.allCases where tier != .base {
            guard let gate = gates[tier.displayName.lowercased()] as? [String: Any],
                  let requiredLevel = gate["level"] as? Int else { break }
            var met = level >= requiredLevel
            if let keystone = gate["keystone"] as? String {
                met = met && earnedBadgeKeys.contains(keystone)
            }
            if let requiredCount = gate["domainBadgeCount"] as? Int {
                met = met && domainCount >= requiredCount
            }
            guard met else { break }
            result = tier
        }
        return result
    }

    // MARK: - Shared date helpers

    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }

    static func weekOrdinal(_ date: Date, calendar: Calendar) -> Int {
        ProgressEngine.bucketKey(for: date, period: .week, calendar: calendar).ordinal
    }

    static func dateFromKey(_ dateKey: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = dateKey / 10_000
        components.month = (dateKey / 100) % 100
        components.day = dateKey % 100
        components.hour = 12
        return calendar.date(from: components)
    }

    /// Week-start dates from the week containing `from` up to the week containing
    /// `boundary` — exclusive of that final week unless `includeFinal`.
    static func weekStarts(from: Date, upToWeekContaining boundary: Date,
                           calendar: Calendar, includeFinal: Bool) -> [Date] {
        guard let firstStart = calendar.dateInterval(of: .weekOfYear, for: from)?.start,
              let boundaryStart = calendar.dateInterval(of: .weekOfYear, for: boundary)?.start,
              firstStart <= boundaryStart else { return [] }
        var starts: [Date] = []
        var cursor = firstStart
        while cursor < boundaryStart {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        if includeFinal { starts.append(boundaryStart) }
        return starts
    }

    static func qualifyingDaysPerWeek(qualifying: [Session], calendar: Calendar) -> [Int: Set<Int>] {
        var perWeek: [Int: Set<Int>] = [:]
        for session in qualifying {
            perWeek[weekOrdinal(session.workout.startedAt, calendar: calendar), default: []]
                .insert(session.dayKey)
        }
        return perWeek
    }

    static func distinctQualifyingDayStarts(qualifying: [Session]) -> [Date] {
        var seen: Set<Int> = []
        var days: [Date] = []
        for session in qualifying where !seen.contains(session.dayKey) {
            seen.insert(session.dayKey)
            days.append(session.dayStart)
        }
        return days
    }
}

// MARK: - Badge evaluation (all 30, keyed exactly as progression_config.json)

private struct BadgeEvaluator {
    let analysis: ProgressionEngine.Analysis
    let qualifying: [ProgressionEngine.Session]
    let plEvals: [(date: Date, pl: Int)]
    let netPositive: [UUID: Bool]
    let input: ProgressionInput
    let config: ProgressionConfig
    let calendar: Calendar
    let asOf: Date

    // Precomputed context.
    let completedGoals: [GoalSample]
    let sleepByDateKey: [Int: SleepSample]
    let qualDaysPerWeek: [Int: Set<Int>]
    let qualPerWeek: [Int: [ProgressionEngine.Session]]
    let trainedDayStarts: [Date]

    init(analysis: ProgressionEngine.Analysis, qualifying: [ProgressionEngine.Session],
         plEvals: [(date: Date, pl: Int)], netPositive: [UUID: Bool],
         input: ProgressionInput, config: ProgressionConfig, calendar: Calendar, asOf: Date) {
        self.analysis = analysis
        self.qualifying = qualifying
        self.plEvals = plEvals
        self.netPositive = netPositive
        self.input = input
        self.config = config
        self.calendar = calendar
        self.asOf = asOf
        self.completedGoals = input.goals
            .filter { $0.completedAt != nil && ($0.completedAt ?? asOf) <= asOf }
            .sorted { ($0.completedAt ?? asOf) < ($1.completedAt ?? asOf) }
        var sleepMap: [Int: SleepSample] = [:]
        let asOfKey = calendar.dateKey(for: asOf)
        for night in input.sleep where night.dateKey <= asOfKey {
            sleepMap[night.dateKey] = night
        }
        self.sleepByDateKey = sleepMap
        self.qualDaysPerWeek = ProgressionEngine.qualifyingDaysPerWeek(qualifying: qualifying,
                                                                       calendar: calendar)
        var perWeek: [Int: [ProgressionEngine.Session]] = [:]
        for session in qualifying {
            perWeek[ProgressionEngine.weekOrdinal(session.workout.startedAt, calendar: calendar),
                    default: []].append(session)
        }
        self.qualPerWeek = perWeek
        self.trainedDayStarts = ProgressionEngine.distinctQualifyingDayStarts(qualifying: qualifying)
    }

    func grant(for def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        switch def.key {
        case "new_ceiling", "limit_break", "walking_legend":
            return prCountGrant(def)
        case "triple_threat":
            return tripleThreat(def)
        case "perfect_form":
            return perfectForm(def)
        case "scanner_breaker":
            return scannerBreaker(def)
        case "twenty_ton_day":
            return twentyTonDay(def)
        case "hundred_grand", "million_pound_club", "ten_million":
            return lifetimeTonnage(def)
        case "ignition":
            return nthQualifyingWorkout(def, threshold: def.params["threshold"] ?? 1) { _ in true }
        case "steady_flame", "chamber_regular", "chamber_resident", "unbroken_year":
            return consecutiveWeeks(def, weeks: def.params["weeks"] ?? 4,
                                    daysPerWeek: def.params["daysPerWeek"] ?? 1)
        case "goal_getter":
            return nthCompletedGoal(def, threshold: def.params["threshold"] ?? 1) { _ in true }
        case "marksman":
            return nthCompletedGoal(def, threshold: def.params["threshold"] ?? 1) { $0.kind == .prTarget }
        case "serial_achiever":
            return nthCompletedGoal(def, threshold: def.params["threshold"] ?? 10) { _ in true }
        case "by_the_book":
            return nthQualifyingWorkout(def, threshold: def.params["threshold"] ?? 12) {
                $0.workout.routineID != nil
            }
        case "planners_pride":
            return plannersPride(def)
        case "lab_partner":
            return labPartner(def)
        case "well_rested":
            return wellRested(def)
        case "recovery_protocol":
            return recoveryProtocol(def)
        case "explorer":
            return explorer(def)
        case "full_arsenal":
            return fullArsenal(def)
        case "momentum":
            return momentum(def)
        case "dawn_patrol":
            return nthQualifyingWorkout(def, threshold: def.params["threshold"] ?? 10) {
                calendar.component(.hour, from: $0.workout.startedAt) < (def.params["beforeHour"] ?? 7)
            }
        case "midnight_oil":
            return nthQualifyingWorkout(def, threshold: def.params["threshold"] ?? 10) {
                calendar.component(.hour, from: $0.workout.startedAt) >= (def.params["afterHour"] ?? 21)
            }
        case "return_to_form":
            return returnToForm(def)
        case "reforged":
            return reforged(def)
        default:
            return nil
        }
    }

    // MARK: Kael/Vego — PRs & power

    private func prCountGrant(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let threshold = def.params["threshold"] ?? 1
        guard threshold >= 1, analysis.prEvents.count >= threshold else { return nil }
        let event = analysis.prEvents[threshold - 1]
        return BadgeGrant(key: def.key, earnedAt: event.date, valueSnapshot: threshold,
                          workoutID: event.workoutID, exerciseID: event.exerciseID)
    }

    private func tripleThreat(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let needed = def.params["threshold"] ?? 3
        var musclesPerWeek: [Int: Set<Muscle>] = [:]
        for event in analysis.prEvents {
            let ordinal = ProgressionEngine.weekOrdinal(event.date, calendar: calendar)
            musclesPerWeek[ordinal, default: []].insert(event.muscle)
            if musclesPerWeek[ordinal, default: []].count >= needed {
                return BadgeGrant(key: def.key, earnedAt: event.date, valueSnapshot: needed,
                                  workoutID: event.workoutID, exerciseID: event.exerciseID)
            }
        }
        return nil
    }

    private func perfectForm(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let minExercises = def.params["threshold"] ?? 4
        for session in qualifying where session.effectiveExerciseIDs.count >= minExercises {
            let allPositive = session.effectiveExerciseIDs.allSatisfy { exerciseID in
                let exerciseSets = analysis.workingSets.filter { $0.exerciseID == exerciseID }
                return ProgressEngine.workoutNet(samples: exerciseSets,
                                                 workoutID: session.workout.id).volumeGrams > 0
            }
            if allPositive {
                return BadgeGrant(key: def.key, earnedAt: session.endedAt,
                                  valueSnapshot: session.effectiveExerciseIDs.count,
                                  workoutID: session.workout.id, exerciseID: nil)
            }
        }
        return nil
    }

    private func scannerBreaker(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let threshold = def.params["threshold"] ?? 9000
        for eval in plEvals where eval.pl > threshold {
            return BadgeGrant(key: def.key, earnedAt: eval.date, valueSnapshot: eval.pl,
                              workoutID: nil, exerciseID: nil)
        }
        return nil
    }

    // MARK: Barok — volume

    private func twentyTonDay(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let thresholdLb = def.params["thresholdLb"] ?? 20_000
        for session in qualifying {
            let tonnageLb = Units.pounds(fromGrams: session.effectiveTonnageGrams)
            if tonnageLb >= Double(thresholdLb) {
                return BadgeGrant(key: def.key, earnedAt: session.endedAt,
                                  valueSnapshot: Int(tonnageLb.rounded()),
                                  workoutID: session.workout.id, exerciseID: nil)
            }
        }
        return nil
    }

    private func lifetimeTonnage(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let thresholdLb = Double(def.params["thresholdLb"] ?? 100_000)
        var cumulativeGrams = 0
        for record in analysis.effectiveSets {
            cumulativeGrams += record.sample.weightGrams * record.sample.reps
            let cumulativeLb = Units.pounds(fromGrams: cumulativeGrams)
            if cumulativeLb >= thresholdLb {
                return BadgeGrant(key: def.key, earnedAt: record.sample.completedAt,
                                  valueSnapshot: Int(cumulativeLb.rounded()),
                                  workoutID: record.sample.workoutID, exerciseID: nil)
            }
        }
        return nil
    }

    // MARK: Shared count-based helpers

    private func nthQualifyingWorkout(_ def: ProgressionConfig.BadgeDef, threshold: Int,
                                      where predicate: (ProgressionEngine.Session) -> Bool) -> BadgeGrant? {
        guard threshold >= 1 else { return nil }
        var count = 0
        for session in qualifying where predicate(session) {
            count += 1
            if count == threshold {
                return BadgeGrant(key: def.key, earnedAt: session.endedAt, valueSnapshot: threshold,
                                  workoutID: session.workout.id, exerciseID: nil)
            }
        }
        return nil
    }

    private func nthCompletedGoal(_ def: ProgressionConfig.BadgeDef, threshold: Int,
                                  where predicate: (GoalSample) -> Bool) -> BadgeGrant? {
        guard threshold >= 1 else { return nil }
        var count = 0
        for goal in completedGoals where predicate(goal) {
            count += 1
            if count == threshold, let completedAt = goal.completedAt {
                return BadgeGrant(key: def.key, earnedAt: completedAt, valueSnapshot: threshold,
                                  workoutID: nil, exerciseID: goal.exerciseID)
            }
        }
        return nil
    }

    // MARK: Nyra — streak weeks

    private func consecutiveWeeks(_ def: ProgressionConfig.BadgeDef,
                                  weeks: Int, daysPerWeek: Int) -> BadgeGrant? {
        guard weeks >= 1, let firstDate = qualifying.first?.workout.startedAt else { return nil }
        var run = 0
        for weekStart in ProgressionEngine.weekStarts(from: firstDate, upToWeekContaining: asOf,
                                                      calendar: calendar, includeFinal: false) {
            let ordinal = ProgressionEngine.weekOrdinal(weekStart, calendar: calendar)
            if (qualDaysPerWeek[ordinal]?.count ?? 0) >= daysPerWeek {
                run += 1
                if run >= weeks {
                    let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
                    return BadgeGrant(key: def.key, earnedAt: weekEnd, valueSnapshot: weeks,
                                      workoutID: nil, exerciseID: nil)
                }
            } else {
                run = 0
            }
        }
        return nil
    }

    // MARK: Torren — adherence

    /// SIMPLIFIED on-plan semantics (routine weekday masks are not part of
    /// ProgressionInput): a week is "on plan" when it has at least one qualifying
    /// workout and every qualifying workout that week was started from a routine.
    private func plannersPride(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let weeks = def.params["weeks"] ?? 4
        guard weeks >= 1, let firstDate = qualifying.first?.workout.startedAt else { return nil }
        var run = 0
        for weekStart in ProgressionEngine.weekStarts(from: firstDate, upToWeekContaining: asOf,
                                                      calendar: calendar, includeFinal: false) {
            let ordinal = ProgressionEngine.weekOrdinal(weekStart, calendar: calendar)
            let sessions = qualPerWeek[ordinal] ?? []
            if !sessions.isEmpty, sessions.allSatisfy({ $0.workout.routineID != nil }) {
                run += 1
                if run >= weeks {
                    let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
                    return BadgeGrant(key: def.key, earnedAt: weekEnd, valueSnapshot: weeks,
                                      workoutID: nil, exerciseID: nil)
                }
            } else {
                run = 0
            }
        }
        return nil
    }

    // MARK: Zia — sleep

    private func labPartner(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let threshold = def.params["threshold"] ?? 7
        let nights = sleepByDateKey.keys.sorted()
        guard threshold >= 1, nights.count >= threshold else { return nil }
        guard let earnedAt = ProgressionEngine.dateFromKey(nights[threshold - 1],
                                                           calendar: calendar) else { return nil }
        return BadgeGrant(key: def.key, earnedAt: earnedAt, valueSnapshot: threshold,
                          workoutID: nil, exerciseID: nil)
    }

    private func wellRested(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let needed = def.params["threshold"] ?? 5
        let minScore = def.params["sleepScore"] ?? 80
        let windowDays = def.params["windowDays"] ?? 30
        var restedDates: [Date] = []
        for session in qualifying {
            let score = sleepByDateKey[session.dayKey]?.sleepScore ?? 0
            guard score >= minScore else { continue }
            restedDates.append(session.dayStart)
            let inWindow = restedDates.count {
                ProgressionEngine.daysBetween($0, session.dayStart, calendar: calendar) <= windowDays
            }
            if inWindow >= needed {
                return BadgeGrant(key: def.key, earnedAt: session.endedAt, valueSnapshot: needed,
                                  workoutID: session.workout.id, exerciseID: nil)
            }
        }
        return nil
    }

    private func recoveryProtocol(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let minSleepSeconds = (def.params["sleepHours"] ?? 7) * 3600
        let minDays = def.params["daysPerWeek"] ?? 3
        guard let firstDate = qualifying.first?.workout.startedAt else { return nil }
        for weekStart in ProgressionEngine.weekStarts(from: firstDate, upToWeekContaining: asOf,
                                                      calendar: calendar, includeFinal: false) {
            let ordinal = ProgressionEngine.weekOrdinal(weekStart, calendar: calendar)
            let trainedDays = qualDaysPerWeek[ordinal]?.count ?? 0
            guard trainedDays >= minDays else { continue }
            var allNightsRested = true
            for dayOffset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                      let night = sleepByDateKey[calendar.dateKey(for: day)],
                      (night.totalSleepSeconds ?? 0) >= minSleepSeconds else {
                    allNightsRested = false
                    break
                }
            }
            if allNightsRested {
                let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
                return BadgeGrant(key: def.key, earnedAt: weekEnd, valueSnapshot: trainedDays,
                                  workoutID: nil, exerciseID: nil)
            }
        }
        return nil
    }

    // MARK: Gosi — breadth & dawn

    private func explorer(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let threshold = def.params["threshold"] ?? 20
        var seen: Set<UUID> = []
        for record in analysis.effectiveSets where !seen.contains(record.sample.exerciseID) {
            seen.insert(record.sample.exerciseID)
            if seen.count == threshold {
                return BadgeGrant(key: def.key, earnedAt: record.sample.completedAt,
                                  valueSnapshot: threshold,
                                  workoutID: record.sample.workoutID,
                                  exerciseID: record.sample.exerciseID)
            }
        }
        return nil
    }

    private func fullArsenal(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let windowDays = def.params["windowDays"] ?? 7
        var lastSeen: [Muscle: Date] = [:]
        for record in analysis.effectiveSets {
            let muscle = record.sample.muscle
            guard ProgressionEngine.primaryMuscles.contains(muscle) else { continue }
            lastSeen[muscle] = record.sample.completedAt
            guard lastSeen.count == ProgressionEngine.primaryMuscles.count else { continue }
            let windowStart = calendar.date(byAdding: .day, value: -windowDays,
                                            to: record.sample.completedAt) ?? record.sample.completedAt
            if lastSeen.values.allSatisfy({ $0 >= windowStart }) {
                return BadgeGrant(key: def.key, earnedAt: record.sample.completedAt,
                                  valueSnapshot: ProgressionEngine.primaryMuscles.count,
                                  workoutID: record.sample.workoutID, exerciseID: nil)
            }
        }
        return nil
    }

    // MARK: Zyn — momentum & comebacks

    private func momentum(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let needed = def.params["threshold"] ?? 5
        guard needed >= 1 else { return nil }
        var runs: [String: Int] = [:]
        for session in qualifying {
            let slot = session.workout.routineID?.uuidString ?? "title:\(session.workout.title)"
            if netPositive[session.workout.id] == true {
                let run = (runs[slot] ?? 0) + 1
                runs[slot] = run
                if run >= needed {
                    return BadgeGrant(key: def.key, earnedAt: session.endedAt, valueSnapshot: needed,
                                      workoutID: session.workout.id, exerciseID: nil)
                }
            } else {
                runs[slot] = 0
            }
        }
        return nil
    }

    private func returnToForm(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let gapDays = def.params["gapDays"] ?? 21
        let workoutsNeeded = def.params["workouts"] ?? 3
        let windowDays = def.params["windowDays"] ?? 14
        guard trainedDayStarts.count >= 2 else { return nil }
        for index in 0..<(trainedDayStarts.count - 1) {
            let gap = ProgressionEngine.daysBetween(trainedDayStarts[index],
                                                    trainedDayStarts[index + 1], calendar: calendar)
            guard gap >= gapDays else { continue }
            let comeback = trainedDayStarts[index + 1]
            let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: comeback) ?? comeback
            let wins = qualifying.filter {
                $0.workout.startedAt >= comeback && $0.workout.startedAt < windowEnd
            }
            if wins.count >= workoutsNeeded {
                return BadgeGrant(key: def.key, earnedAt: wins[workoutsNeeded - 1].endedAt,
                                  valueSnapshot: workoutsNeeded,
                                  workoutID: wins[workoutsNeeded - 1].workout.id, exerciseID: nil)
            }
        }
        return nil
    }

    private func reforged(_ def: ProgressionConfig.BadgeDef) -> BadgeGrant? {
        let gapDays = def.params["gapDays"] ?? 21
        let windowDays = def.params["windowDays"] ?? 60
        guard trainedDayStarts.count >= 2 else { return nil }
        for index in 0..<(trainedDayStarts.count - 1) {
            let gap = ProgressionEngine.daysBetween(trainedDayStarts[index],
                                                    trainedDayStarts[index + 1], calendar: calendar)
            guard gap >= gapDays else { continue }
            let comeback = trainedDayStarts[index + 1]
            var preGapBest: [UUID: Int] = [:]
            for record in analysis.effectiveSets {
                guard record.sample.completedAt < comeback,
                      let verifiedAt = record.verifiedAt, verifiedAt < comeback else { continue }
                preGapBest[record.sample.exerciseID] = max(preGapBest[record.sample.exerciseID] ?? 0,
                                                           record.e1RMGrams)
            }
            let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: comeback) ?? comeback
            var earliest: BadgeGrant?
            for record in analysis.effectiveSets {
                guard record.sample.completedAt >= comeback,
                      record.sample.completedAt < windowEnd,
                      let verifiedAt = record.verifiedAt,
                      let target = preGapBest[record.sample.exerciseID], target > 0,
                      record.e1RMGrams >= target else { continue }
                let moment = max(record.sample.completedAt, verifiedAt)
                if earliest == nil || moment < earliest!.earnedAt {
                    earliest = BadgeGrant(key: def.key, earnedAt: moment,
                                          valueSnapshot: record.e1RMGrams,
                                          workoutID: record.sample.workoutID,
                                          exerciseID: record.sample.exerciseID)
                }
            }
            if let earliest { return earliest }
        }
        return nil
    }
}

// MARK: - Config raw-JSON accessors

extension ProgressionConfig {
    var prVerificationValues: (provisionalAboveFraction: Double,
                               verifyWithinFraction: Double,
                               minPriorSessions: Int) {
        let dict = raw["prVerification"] as? [String: Any] ?? [:]
        return (dict["provisionalAboveFraction"] as? Double ?? 0.15,
                dict["verifyWithinFraction"] as? Double ?? 0.10,
                dict["minPriorDistinctDaySessions"] as? Int ?? 3)
    }

    func xpInt(_ key: String, _ fallback: Int) -> Int {
        if let value = xp[key] as? Int { return value }
        if let value = xp[key] as? Double { return Int(value) }
        return fallback
    }

    func xpDouble(_ key: String, _ fallback: Double) -> Double {
        if let value = xp[key] as? Double { return value }
        if let value = xp[key] as? Int { return Double(value) }
        return fallback
    }

    func dripInt(_ key: String, _ fallback: Int) -> Int {
        ((xp["drip"] as? [String: Any])?[key] as? Int) ?? fallback
    }

    func goalXPInt(_ key: String, _ fallback: Int) -> Int {
        ((xp["goalCompletionXP"] as? [String: Any])?[key] as? Int) ?? fallback
    }
}
