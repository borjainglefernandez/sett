import Foundation
import Testing
@testable import SettCore

// MARK: - Fixed test clock & calendar helpers (never Date.now)

/// ISO-8601 calendar (Monday-first, ISO week numbering) pinned to Madrid.
private func isoMadrid() -> Calendar {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return cal
}

/// Gregorian calendar configured like the app default: firstWeekday = 2 (Monday),
/// ISO-style minimum days in first week, pinned to Madrid.
private func gregorianMondayMadrid() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
    cal.firstWeekday = 2
    cal.minimumDaysInFirstWeek = 4
    return cal
}

private func date(_ year: Int, _ month: Int, _ day: Int,
                  _ hour: Int = 12, _ minute: Int = 0,
                  calendar: Calendar = isoMadrid()) -> Date {
    var c = DateComponents()
    c.year = year
    c.month = month
    c.day = day
    c.hour = hour
    c.minute = minute
    return calendar.date(from: c)!
}

private func sample(_ exerciseID: UUID, weightGrams: Int, reps: Int, at completedAt: Date,
                    workoutID: UUID, warmup: Bool = false) -> SetSample {
    SetSample(exerciseID: exerciseID, muscle: .chest, weightGrams: weightGrams, reps: reps,
              isWarmup: warmup, completedAt: completedAt, workoutID: workoutID)
}

private let bench = UUID()
private let squat = UUID()
private let curl = UUID()

// MARK: - e1RM

@Suite("ProgressEngine.e1RMGrams")
struct E1RMTests {

    @Test("Epley formula at moderate reps")
    func moderateReps() {
        // 100 kg x 10 -> 100000 * (1 + 10/30) = 133333.33 -> 133333
        #expect(ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 10) == 133_333)
    }

    @Test("Reps cap at 12: 50 reps == 12 reps")
    func repCap() {
        let at12 = ProgressEngine.e1RMGrams(weightGrams: 80_000, reps: 12)
        let at50 = ProgressEngine.e1RMGrams(weightGrams: 80_000, reps: 50)
        #expect(at12 == at50)
        #expect(at12 == 112_000) // 80000 * 1.4
    }

    @Test("Cap boundary: 13 reps == 12 reps, 11 reps < 12 reps")
    func capBoundary() {
        #expect(ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 13)
                == ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 12))
        #expect(ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 11)
                < ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 12))
    }

    @Test("Single rep uses the plain Epley term")
    func singleRep() {
        // 100000 * (1 + 1/30) = 103333.33 -> 103333
        #expect(ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 1) == 103_333)
    }

    @Test("Rounding is to the nearest gram")
    func rounding() {
        // 100001 * (1 + 1/30) = 103334.366... -> 103334
        #expect(ProgressEngine.e1RMGrams(weightGrams: 100_001, reps: 1) == 103_334)
    }

    @Test("Zero and negative reps clamp to the bare weight")
    func degenerateReps() {
        #expect(ProgressEngine.e1RMGrams(weightGrams: 50_000, reps: 0) == 50_000)
        #expect(ProgressEngine.e1RMGrams(weightGrams: 50_000, reps: -3) == 50_000)
    }
}

// MARK: - Bucket keys

@Suite("ProgressEngine.bucketKey")
struct BucketKeyTests {
    let cal = isoMadrid()

    @Test("Sunday 23:59 and Monday 00:00 land in adjacent ISO weeks (firstWeekday=2)")
    func sundayMondayBoundary() {
        let greg = gregorianMondayMadrid()
        // 2026-06-28 is a Sunday, 2026-06-29 a Monday.
        let sunday = date(2026, 6, 28, 23, 59, calendar: greg)
        let monday = date(2026, 6, 29, 0, 0, calendar: greg)
        let sundayKey = ProgressEngine.bucketKey(for: sunday, period: .week, calendar: greg)
        let mondayKey = ProgressEngine.bucketKey(for: monday, period: .week, calendar: greg)
        #expect(sundayKey.ordinal == 202626)
        #expect(mondayKey.ordinal == 202627)
        #expect(sundayKey < mondayKey)
    }

    @Test("ISO week 53 year rollover: Dec 31 2020 is week 53 of 2020, Jan 4 2021 is week 1 of 2021")
    func week53Rollover() {
        let inWeek53 = date(2020, 12, 31)
        let inWeek1 = date(2021, 1, 4)
        #expect(ProgressEngine.bucketKey(for: inWeek53, period: .week, calendar: cal).ordinal == 202053)
        #expect(ProgressEngine.bucketKey(for: inWeek1, period: .week, calendar: cal).ordinal == 202101)
    }

    @Test("Early January can belong to the previous ISO week-year")
    func januaryBelongsToPreviousWeekYear() {
        // 2021-01-01 (Friday) is still ISO week 53 of 2020.
        let jan1 = date(2021, 1, 1)
        #expect(ProgressEngine.bucketKey(for: jan1, period: .week, calendar: cal).ordinal == 202053)
        // ...while its month/year keys use the plain calendar year.
        #expect(ProgressEngine.bucketKey(for: jan1, period: .month, calendar: cal).ordinal == 202101)
        #expect(ProgressEngine.bucketKey(for: jan1, period: .year, calendar: cal).ordinal == 2021)
    }

    @Test("Month and year ordinals")
    func monthAndYear() {
        let d = date(2026, 3, 15)
        #expect(ProgressEngine.bucketKey(for: d, period: .month, calendar: cal).ordinal == 202603)
        #expect(ProgressEngine.bucketKey(for: d, period: .year, calendar: cal).ordinal == 2026)
    }

    @Test("DST spring-forward day stays in its week bucket")
    func dstTransition() {
        // Madrid springs forward 02:00 -> 03:00 on Sunday 2026-03-29.
        let saturday = date(2026, 3, 28, 22, 0)
        let dstSundayEvening = date(2026, 3, 29, 22, 0)
        let mondayAfter = date(2026, 3, 30, 0, 0)
        let satKey = ProgressEngine.bucketKey(for: saturday, period: .week, calendar: cal)
        let sunKey = ProgressEngine.bucketKey(for: dstSundayEvening, period: .week, calendar: cal)
        let monKey = ProgressEngine.bucketKey(for: mondayAfter, period: .week, calendar: cal)
        #expect(satKey == sunKey)
        #expect(monKey.ordinal == sunKey.ordinal + 1)
    }
}

// MARK: - Net summaries

@Suite("ProgressEngine.netSummary")
struct NetSummaryTests {
    let cal = isoMadrid()
    let workoutA = UUID()
    let workoutB = UUID()

    @Test("Positive week-over-week net")
    func positiveNet() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 24), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 7, 1), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(net.reps == 2)
        #expect(net.volumeGrams == 200_000)
        #expect(!net.isNew)
    }

    @Test("Negative nets are reported honestly")
    func negativeNet() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 6, 24), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 8, at: date(2026, 7, 1), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(net.reps == -4)
        #expect(net.volumeGrams == -400_000)
        #expect(!net.isNew)
    }

    @Test("Empty current bucket with a non-empty previous one is a full negative net, not NEW")
    func emptyCurrentBucket() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 24), workoutID: workoutA)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(net.reps == -10)
        #expect(net.volumeGrams == -1_000_000)
        #expect(!net.isNew)
    }

    @Test("Empty previous bucket => isNew, even when older history exists")
    func isNewWhenPreviousEmpty() {
        let samples = [
            // Two weeks before the current one — NOT the immediately preceding bucket.
            sample(bench, weightGrams: 90_000, reps: 10, at: date(2026, 6, 17), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 7, 1), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(net.isNew)
        #expect(net.reps == 10)
        #expect(net.volumeGrams == 1_000_000)
    }

    @Test("Both buckets empty => zero net, not NEW")
    func bothEmpty() {
        let samples = [
            sample(bench, weightGrams: 90_000, reps: 10, at: date(2026, 1, 7), workoutID: workoutA)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(net.reps == 0)
        #expect(net.volumeGrams == 0)
        #expect(!net.isNew)
    }

    @Test("Sunday 23:59 set belongs to the previous bucket of a Monday date")
    func strictSundayMondayBoundary() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 28, 23, 59), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 11, at: date(2026, 6, 29, 0, 0), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 6, 29, 0, 0), calendar: cal)
        #expect(net.reps == 1)
        #expect(net.volumeGrams == 100_000)
        #expect(!net.isNew)
    }

    @Test("Week 53 rollover: previous bucket of week 1 2021 is week 53 2020")
    func week53PreviousBucket() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2020, 12, 30), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 13, at: date(2021, 1, 5), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2021, 1, 4), calendar: cal)
        #expect(net.reps == 3)
        #expect(net.volumeGrams == 300_000)
        #expect(!net.isNew)
    }

    @Test("Warmup sets are excluded from both buckets")
    func warmupsExcluded() {
        let samples = [
            sample(bench, weightGrams: 60_000, reps: 15, at: date(2026, 6, 24), workoutID: workoutA, warmup: true),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 24), workoutID: workoutA),
            sample(bench, weightGrams: 60_000, reps: 15, at: date(2026, 7, 1), workoutID: workoutB, warmup: true),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 7, 1), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(net.reps == 0)
        #expect(net.volumeGrams == 0)
    }

    @Test("A bucket with only warmups counts as empty for isNew")
    func warmupOnlyPreviousBucketIsEmpty() {
        let samples = [
            sample(bench, weightGrams: 60_000, reps: 15, at: date(2026, 6, 24), workoutID: workoutA, warmup: true),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 7, 1), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(net.isNew)
    }

    @Test("exerciseID nil aggregates all exercises; non-nil filters")
    func exerciseFilter() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 24), workoutID: workoutA),
            sample(squat, weightGrams: 140_000, reps: 5, at: date(2026, 6, 24), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 7, 1), workoutID: workoutB),
            sample(squat, weightGrams: 140_000, reps: 8, at: date(2026, 7, 1), workoutID: workoutB)
        ]
        let all = ProgressEngine.netSummary(samples: samples, exerciseID: nil, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        #expect(all.reps == 5) // +2 bench, +3 squat
        #expect(all.volumeGrams == 200_000 + 420_000)

        let squatOnly = ProgressEngine.netSummary(samples: samples, exerciseID: squat, period: .week,
                                                  containing: date(2026, 7, 2), calendar: cal)
        #expect(squatOnly.reps == 3)
        #expect(squatOnly.volumeGrams == 420_000)
    }

    @Test("Month period compares against the immediately preceding month")
    func monthPeriod() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 3, 31, 23, 59), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 14, at: date(2026, 4, 1, 0, 0), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .month,
                                            containing: date(2026, 4, 20), calendar: cal)
        #expect(net.reps == 4)
        #expect(!net.isNew)
    }

    @Test("Year period compares against the immediately preceding year")
    func yearPeriod() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2025, 12, 31, 23, 0), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 25, at: date(2026, 1, 1, 10, 0), workoutID: workoutB)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .year,
                                            containing: date(2026, 6, 15), calendar: cal)
        #expect(net.reps == 15)
        #expect(!net.isNew)
    }
}

// MARK: - Per-exercise nets

@Suite("ProgressEngine.perExerciseNets")
struct PerExerciseNetsTests {
    let cal = isoMadrid()
    let workoutA = UUID()
    let workoutB = UUID()

    @Test("Covers exercises in either bucket, with correct isNew per exercise")
    func mixedExercises() {
        let samples = [
            // bench: both weeks.
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 24), workoutID: workoutA),
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 7, 1), workoutID: workoutB),
            // squat: previous week only -> honest negative, not new.
            sample(squat, weightGrams: 140_000, reps: 5, at: date(2026, 6, 24), workoutID: workoutA),
            // curl: current week only -> NEW.
            sample(curl, weightGrams: 15_000, reps: 12, at: date(2026, 7, 1), workoutID: workoutB),
        ]
        let nets = ProgressEngine.perExerciseNets(samples: samples, period: .week,
                                                  containing: date(2026, 7, 2), calendar: cal)
        #expect(nets.count == 3)
        #expect(nets[bench]?.reps == 2)
        #expect(nets[bench]?.isNew == false)
        #expect(nets[squat]?.reps == -5)
        #expect(nets[squat]?.volumeGrams == -700_000)
        #expect(nets[squat]?.isNew == false)
        #expect(nets[curl]?.reps == 12)
        #expect(nets[curl]?.isNew == true)
    }

    @Test("Exercises outside both buckets are omitted")
    func outsideBucketsOmitted() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 1, 7), workoutID: workoutA),
            sample(squat, weightGrams: 140_000, reps: 5, at: date(2026, 7, 1), workoutID: workoutB)
        ]
        let nets = ProgressEngine.perExerciseNets(samples: samples, period: .week,
                                                  containing: date(2026, 7, 2), calendar: cal)
        #expect(nets.count == 1)
        #expect(nets[squat] != nil)
        #expect(nets[bench] == nil)
    }
}

// MARK: - Workout-level rollup

@Suite("ProgressEngine.workoutNet")
struct WorkoutNetTests {
    let w0 = UUID()
    let w1 = UUID()
    let w2 = UUID()

    @Test("Net against each exercise's most recent prior workout containing it")
    func referenceRollup() {
        let samples = [
            // w0: bench only.
            sample(bench, weightGrams: 95_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            // w1: squat only — must NOT be bench's reference.
            sample(squat, weightGrams: 140_000, reps: 5, at: date(2026, 6, 15, 10, 0), workoutID: w1),
            // w2: bench + squat.
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 20, 10, 0), workoutID: w2),
            sample(squat, weightGrams: 140_000, reps: 6, at: date(2026, 6, 20, 10, 20), workoutID: w2)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w2)
        // bench: 1_000_000 - 950_000 = +50_000; squat: 840_000 - 700_000 = +140_000.
        #expect(net.volumeGrams == 190_000)
        #expect(net.reps == 1) // bench 10-10, squat 6-5
        #expect(!net.isNew)
    }

    @Test("Exercise with no prior session contributes bonus volume; isNew stays false when others have history")
    func partialNewExercise() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 20, 10, 0), workoutID: w1),
            sample(curl, weightGrams: 15_000, reps: 12, at: date(2026, 6, 20, 10, 30), workoutID: w1)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w1)
        #expect(net.reps == 12)              // bench flat, curl all bonus
        #expect(net.volumeGrams == 180_000)  // curl 15_000 * 12
        #expect(!net.isNew)
    }

    @Test("isNew only when ALL exercises lack a prior session")
    func allNew() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 20, 10, 0), workoutID: w1),
            sample(curl, weightGrams: 15_000, reps: 12, at: date(2026, 6, 20, 10, 30), workoutID: w1)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w1)
        #expect(net.isNew)
        #expect(net.reps == 22)
        #expect(net.volumeGrams == 1_000_000 + 180_000)
    }

    @Test("Reference is the most recent prior workout, not an older one")
    func mostRecentReferenceWins() {
        let samples = [
            sample(bench, weightGrams: 80_000, reps: 10, at: date(2026, 6, 1, 10, 0), workoutID: w0),
            sample(bench, weightGrams: 95_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w1),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 20, 10, 0), workoutID: w2)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w2)
        #expect(net.volumeGrams == 50_000) // vs w1 (950_000), not w0 (800_000)
    }

    @Test("Later workouts never leak into the reference")
    func laterWorkoutsIgnored() {
        let samples = [
            sample(bench, weightGrams: 95_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 15, 10, 0), workoutID: w1),
            sample(bench, weightGrams: 120_000, reps: 10, at: date(2026, 6, 20, 10, 0), workoutID: w2)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w1)
        #expect(net.volumeGrams == 50_000) // vs w0, ignoring the future w2
    }

    @Test("Warmups excluded on both sides")
    func warmupsExcluded() {
        let samples = [
            sample(bench, weightGrams: 60_000, reps: 15, at: date(2026, 6, 10, 9, 55), workoutID: w0, warmup: true),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            sample(bench, weightGrams: 60_000, reps: 15, at: date(2026, 6, 20, 9, 55), workoutID: w1, warmup: true),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 20, 10, 0), workoutID: w1)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w1)
        #expect(net.reps == 0)
        #expect(net.volumeGrams == 0)
    }

    @Test("Workout with no working sets yields a zero, non-new summary")
    func emptyWorkout() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w1)
        #expect(net.reps == 0)
        #expect(net.volumeGrams == 0)
        #expect(!net.isNew)
    }

    @Test("Regression net is honest (fewer reps than reference)")
    func negativeWorkoutNet() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            sample(bench, weightGrams: 100_000, reps: 8, at: date(2026, 6, 20, 10, 0), workoutID: w1)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w1)
        #expect(net.reps == -4)
        #expect(net.volumeGrams == -400_000)
        #expect(!net.isNew)
    }
}

// MARK: - Chart series

@Suite("ProgressEngine chart series")
struct SeriesTests {
    let cal = isoMadrid()
    let w0 = UUID()
    let w1 = UUID()
    let w2 = UUID()

    @Test("bestE1RMSeries: one point per workout, best set, chronological")
    func bestE1RMSeries() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 5, at: date(2026, 6, 20, 10, 0), workoutID: w1),
            sample(bench, weightGrams: 100_000, reps: 8, at: date(2026, 6, 20, 10, 10), workoutID: w1),
            sample(bench, weightGrams: 95_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            sample(squat, weightGrams: 200_000, reps: 5, at: date(2026, 6, 10, 11, 0), workoutID: w0)
        ]
        let series = ProgressEngine.bestE1RMSeries(samples: samples, exerciseID: bench)
        #expect(series.count == 2)
        #expect(series[0].date < series[1].date)
        #expect(series[0].e1RMGrams == ProgressEngine.e1RMGrams(weightGrams: 95_000, reps: 10))
        #expect(series[1].e1RMGrams == ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 8))
    }

    @Test("bestE1RMSeries ignores warmups and other exercises")
    func bestE1RMSeriesFilters() {
        let samples = [
            sample(bench, weightGrams: 300_000, reps: 1, at: date(2026, 6, 10, 9, 55), workoutID: w0, warmup: true),
            sample(bench, weightGrams: 100_000, reps: 5, at: date(2026, 6, 10, 10, 0), workoutID: w0)
        ]
        let series = ProgressEngine.bestE1RMSeries(samples: samples, exerciseID: bench)
        #expect(series.count == 1)
        #expect(series[0].e1RMGrams == ProgressEngine.e1RMGrams(weightGrams: 100_000, reps: 5))
        #expect(ProgressEngine.bestE1RMSeries(samples: samples, exerciseID: squat).isEmpty)
    }

    @Test("volumeSeries: last N weekly buckets, zeros for empty weeks, chronological")
    func weeklyVolumeSeries() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 17), workoutID: w0), // week 25
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 7, 1), workoutID: w2)   // week 27
        ]
        let series = ProgressEngine.volumeSeries(samples: samples, period: .week,
                                                 endingAt: date(2026, 7, 2), count: 3, calendar: cal)
        #expect(series.count == 3)
        #expect(series.map(\.bucket.ordinal) == [202625, 202626, 202627])
        #expect(series.map(\.volumeGrams) == [1_000_000, 0, 1_200_000])
    }

    @Test("volumeSeries spans the ISO week-53 year rollover")
    func volumeSeriesWeek53() {
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2020, 12, 30), workoutID: w0), // 202053
            sample(bench, weightGrams: 100_000, reps: 11, at: date(2021, 1, 5), workoutID: w1)    // 202101
        ]
        let series = ProgressEngine.volumeSeries(samples: samples, period: .week,
                                                 endingAt: date(2021, 1, 5), count: 2, calendar: cal)
        #expect(series.map(\.bucket.ordinal) == [202053, 202101])
        #expect(series.map(\.volumeGrams) == [1_000_000, 1_100_000])
    }

    @Test("volumeSeries walks correctly across the DST transition week")
    func volumeSeriesDST() {
        // Madrid DST: 2026-03-29 02:00 -> 03:00. Week 13 = Mar 23-29, week 14 = Mar 30-Apr 5.
        let samples = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 3, 28, 18, 0), workoutID: w0),
            sample(bench, weightGrams: 100_000, reps: 5, at: date(2026, 3, 29, 22, 0), workoutID: w1),
            sample(bench, weightGrams: 100_000, reps: 8, at: date(2026, 3, 30, 10, 0), workoutID: w2)
        ]
        let series = ProgressEngine.volumeSeries(samples: samples, period: .week,
                                                 endingAt: date(2026, 3, 30, 12, 0), count: 2, calendar: cal)
        #expect(series.map(\.bucket.ordinal) == [202613, 202614])
        #expect(series.map(\.volumeGrams) == [1_500_000, 800_000])
    }

    @Test("volumeSeries monthly buckets and warmup exclusion")
    func monthlyVolumeSeries() {
        let samples = [
            sample(bench, weightGrams: 60_000, reps: 15, at: date(2026, 5, 10), workoutID: w0, warmup: true),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 5, 10), workoutID: w0),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 10), workoutID: w1)
        ]
        let series = ProgressEngine.volumeSeries(samples: samples, period: .month,
                                                 endingAt: date(2026, 6, 15), count: 3, calendar: cal)
        #expect(series.map(\.bucket.ordinal) == [202604, 202605, 202606])
        #expect(series.map(\.volumeGrams) == [0, 1_000_000, 1_000_000])
    }

    @Test("volumeSeries with non-positive count is empty")
    func nonPositiveCount() {
        #expect(ProgressEngine.volumeSeries(samples: [], period: .week,
                                            endingAt: date(2026, 7, 2), count: 0, calendar: cal).isEmpty)
        #expect(ProgressEngine.volumeSeries(samples: [], period: .week,
                                            endingAt: date(2026, 7, 2), count: -3, calendar: cal).isEmpty)
    }
}

// MARK: - Streaks

@Suite("StreakEngine.streakWeeks")
struct StreakEngineTests {
    let cal = isoMadrid()

    /// Two distinct workout days in the ISO week starting on the given Monday.
    private func twoDays(weekOfMonday monday: (Int, Int, Int)) -> [Date] {
        [date(monday.0, monday.1, monday.2, 18, 0),
         dateShifted(monday, byDays: 3)]
    }

    private func dateShifted(_ ymd: (Int, Int, Int), byDays days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: date(ymd.0, ymd.1, ymd.2, 18, 0))!
    }

    @Test("Completed qualifying weeks count; empty in-progress week never breaks")
    func completedWeeksNotBrokenByCurrentWeek() {
        // Weeks of Jun 8, Jun 15, Jun 22 each have 2 distinct days. asOf Tue Jun 30 (week of Jun 29), 0 days so far.
        let dates = twoDays(weekOfMonday: (2026, 6, 8))
            + twoDays(weekOfMonday: (2026, 6, 15))
            + twoDays(weekOfMonday: (2026, 6, 22))
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2026, 6, 30, 9, 0))
        #expect(streak == 3)
    }

    @Test("In-progress week extends the streak once it qualifies")
    func inProgressWeekExtends() {
        let dates = twoDays(weekOfMonday: (2026, 6, 8))
            + twoDays(weekOfMonday: (2026, 6, 15))
            + twoDays(weekOfMonday: (2026, 6, 22))
            + twoDays(weekOfMonday: (2026, 6, 29)) // current week qualifies too
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2026, 7, 3, 9, 0))
        #expect(streak == 4)
    }

    @Test("A completed week below the threshold breaks the run")
    func brokenStreak() {
        let dates = twoDays(weekOfMonday: (2026, 6, 8))
            + [date(2026, 6, 17, 18, 0)] // week of Jun 15: only 1 day
            + twoDays(weekOfMonday: (2026, 6, 22))
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2026, 6, 30, 9, 0))
        #expect(streak == 1) // only the week of Jun 22 survives
    }

    @Test("Two workouts on the same calendar day count as one day")
    func sameDayCollapses() {
        let dates = [date(2026, 6, 23, 8, 0), date(2026, 6, 23, 19, 0)]
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2026, 6, 30, 9, 0))
        #expect(streak == 0)
    }

    @Test("Qualifying in-progress week with no completed history counts as 1")
    func onlyCurrentWeekQualifies() {
        let dates = twoDays(weekOfMonday: (2026, 6, 29))
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2026, 7, 3, 9, 0))
        #expect(streak == 1)
    }

    @Test("No workouts => zero")
    func emptyDates() {
        #expect(StreakEngine.streakWeeks(workoutDates: [], minDaysPerWeek: 2,
                                         calendar: cal, asOf: date(2026, 6, 30)) == 0)
    }

    @Test("Streak survives the ISO week-53 year rollover")
    func week53Rollover() {
        // Week 53 of 2020: Mon Dec 28 2020 - Sun Jan 3 2021. Week 1 of 2021: Mon Jan 4.
        let dates = twoDays(weekOfMonday: (2020, 12, 21))  // week 52
            + twoDays(weekOfMonday: (2020, 12, 28))        // week 53
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2021, 1, 5, 9, 0))
        #expect(streak == 2)
    }

    @Test("Week containing the DST transition still counts its distinct days")
    func dstWeek() {
        // Madrid springs forward on Sunday 2026-03-29.
        let dates = [date(2026, 3, 28, 18, 0), date(2026, 3, 29, 22, 0)] // Sat + DST Sunday, same week
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2026, 3, 31, 9, 0))
        #expect(streak == 1)
    }

    @Test("Sunday 23:59 workout stays in the closing week, Monday 00:00 in the next")
    func weekBoundaryAttribution() {
        // Week of Jun 22: Tue Jun 23 + Sun Jun 28 23:59 -> 2 distinct days.
        let dates = [date(2026, 6, 23, 18, 0), date(2026, 6, 28, 23, 59), date(2026, 6, 29, 0, 0)]
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 2,
                                              calendar: cal, asOf: date(2026, 6, 30, 9, 0))
        // Completed week of Jun 22 qualifies (2 days); current week has 1 day -> no extension.
        #expect(streak == 1)
    }

    @Test("minDaysPerWeek below 1 is clamped, not infinite")
    func degenerateThreshold() {
        let dates = twoDays(weekOfMonday: (2026, 6, 22))
        let streak = StreakEngine.streakWeeks(workoutDates: dates, minDaysPerWeek: 0,
                                              calendar: cal, asOf: date(2026, 6, 30, 9, 0))
        #expect(streak == 1)
    }
}

// MARK: - Shielded streak (streakState)

@Suite("StreakEngine.streakState — shields & targets")
struct StreakStateTests {
    let cal = isoMadrid()

    private func twoDays(weekOfMonday monday: (Int, Int, Int)) -> [Date] {
        [date(monday.0, monday.1, monday.2, 18, 0),
         cal.date(byAdding: .day, value: 3, to: date(monday.0, monday.1, monday.2, 18, 0))!]
    }

    /// Mondays of N consecutive ISO weeks starting at the given one.
    private func mondays(from start: (Int, Int, Int), count: Int) -> [(Int, Int, Int)] {
        (0..<count).map { i in
            let d = cal.date(byAdding: .day, value: 7 * i, to: date(start.0, start.1, start.2, 12, 0))!
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return (c.year!, c.month!, c.day!)
        }
    }

    @Test("Four straight passing weeks bank a shield")
    func shieldEarned() {
        let dates = mondays(from: (2026, 5, 4), count: 4).flatMap { twoDays(weekOfMonday: $0) }
        let state = StreakEngine.streakState(workoutDates: dates, weeklyTarget: 2,
                                             calendar: cal, asOf: date(2026, 6, 2, 9, 0))
        #expect(state.weeks == 4)
        #expect(state.shields == 1)
        #expect(state.weeksToNextShield == 4)
    }

    @Test("A missed week spends the shield and the streak survives")
    func shieldAbsorbsMiss() {
        // 4 passing weeks (bank a shield), one fully empty vacation week, then 1 passing week.
        var dates = mondays(from: (2026, 5, 4), count: 4).flatMap { twoDays(weekOfMonday: $0) }
        dates += twoDays(weekOfMonday: (2026, 6, 8))   // week of Jun 1 skipped entirely
        let state = StreakEngine.streakState(workoutDates: dates, weeklyTarget: 2,
                                             calendar: cal, asOf: date(2026, 6, 16, 9, 0))
        #expect(state.weeks == 5)      // 4 + survived miss + 1
        #expect(state.shields == 0)    // spent
    }

    @Test("A missed week with no shield resets to zero")
    func noShieldResets() {
        // Only 2 passing weeks (no shield yet), then an empty week, then 1 passing week.
        var dates = mondays(from: (2026, 5, 18), count: 2).flatMap { twoDays(weekOfMonday: $0) }
        dates += twoDays(weekOfMonday: (2026, 6, 8))   // week of Jun 1 skipped
        let state = StreakEngine.streakState(workoutDates: dates, weeklyTarget: 2,
                                             calendar: cal, asOf: date(2026, 6, 16, 9, 0))
        #expect(state.weeks == 1)
        #expect(state.bestWeeks == 2)
    }

    @Test("Two banked shields survive a two-week vacation")
    func twoShieldsTwoWeeks() {
        // 8 passing weeks bank 2 shields; 2 empty weeks; 1 passing week.
        var dates = mondays(from: (2026, 3, 30), count: 8).flatMap { twoDays(weekOfMonday: $0) }
        dates += twoDays(weekOfMonday: (2026, 6, 8))   // weeks of May 25 + Jun 1 skipped
        let state = StreakEngine.streakState(workoutDates: dates, weeklyTarget: 2,
                                             calendar: cal, asOf: date(2026, 6, 16, 9, 0))
        #expect(state.weeks == 9)
        #expect(state.shields == 0)
    }

    @Test("Target-aware: a 3-day target fails a 2-day week")
    func targetAware() {
        let dates = twoDays(weekOfMonday: (2026, 6, 22))
        let state = StreakEngine.streakState(workoutDates: dates, weeklyTarget: 3,
                                             calendar: cal, asOf: date(2026, 6, 30, 9, 0))
        #expect(state.weeks == 0)
        #expect(state.daysThisWeek == 0)
        #expect(state.weeklyTarget == 3)
    }

    @Test("In-progress week extends and reports its day count")
    func inProgressExtends() {
        let dates = twoDays(weekOfMonday: (2026, 6, 22)) + twoDays(weekOfMonday: (2026, 6, 29))
        let state = StreakEngine.streakState(workoutDates: dates, weeklyTarget: 2,
                                             calendar: cal, asOf: date(2026, 7, 3, 9, 0))
        #expect(state.weeks == 2)
        #expect(state.extendedThisWeek)
        #expect(state.daysThisWeek == 2)
    }

    @Test("Empty history is a zeroed state")
    func emptyHistory() {
        let state = StreakEngine.streakState(workoutDates: [], weeklyTarget: 3,
                                             calendar: cal, asOf: date(2026, 6, 30))
        #expect(state.weeks == 0)
        #expect(state.shields == 0)
        #expect(!state.extendedThisWeek)
    }
}

// MARK: - Goals

@Suite("GoalEvaluator.progress")
struct GoalEvaluatorTests {
    let cal = isoMadrid()
    let w0 = UUID()
    let w1 = UUID()
    let w2 = UUID()

    private func goal(kind: GoalKind, target: Int, exerciseID: UUID? = nil,
                      start: Date, end: Date? = nil, completedAt: Date? = nil) -> GoalSample {
        GoalSample(id: UUID(), kind: kind, targetValue: target, exerciseID: exerciseID,
                   startDate: start, endDate: end, isActive: true,
                   completedAt: completedAt, createdAt: start)
    }

    private func workout(id: UUID, startedAt: Date) -> WorkoutSample {
        WorkoutSample(id: id, title: "Session", startedAt: startedAt,
                      endedAt: startedAt.addingTimeInterval(3600), bodyweightGrams: nil, routineID: nil)
    }

    // MARK: frequency

    @Test("frequency: distinct workout days in the current ISO week")
    func frequencyProgress() {
        let g = goal(kind: .frequency, target: 3, start: date(2026, 6, 1))
        let workouts = [
            workout(id: w0, startedAt: date(2026, 6, 29, 18, 0)),   // Mon, current week
            workout(id: w1, startedAt: date(2026, 7, 1, 8, 0)),     // Wed morning
            workout(id: w2, startedAt: date(2026, 7, 1, 19, 0)),    // Wed evening — same day
            workout(id: UUID(), startedAt: date(2026, 6, 25, 18, 0)) // previous week — excluded
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: [], workoutSamples: workouts,
                                              calendar: cal, asOf: date(2026, 7, 2, 12, 0))
        #expect(progress.currentValue == 2)
        #expect(progress.targetValue == 3)
        #expect(!progress.isComplete)
        #expect(abs(progress.fraction - 2.0 / 3.0) < 0.0001)
    }

    @Test("frequency: ring closes at the target")
    func frequencyComplete() {
        let g = goal(kind: .frequency, target: 3, start: date(2026, 6, 1))
        let workouts = [
            workout(id: w0, startedAt: date(2026, 6, 29, 18, 0)),
            workout(id: w1, startedAt: date(2026, 6, 30, 18, 0)),
            workout(id: w2, startedAt: date(2026, 7, 1, 18, 0))
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: [], workoutSamples: workouts,
                                              calendar: cal, asOf: date(2026, 7, 2, 12, 0))
        #expect(progress.currentValue == 3)
        #expect(progress.isComplete)
        #expect(progress.fraction == 1.0)
    }

    @Test("frequency: workouts before the goal start are excluded even inside the week")
    func frequencyRespectsStartDate() {
        let g = goal(kind: .frequency, target: 2, start: date(2026, 7, 1, 0, 0))
        let workouts = [
            workout(id: w0, startedAt: date(2026, 6, 29, 18, 0)), // same ISO week, before goal start
            workout(id: w1, startedAt: date(2026, 7, 1, 18, 0))
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: [], workoutSamples: workouts,
                                              calendar: cal, asOf: date(2026, 7, 2, 12, 0))
        #expect(progress.currentValue == 1)
        #expect(!progress.isComplete)
    }

    // MARK: pr_target

    @Test("prTarget: best capped-Epley e1RM inside the window vs target grams")
    func prTargetComplete() {
        // 100 kg x 12 -> e1RM 140_000 g, exactly the target.
        let g = goal(kind: .prTarget, target: 140_000, exerciseID: bench,
                     start: date(2026, 6, 1), end: date(2026, 7, 31))
        let sets = [
            sample(bench, weightGrams: 200_000, reps: 5, at: date(2026, 5, 20), workoutID: w0), // before start
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 6, 10), workoutID: w1)
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: sets, workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 7, 2))
        #expect(progress.currentValue == 140_000)
        #expect(progress.isComplete)
        #expect(progress.fraction == 1.0)
    }

    @Test("prTarget: partial progress fraction, warmups and other exercises excluded")
    func prTargetPartial() {
        let g = goal(kind: .prTarget, target: 150_000, exerciseID: bench,
                     start: date(2026, 6, 1), end: date(2026, 7, 31))
        let sets = [
            sample(bench, weightGrams: 300_000, reps: 1, at: date(2026, 6, 10), workoutID: w1, warmup: true),
            sample(squat, weightGrams: 300_000, reps: 5, at: date(2026, 6, 10), workoutID: w1),
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 6, 10), workoutID: w1)
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: sets, workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 7, 2))
        #expect(progress.currentValue == 140_000)
        #expect(!progress.isComplete)
        #expect(abs(progress.fraction - 140_000.0 / 150_000.0) < 0.0001)
    }

    @Test("prTarget: sets after the deadline do not count")
    func prTargetDeadline() {
        let g = goal(kind: .prTarget, target: 140_000, exerciseID: bench,
                     start: date(2026, 6, 1), end: date(2026, 6, 30))
        let sets = [
            sample(bench, weightGrams: 100_000, reps: 12, at: date(2026, 7, 1), workoutID: w1) // after deadline
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: sets, workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 7, 2))
        #expect(progress.currentValue == 0)
        #expect(!progress.isComplete)
        #expect(progress.fraction == 0.0)
    }

    // MARK: volume_target

    @Test("volumeTarget: tonnage accumulates across all exercises when exerciseID is nil")
    func volumeTargetAllExercises() {
        let g = goal(kind: .volumeTarget, target: 3_000_000,
                     start: date(2026, 6, 1), end: date(2026, 6, 30))
        let sets = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 10), workoutID: w0), // 1_000_000
            sample(squat, weightGrams: 100_000, reps: 5, at: date(2026, 6, 12), workoutID: w1),  // 500_000
            sample(bench, weightGrams: 60_000, reps: 15, at: date(2026, 6, 12), workoutID: w1, warmup: true)
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: sets, workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 6, 20))
        #expect(progress.currentValue == 1_500_000)
        #expect(!progress.isComplete)
        #expect(abs(progress.fraction - 0.5) < 0.0001)
    }

    @Test("volumeTarget: completes at the target, filtered to the goal's exercise")
    func volumeTargetComplete() {
        let g = goal(kind: .volumeTarget, target: 2_000_000, exerciseID: bench,
                     start: date(2026, 6, 1), end: date(2026, 6, 30))
        let sets = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 10), workoutID: w0),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 15), workoutID: w1),
            sample(squat, weightGrams: 200_000, reps: 10, at: date(2026, 6, 15), workoutID: w1) // ignored
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: sets, workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 6, 20))
        #expect(progress.currentValue == 2_000_000)
        #expect(progress.isComplete)
        #expect(progress.fraction == 1.0)
    }

    @Test("volumeTarget: window end is min(asOf, endDate)")
    func volumeTargetWindow() {
        let g = goal(kind: .volumeTarget, target: 2_000_000, exerciseID: bench,
                     start: date(2026, 6, 1), end: date(2026, 6, 15))
        let sets = [
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 10), workoutID: w0),
            sample(bench, weightGrams: 100_000, reps: 10, at: date(2026, 6, 20), workoutID: w1) // after endDate
        ]
        let progress = GoalEvaluator.progress(goal: g, setSamples: sets, workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 6, 25))
        #expect(progress.currentValue == 1_000_000)
        #expect(!progress.isComplete)
    }

    // MARK: shared semantics

    @Test("A goal already marked completed reports complete with a full ring")
    func completedAtWins() {
        let g = goal(kind: .volumeTarget, target: 5_000_000, exerciseID: bench,
                     start: date(2026, 6, 1), end: date(2026, 6, 30),
                     completedAt: date(2026, 6, 18))
        let progress = GoalEvaluator.progress(goal: g, setSamples: [], workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 6, 25))
        #expect(progress.isComplete)
        #expect(progress.fraction == 1.0)
    }

    @Test("Non-positive target is treated as complete instead of dividing by zero")
    func degenerateTarget() {
        let g = goal(kind: .volumeTarget, target: 0, start: date(2026, 6, 1))
        let progress = GoalEvaluator.progress(goal: g, setSamples: [], workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 6, 25))
        #expect(progress.isComplete)
        #expect(progress.fraction == 1.0)
    }

    @Test("GoalProgress carries the goal's id")
    func goalIDPassthrough() {
        let g = goal(kind: .frequency, target: 3, start: date(2026, 6, 1))
        let progress = GoalEvaluator.progress(goal: g, setSamples: [], workoutSamples: [],
                                              calendar: cal, asOf: date(2026, 7, 2))
        #expect(progress.goalID == g.id)
        #expect(progress.currentValue == 0)
        #expect(progress.fraction == 0.0)
    }
}
