import Foundation

/// Weekly training-streak math (design-gamification §"Consistency Multiplier").
/// A week qualifies when it contains at least `minDaysPerWeek` distinct
/// workout days (local calendar days in the passed calendar's time zone).
public enum StreakEngine {

    /// Consecutive completed ISO weeks (before the week containing `asOf`)
    /// with >= `minDaysPerWeek` distinct workout days; the in-progress week
    /// extends the streak when it already qualifies but never breaks it.
    public static func streakWeeks(workoutDates: [Date], minDaysPerWeek: Int,
                                   calendar: Calendar, asOf: Date) -> Int {
        guard !workoutDates.isEmpty else { return 0 }
        let threshold = max(1, minDaysPerWeek)

        // Distinct workout days per week ordinal. Only weeks that actually
        // contain workouts get an entry, so the backwards walk below always
        // terminates at the first empty week.
        var daysPerWeek: [Int: Set<Int>] = [:]
        for date in workoutDates {
            let ordinal = ProgressEngine.bucketKey(for: date, period: .week, calendar: calendar).ordinal
            daysPerWeek[ordinal, default: []].insert(calendar.dateKey(for: date))
        }

        func qualifies(_ ordinal: Int) -> Bool {
            (daysPerWeek[ordinal]?.count ?? 0) >= threshold
        }

        func previousWeekDate(of date: Date) -> Date {
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            return start.addingTimeInterval(-1)
        }

        // Completed weeks: walk backwards from the week before asOf's week
        // until the first non-qualifying week.
        var streak = 0
        var cursor = previousWeekDate(of: asOf)
        while qualifies(ProgressEngine.bucketKey(for: cursor, period: .week, calendar: calendar).ordinal) {
            streak += 1
            cursor = previousWeekDate(of: cursor)
        }

        // The in-progress week can only extend, never break.
        let currentOrdinal = ProgressEngine.bucketKey(for: asOf, period: .week, calendar: calendar).ordinal
        if qualifies(currentOrdinal) { streak += 1 }
        return streak
    }

    // MARK: - Shielded, target-aware streak (the interactive home streak)

    /// Everything the streak UI needs in one pass.
    public struct StreakState: Equatable, Sendable {
        /// Current streak in weeks (includes the in-progress week once it qualifies).
        public let weeks: Int
        public let bestWeeks: Int
        /// Distinct training days required for a week to count.
        public let weeklyTarget: Int
        /// Distinct training days logged in the in-progress week.
        public let daysThisWeek: Int
        /// Shields banked — a missed week SPENDS one instead of breaking the streak.
        public let shields: Int
        public let shieldCap: Int
        /// Qualifying weeks still needed to bank the next shield (0 when at cap).
        public let weeksToNextShield: Int
        /// The in-progress week has already hit the target — streak extended.
        public let extendedThisWeek: Bool
    }

    /// Forgiving streak walk ("life happens" rule). Chronological over every week from
    /// the first workout to the week before `asOf`:
    ///  - a week PASSES with >= `weeklyTarget` distinct training days; every
    ///    `shieldEarnEvery` consecutive passes bank one shield (capped at `shieldCap`).
    ///  - a MISSED week (including fully empty vacation weeks) spends a shield and the
    ///    streak survives; with no shield banked the streak resets to zero.
    ///  - the in-progress week extends the streak once it qualifies, never breaks it.
    public static func streakState(workoutDates: [Date], weeklyTarget: Int,
                                   calendar: Calendar, asOf: Date,
                                   shieldEarnEvery: Int = 4,
                                   shieldCap: Int = 2) -> StreakState {
        let target = max(1, weeklyTarget)
        let currentOrdinal = ProgressEngine.bucketKey(for: asOf, period: .week, calendar: calendar).ordinal

        var daysPerWeek: [Int: Set<Int>] = [:]
        for date in workoutDates where date <= asOf {
            let ordinal = ProgressEngine.bucketKey(for: date, period: .week, calendar: calendar).ordinal
            daysPerWeek[ordinal, default: []].insert(calendar.dateKey(for: date))
        }
        let daysThisWeek = daysPerWeek[currentOrdinal]?.count ?? 0

        guard let firstDate = workoutDates.filter({ $0 <= asOf }).min() else {
            return StreakState(weeks: 0, bestWeeks: 0, weeklyTarget: target, daysThisWeek: 0,
                               shields: 0, shieldCap: shieldCap,
                               weeksToNextShield: shieldEarnEvery, extendedThisWeek: false)
        }

        // Chronological walk by real week starts — ordinals aren't consecutive across
        // year boundaries, so step dates (re-anchored per week for DST safety).
        var streak = 0, best = 0, shields = 0, earnProgress = 0
        var cursor = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start ?? firstDate
        let weekSeconds: TimeInterval = 7 * 24 * 3600
        while true {
            let ordinal = ProgressEngine.bucketKey(for: cursor, period: .week, calendar: calendar).ordinal
            if ordinal == currentOrdinal { break }   // in-progress week handled below
            if (daysPerWeek[ordinal]?.count ?? 0) >= target {
                streak += 1
                best = max(best, streak)
                earnProgress += 1
                if earnProgress >= shieldEarnEvery {
                    shields = min(shieldCap, shields + 1)
                    earnProgress = 0
                }
            } else if shields > 0 {
                shields -= 1        // the shield absorbs the miss; the streak survives
                earnProgress = 0
            } else {
                streak = 0
                earnProgress = 0
            }
            let next = cursor.addingTimeInterval(weekSeconds + 3600)   // overshoot DST
            cursor = calendar.dateInterval(of: .weekOfYear, for: next)?.start ?? next
        }

        let extended = daysThisWeek >= target
        if extended {
            streak += 1
            best = max(best, streak)
        }
        return StreakState(weeks: streak, bestWeeks: best, weeklyTarget: target,
                           daysThisWeek: daysThisWeek, shields: shields, shieldCap: shieldCap,
                           weeksToNextShield: shields >= shieldCap ? 0 : shieldEarnEvery - earnProgress,
                           extendedThisWeek: extended)
    }
}
