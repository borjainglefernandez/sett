import Foundation
import Testing
@testable import SettCore

// MARK: - Fixed clock & calendars (never Date.now)

private func isoMadrid() -> Calendar {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return cal
}

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
    c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
    return calendar.date(from: c)!
}

private func setSample(_ exerciseID: UUID, grams: Int, reps: Int, at completedAt: Date,
                       workoutID: UUID, muscle: Muscle = .chest,
                       warmup: Bool = false, casual: Bool = false) -> SetSample {
    SetSample(exerciseID: exerciseID, muscle: muscle, weightGrams: grams, reps: reps,
              isWarmup: warmup, completedAt: completedAt, workoutID: workoutID, isCasual: casual)
}

private let bench = UUID()

// MARK: - workoutNet on a casual workout

@Suite("Casual — workoutNet")
struct CasualWorkoutNetTests {
    let w0 = UUID()
    let casualW = UUID()
    let w2 = UUID()

    @Test("A casual workout has zero nets and isNew == false via workoutNet")
    func casualWorkoutHasNoNets() {
        let samples = [
            setSample(bench, grams: 100_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            setSample(bench, grams: 100_000, reps: 12, at: date(2026, 6, 15, 10, 0),
                      workoutID: casualW, casual: true)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: casualW)
        #expect(net.reps == 0)
        #expect(net.volumeGrams == 0)
        #expect(!net.isNew)
    }

    @Test("A casual workout between two normal ones is skipped as the reference")
    func casualSkippedAsReference() {
        let samples = [
            // Earliest NORMAL workout — the reference w2 should compare against.
            setSample(bench, grams: 100_000, reps: 10, at: date(2026, 6, 10, 10, 0), workoutID: w0),
            // A CASUAL workout in between with heavier volume — must NOT be the reference.
            setSample(bench, grams: 100_000, reps: 12, at: date(2026, 6, 15, 10, 0),
                      workoutID: casualW, casual: true),
            // Latest NORMAL workout.
            setSample(bench, grams: 100_000, reps: 11, at: date(2026, 6, 20, 10, 0), workoutID: w2)
        ]
        let net = ProgressEngine.workoutNet(samples: samples, workoutID: w2)
        // vs w0 (1,000,000 / 10 reps): +100,000 / +1. If casual were the reference it
        // would be -100,000 / -1.
        #expect(net.volumeGrams == 100_000)
        #expect(net.reps == 1)
        #expect(!net.isNew)
    }
}

// MARK: - netSummary excludes casual from both buckets

@Suite("Casual — netSummary buckets")
struct CasualNetSummaryTests {
    let cal = isoMadrid()
    let prevW = UUID()
    let curW = UUID()

    @Test("Weekly netSummary excludes casual sets from both buckets")
    func casualExcludedFromBothBuckets() {
        let samples = [
            // Previous ISO week (of Jun 24): normal + casual bench.
            setSample(bench, grams: 100_000, reps: 10, at: date(2026, 6, 24), workoutID: prevW),
            setSample(bench, grams: 100_000, reps: 5, at: date(2026, 6, 24),
                      workoutID: prevW, casual: true),
            // Current ISO week (of Jul 1): normal + casual bench.
            setSample(bench, grams: 100_000, reps: 12, at: date(2026, 7, 1), workoutID: curW),
            setSample(bench, grams: 100_000, reps: 7, at: date(2026, 7, 1),
                      workoutID: curW, casual: true)
        ]
        let net = ProgressEngine.netSummary(samples: samples, exerciseID: bench, period: .week,
                                            containing: date(2026, 7, 2), calendar: cal)
        // Only the normal sets count: 12 - 10 reps, 1,200,000 - 1,000,000 volume.
        #expect(net.reps == 2)
        #expect(net.volumeGrams == 200_000)
        #expect(!net.isNew)
    }
}

// MARK: - Casual still counts for volume charts and PRs

@Suite("Casual — still counts for volume & PRs")
struct CasualStillCountsTests {

    @Test("Casual sets still appear in volumeSeries")
    func casualCountsInVolumeSeries() {
        let cal = isoMadrid()
        let wA = UUID()
        let samples = [
            setSample(bench, grams: 100_000, reps: 10, at: date(2026, 7, 1),
                      workoutID: wA, casual: true)
        ]
        let series = ProgressEngine.volumeSeries(samples: samples, period: .week,
                                                 endingAt: date(2026, 7, 2), count: 1, calendar: cal)
        #expect(series.count == 1)
        #expect(series[0].volumeGrams == 1_000_000)
    }

    @Test("Casual sets still produce a verified PR via ProgressionEngine")
    func casualProducesVerifiedPR() throws {
        let config = try ProgressionConfig.load()
        let cal = gregorianMondayMadrid()
        let benchID = UUID()

        var workouts: [WorkoutSample] = []
        var allSets: [SetSample] = []
        // Three prior distinct-day CASUAL sessions at 100 kg × 5 (e1RM 116,667 g).
        for day in 2...4 {
            let start = date(2025, 6, day, 18, 0, calendar: cal)
            let id = UUID()
            workouts.append(WorkoutSample(id: id, title: "Casual", startedAt: start,
                                          endedAt: start.addingTimeInterval(3600),
                                          bodyweightGrams: nil, routineID: nil, isCasual: true))
            for setIndex in 0..<3 {
                allSets.append(setSample(benchID, grams: 100_000, reps: 5,
                                         at: start.addingTimeInterval(Double(300 + setIndex * 300)),
                                         workoutID: id, casual: true))
            }
        }
        // Day 4: 110 kg × 5 -> e1RM 128,333 g (+10%, below the 15% provisional gate)
        // and priorDistinctDays == 3 -> a directly verified PR.
        let prStart = date(2025, 6, 5, 18, 0, calendar: cal)
        let prID = UUID()
        workouts.append(WorkoutSample(id: prID, title: "Casual", startedAt: prStart,
                                      endedAt: prStart.addingTimeInterval(3600),
                                      bodyweightGrams: nil, routineID: nil, isCasual: true))
        for setIndex in 0..<3 {
            allSets.append(setSample(benchID, grams: 110_000, reps: 5,
                                     at: prStart.addingTimeInterval(Double(300 + setIndex * 300)),
                                     workoutID: prID, casual: true))
        }

        let payload = ProgressionInput(sets: allSets, workouts: workouts, sleep: [], goals: [],
                                       previousPeakPL: 0,
                                       firstWorkoutDate: workouts.map(\.startedAt).min())
        let snapshot = ProgressionEngine.compute(input: payload, config: config,
                                                  calendar: cal, asOf: date(2025, 6, 5, 20, 0, calendar: cal))
        // Casual training still earns the new_ceiling PR badge and a non-zero PL.
        #expect(snapshot.badges.contains { $0.key == "new_ceiling" })
        #expect(snapshot.powerLevel > 0)
    }
}

// MARK: - Commentary

@Suite("Casual — commentary")
struct CasualCommentaryTests {

    @Test("Casual facts yield a terse, number-free Vego line, chosen deterministically")
    func casualCommentary() {
        let facts = CommentaryFacts(title: "Evening", netReps: 4, netVolumeGrams: 999,
                                    netIsNew: false, newBadgeCount: 2, powerLevelDelta: 5,
                                    isCasual: true)
        let (text, source) = CommentaryFallback.generate(facts: facts)
        #expect(source == .fallbackTemplate)
        #expect(CommentaryFallback.casualLines.contains(text))
        // No digits anywhere in a casual line.
        #expect(!text.contains { $0.isNumber })
        // Deterministic: index = (netReps + powerLevelDelta) mod count = (4 + 5) mod 3 = 0.
        #expect(text == CommentaryFallback.casualLines[0])
    }
}

// MARK: - Commentary persona routing

@Suite("Commentary — persona routing")
struct CommentaryPersonaTests {

    @Test("Default persona is Vego and preserves the classic line, unchanged")
    func defaultsToVego() {
        // 45,360 g ≈ 100 lb; only the volume line fires (no PL, no badges).
        let facts = CommentaryFacts(title: "Push", netReps: 3, netVolumeGrams: 45_360,
                                    netIsNew: false, newBadgeCount: 0, powerLevelDelta: 0)
        let (text, source) = CommentaryFallback.generate(facts: facts)
        #expect(source == .fallbackTemplate)
        #expect(text == "+100 lb over last time. Adequate.")
    }

    @Test("Barok speaks in mass on a tonnage-up day and never quotes a figure")
    func barokVoice() {
        let facts = CommentaryFacts(title: "Legs", netReps: 6, netVolumeGrams: 90_000,
                                    netIsNew: false, newBadgeCount: 1, powerLevelDelta: 3,
                                    persona: .barok)
        let (text, _) = CommentaryFallback.generate(facts: facts)
        #expect(text.contains("mountain"))
        #expect(!text.contains { $0.isNumber })
    }

    @Test("Zyn's comeback voice differs from Vego for the same facts")
    func zynVoiceIsDistinct() {
        let base = CommentaryFacts(title: "Back", netReps: 2, netVolumeGrams: 30_000,
                                   netIsNew: false, newBadgeCount: 0, powerLevelDelta: 0)
        let zyn = CommentaryFacts(title: "Back", netReps: 2, netVolumeGrams: 30_000,
                                  netIsNew: false, newBadgeCount: 0, powerLevelDelta: 0,
                                  persona: .zyn)
        let (vegoText, _) = CommentaryFallback.generate(facts: base)
        let (zynText, _) = CommentaryFallback.generate(facts: zyn)
        #expect(vegoText != zynText)
        #expect(zynText.contains("..."))   // shy fragments
    }

    @Test("A cut dip is never shamed, whoever is speaking")
    func cutDipNeverShamed() {
        let shaming = ["failure", "failed", "lost", "weak", "pathetic", "complacen"]
        for persona in CharacterKey.allCases {
            let facts = CommentaryFacts(title: "Cut day", netReps: -2, netVolumeGrams: -20_000,
                                        netIsNew: false, newBadgeCount: 0, powerLevelDelta: 0,
                                        phase: .cutting, persona: persona)
            let (text, _) = CommentaryFallback.generate(facts: facts)
            #expect(!text.isEmpty)
            let lowered = text.lowercased()
            #expect(!shaming.contains { lowered.contains($0) })
        }
    }

    @Test("Casual stays a number-free Vego line even when a patron is routed")
    func casualIgnoresPersona() {
        let facts = CommentaryFacts(title: "Evening", netReps: 4, netVolumeGrams: 999,
                                    netIsNew: false, newBadgeCount: 2, powerLevelDelta: 5,
                                    isCasual: true, persona: .zyn)
        let (text, _) = CommentaryFallback.generate(facts: facts)
        #expect(CommentaryFallback.casualLines.contains(text))
        #expect(!text.contains { $0.isNumber })
    }
}
