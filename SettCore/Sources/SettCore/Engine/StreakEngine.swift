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
}
