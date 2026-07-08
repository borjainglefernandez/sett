import Foundation

/// Pure net-progress math over `SetSample` value snapshots (design-client §3).
/// Strict previous-calendar-bucket semantics: WoW/MoM/YoY compare the bucket
/// containing a date against the immediately preceding calendar bucket, even
/// when that bucket is empty. Warmup sets are always excluded; callers pass
/// samples already filtered of soft-deleted rows.
public enum ProgressEngine {

    // MARK: - e1RM (Epley, reps capped at 12)

    /// Epley with reps capped at 12: `w * (1 + min(r, 12) / 30)`, rounded to Int grams.
    public static func e1RMGrams(weightGrams: Int, reps: Int) -> Int {
        let cappedReps = min(max(reps, 0), 12)
        let estimate = Double(weightGrams) * (1.0 + Double(cappedReps) / 30.0)
        return Int(estimate.rounded())
    }

    // MARK: - Buckets

    /// The strict calendar bucket containing `date` in the given calendar.
    /// Week keys use ISO-style `(yearForWeekOfYear, weekOfYear)` so the ordinal
    /// stays comparable across year rollovers (week 53 → week 1).
    public static func bucketKey(for date: Date, period: Period, calendar: Calendar) -> BucketKey {
        switch period {
        case .week:
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return BucketKey(period: .week, ordinal: (c.yearForWeekOfYear ?? 0) * 100 + (c.weekOfYear ?? 0))
        case .month:
            let c = calendar.dateComponents([.year, .month], from: date)
            return BucketKey(period: .month, ordinal: (c.year ?? 0) * 100 + (c.month ?? 0))
        case .year:
            let c = calendar.dateComponents([.year], from: date)
            return BucketKey(period: .year, ordinal: c.year ?? 0)
        }
    }

    private static func component(for period: Period) -> Calendar.Component {
        switch period {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// Start of the bucket containing `date`.
    private static func bucketStart(of date: Date, period: Period, calendar: Calendar) -> Date {
        calendar.dateInterval(of: component(for: period), for: date)?.start ?? date
    }

    /// A date guaranteed to fall inside the bucket immediately preceding the
    /// one containing `date` (the last instant of it). Buckets abut exactly,
    /// so subtracting one second from the bucket start is DST-safe.
    private static func dateInPreviousBucket(of date: Date, period: Period, calendar: Calendar) -> Date {
        bucketStart(of: date, period: period, calendar: calendar).addingTimeInterval(-1)
    }

    // MARK: - Net summaries

    /// Strict previous-calendar-bucket net for one exercise (nil = all exercises).
    public static func netSummary(samples: [SetSample], exerciseID: UUID?, period: Period,
                                  containing date: Date, calendar: Calendar) -> NetSummary {
        // Casual ("off the record") sets never participate in net comparisons —
        // on either side of the bucket delta.
        let working = samples.filter { !$0.isWarmup && !$0.isCasual && (exerciseID == nil || $0.exerciseID == exerciseID) }
        return netBetweenBuckets(working, period: period, containing: date, calendar: calendar)
    }

    /// Net per exercise for the bucket containing `date`. Includes every
    /// exercise with sets in either the current or the previous bucket.
    public static func perExerciseNets(samples: [SetSample], period: Period,
                                       containing date: Date, calendar: Calendar) -> [UUID: NetSummary] {
        let currentKey = bucketKey(for: date, period: period, calendar: calendar)
        let previousDate = dateInPreviousBucket(of: date, period: period, calendar: calendar)
        let previousKey = bucketKey(for: previousDate, period: period, calendar: calendar)

        var involved: Set<UUID> = []
        for sample in samples where !sample.isWarmup && !sample.isCasual {
            let key = bucketKey(for: sample.completedAt, period: period, calendar: calendar)
            if key == currentKey || key == previousKey { involved.insert(sample.exerciseID) }
        }

        var nets: [UUID: NetSummary] = [:]
        for id in involved {
            let working = samples.filter { !$0.isWarmup && !$0.isCasual && $0.exerciseID == id }
            nets[id] = netBetweenBuckets(working, period: period, containing: date, calendar: calendar)
        }
        return nets
    }

    private static func netBetweenBuckets(_ working: [SetSample], period: Period,
                                          containing date: Date, calendar: Calendar) -> NetSummary {
        let currentKey = bucketKey(for: date, period: period, calendar: calendar)
        let previousDate = dateInPreviousBucket(of: date, period: period, calendar: calendar)
        let previousKey = bucketKey(for: previousDate, period: period, calendar: calendar)

        var currentReps = 0, currentVolume = 0, currentCount = 0
        var previousReps = 0, previousVolume = 0, previousCount = 0
        for sample in working {
            let key = bucketKey(for: sample.completedAt, period: period, calendar: calendar)
            if key == currentKey {
                currentReps += sample.reps
                currentVolume += sample.weightGrams * sample.reps
                currentCount += 1
            } else if key == previousKey {
                previousReps += sample.reps
                previousVolume += sample.weightGrams * sample.reps
                previousCount += 1
            }
        }
        return NetSummary(reps: currentReps - previousReps,
                          volumeGrams: currentVolume - previousVolume,
                          isNew: previousCount == 0 && currentCount > 0)
    }

    // MARK: - Workout-level rollup (summary screen)

    /// This workout's volume/reps minus the same exercises' totals in each
    /// exercise's most recent prior workout containing it (design-client §3.6).
    /// Exercises with no prior session contribute their full volume as bonus;
    /// `isNew` is true only when every exercise in the workout is new.
    /// A casual ("off the record") workout has no nets of its own and is never a
    /// reference for another workout, so casual sets are dropped entirely here.
    /// Called ON a casual workout's ID this returns NetSummary(0, 0, false) via the
    /// empty guard below — callers should not display it.
    public static func workoutNet(samples: [SetSample], workoutID: UUID) -> NetSummary {
        let working = samples.filter { !$0.isWarmup && !$0.isCasual }
        let thisWorkout = working.filter { $0.workoutID == workoutID }
        guard let workoutStart = thisWorkout.map(\.completedAt).min() else {
            return NetSummary(reps: 0, volumeGrams: 0, isNew: false)
        }

        var netReps = 0
        var netVolume = 0
        var allNew = true
        let byExercise = Dictionary(grouping: thisWorkout, by: \.exerciseID)
        for (exerciseID, sets) in byExercise {
            netReps += sets.reduce(0) { $0 + $1.reps }
            netVolume += sets.reduce(0) { $0 + $1.weightGrams * $1.reps }

            // Reference workout: the most recent prior workout containing this exercise.
            let priorSets = working.filter {
                $0.exerciseID == exerciseID && $0.workoutID != workoutID && $0.completedAt < workoutStart
            }
            guard let referenceID = priorSets.max(by: { $0.completedAt < $1.completedAt })?.workoutID else {
                continue
            }
            allNew = false
            let referenceSets = priorSets.filter { $0.workoutID == referenceID }
            netReps -= referenceSets.reduce(0) { $0 + $1.reps }
            netVolume -= referenceSets.reduce(0) { $0 + $1.weightGrams * $1.reps }
        }
        return NetSummary(reps: netReps, volumeGrams: netVolume, isNew: allNew)
    }

    // MARK: - Chart series

    /// Best e1RM per distinct workout session, chronological, for charts.
    /// The point date is the earliest set of the exercise in that session.
    public static func bestE1RMSeries(samples: [SetSample], exerciseID: UUID) -> [(date: Date, e1RMGrams: Int)] {
        let working = samples.filter { !$0.isWarmup && $0.exerciseID == exerciseID }
        let byWorkout = Dictionary(grouping: working, by: \.workoutID)
        return byWorkout.values
            .compactMap { sets -> (date: Date, e1RMGrams: Int)? in
                guard let date = sets.map(\.completedAt).min(),
                      let best = sets.map({ e1RMGrams(weightGrams: $0.weightGrams, reps: $0.reps) }).max()
                else { return nil }
                return (date: date, e1RMGrams: best)
            }
            .sorted { $0.date < $1.date }
    }

    /// Total volume (gram·reps) per bucket, chronological, last `count` buckets
    /// ending at the bucket containing `date`. Empty buckets appear as zero.
    public static func volumeSeries(samples: [SetSample], period: Period, endingAt date: Date,
                                    count: Int, calendar: Calendar) -> [(bucket: BucketKey, volumeGrams: Int)] {
        guard count > 0 else { return [] }

        var anchors: [Date] = []
        var cursor = date
        for _ in 0..<count {
            anchors.append(cursor)
            cursor = dateInPreviousBucket(of: cursor, period: period, calendar: calendar)
        }
        anchors.reverse()

        var totals: [BucketKey: Int] = [:]
        for sample in samples where !sample.isWarmup {
            let key = bucketKey(for: sample.completedAt, period: period, calendar: calendar)
            totals[key, default: 0] += sample.weightGrams * sample.reps
        }
        return anchors.map { anchor in
            let key = bucketKey(for: anchor, period: period, calendar: calendar)
            return (bucket: key, volumeGrams: totals[key] ?? 0)
        }
    }
}
