import Foundation
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

// MARK: - Sample builder

private func sample(_ muscle: Muscle, at completedAt: Date, warmup: Bool = false) -> SetSample {
    SetSample(exerciseID: UUID(), muscle: muscle, weightGrams: 80_000, reps: 8,
              isWarmup: warmup, completedAt: completedAt, workoutID: UUID())
}

/// Three ISO weeks of sets around now = Wednesday 2025-06-11. Only the middle
/// week (Mon 9 June 00:00 … Sun 15 June, half-open at Mon 16 June 00:00) counts.
private func threeWeekFixture() -> [SetSample] {
    [
        // Week BEFORE (Mon 2 – Sun 8 June): must never count.
        sample(.chest, at: date(2025, 6, 3, 18)),
        sample(.chest, at: date(2025, 6, 3, 18, 10)),
        sample(.back, at: date(2025, 6, 5, 18)),

        // MIDDLE week — the one containing now. Edges included on purpose:
        // Monday 00:00 opens the week, Sunday 23:59 still belongs to it.
        sample(.chest, at: date(2025, 6, 9, 0, 0)),          // Monday 00:00 edge
        sample(.chest, at: date(2025, 6, 9, 18)),
        sample(.chest, at: date(2025, 6, 9, 18, 5)),
        sample(.chest, at: date(2025, 6, 9, 17, 55), warmup: true),   // excluded
        sample(.back, at: date(2025, 6, 10, 18)),
        sample(.back, at: date(2025, 6, 15, 23, 59)),        // Sunday 23:59 edge
        sample(.quadriceps, at: date(2025, 6, 12, 18)),
        sample(.quadriceps, at: date(2025, 6, 12, 18, 5)),
        sample(.quadriceps, at: date(2025, 6, 12, 17, 50), warmup: true), // excluded
        sample(.hamstrings, at: date(2025, 6, 12, 18, 15)),
        sample(.glutes, at: date(2025, 6, 13, 18)),
        sample(.calves, at: date(2025, 6, 13, 18, 10)),

        // Week AFTER: the very first instant of next Monday belongs to the NEW
        // week (half-open interval), plus a plainly later set.
        sample(.back, at: date(2025, 6, 16, 0, 0)),
        sample(.quadriceps, at: date(2025, 6, 17, 18)),
    ]
}

/// Wednesday evening inside the middle week.
private let now = date(2025, 6, 11, 20)

// MARK: - Tests

@Suite("WeeklyHardSets — the one weekly set counter")
struct WeeklyHardSetsTests {

    @Test("total: only the ISO week containing now counts, warmups excluded, edges honored")
    func totalCountsOnlyMiddleWeek() {
        let total = WeeklyHardSets.total(samples: threeWeekFixture(),
                                         calendar: madridCalendar(), now: now)
        // chest 3 + back 2 + quads 2 + hams 1 + glutes 1 + calves 1 = 10;
        // the 2 warmups and both neighbor weeks (incl. next-Monday 00:00) are out.
        #expect(total == 10)
    }

    @Test("byMuscle: groups by sample muscle incl. the split lower-body groups")
    func byMuscleGroupsCorrectly() {
        let counts = WeeklyHardSets.byMuscle(samples: threeWeekFixture(),
                                             calendar: madridCalendar(), now: now)
        #expect(counts == [
            .chest: 3,
            .back: 2,
            .quadriceps: 2,
            .hamstrings: 1,
            .glutes: 1,
            .calves: 1,
        ])
        // Untrained muscles are absent, not zero.
        #expect(counts[.biceps] == nil)
        // The two views can never disagree: byMuscle sums to total.
        #expect(counts.values.reduce(0, +) == WeeklyHardSets.total(
            samples: threeWeekFixture(), calendar: madridCalendar(), now: now))
    }

    @Test("now in a different week moves the window with it")
    func windowFollowsNow() {
        let priorWeekNow = date(2025, 6, 4, 20)   // Wednesday of the week BEFORE
        let counts = WeeklyHardSets.byMuscle(samples: threeWeekFixture(),
                                             calendar: madridCalendar(), now: priorWeekNow)
        #expect(counts == [.chest: 2, .back: 1])
    }

    @Test("Empty input -> zero total and empty grouping")
    func emptyInput() {
        #expect(WeeklyHardSets.total(samples: [], calendar: madridCalendar(), now: now) == 0)
        #expect(WeeklyHardSets.byMuscle(samples: [], calendar: madridCalendar(), now: now).isEmpty)
    }
}
