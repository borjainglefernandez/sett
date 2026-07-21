import Foundation

// MARK: - Weekly hard-set counting (the ONE source of truth)

/// Counts hard (non-warmup) working sets inside the ISO week containing `now`.
///
/// This is THE one way any surface counts weekly hard sets — the Home tiles,
/// the muscle zones, and the volume-landmarks card must ALL route through here
/// so they can never disagree about "sets this week". If a surface needs a
/// different slice, it filters the output of the same week window; it never
/// re-derives its own idea of "this week" or its own warmup rule.
///
/// Week semantics: the interval is the passed calendar's
/// `dateInterval(of: .weekOfYear, for: now)` (the app pins a Monday-first,
/// ISO-style calendar), treated as half-open `[start, end)` so a set completed
/// exactly at next Monday 00:00 counts in the NEW week, never in both.
public enum WeeklyHardSets {

    /// Total non-warmup sets completed in the ISO week containing `now`.
    public static func total(samples: [SetSample], calendar: Calendar, now: Date = .now) -> Int {
        var count = 0
        forEachHardSetThisWeek(samples: samples, calendar: calendar, now: now) { _ in count += 1 }
        return count
    }

    /// Non-warmup sets in the ISO week containing `now`, grouped by the muscle
    /// each sample was logged against. Untrained muscles are ABSENT, not 0 —
    /// callers rendering the full landmark grid default missing keys to zero.
    public static func byMuscle(samples: [SetSample], calendar: Calendar, now: Date = .now) -> [Muscle: Int] {
        var counts: [Muscle: Int] = [:]
        forEachHardSetThisWeek(samples: samples, calendar: calendar, now: now) { sample in
            counts[sample.muscle, default: 0] += 1
        }
        return counts
    }

    /// The single shared filter both entry points ride: non-warmup samples whose
    /// completion lands inside the calendar's week interval containing `now`.
    private static func forEachHardSetThisWeek(samples: [SetSample], calendar: Calendar,
                                               now: Date, _ body: (SetSample) -> Void) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return }
        for sample in samples
        where !sample.isWarmup && sample.completedAt >= week.start && sample.completedAt < week.end {
            body(sample)
        }
    }
}
