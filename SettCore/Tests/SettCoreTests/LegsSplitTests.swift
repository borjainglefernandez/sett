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

// MARK: - Sample builders

private let benchID = UUID()
private let squatID = UUID()
private let rdlID = UUID()

private func workout(_ id: UUID, start: Date, minutes: Int = 60,
                     title: String = "Workout") -> WorkoutSample {
    WorkoutSample(id: id, title: title, startedAt: start,
                  endedAt: start.addingTimeInterval(Double(minutes) * 60),
                  bodyweightGrams: nil, routineID: nil)
}

/// `count` identical working sets starting 5 minutes into the workout, 5 minutes apart.
private func sets(_ exerciseID: UUID, muscle: Muscle, grams: Int, reps: Int,
                  count: Int, workout: WorkoutSample, offset: Int = 0) -> [SetSample] {
    (0..<count).map { index in
        SetSample(exerciseID: exerciseID, muscle: muscle, weightGrams: grams, reps: reps,
                  isWarmup: false,
                  completedAt: workout.startedAt
                      .addingTimeInterval(Double(300 + (offset + index) * 300)),
                  workoutID: workout.id)
    }
}

private func input(workouts: [WorkoutSample], sets: [SetSample]) -> ProgressionInput {
    ProgressionInput(sets: sets, workouts: workouts, sleep: [], goals: [],
                     previousPeakPL: 0,
                     firstWorkoutDate: workouts.map(\.startedAt).min())
}

/// One lower-body + one chest session; the lower-body sets carry the given muscle
/// tags so the same physical history can be replayed as `.legs`, split, or mixed.
private func snapshot(squatMuscle: Muscle, rdlMuscle: Muscle,
                      config: ProgressionConfig) -> ProgressionSnapshot {
    let cal = madridCalendar()
    let wLegs = workout(UUID(), start: date(2025, 6, 2, 18))    // Monday
    let wPush = workout(UUID(), start: date(2025, 6, 4, 18))    // Wednesday
    let allSets = sets(squatID, muscle: squatMuscle, grams: 150_000, reps: 5, count: 4, workout: wLegs)
        + sets(rdlID, muscle: rdlMuscle, grams: 120_000, reps: 8, count: 4, workout: wLegs, offset: 4)
        + sets(benchID, muscle: .chest, grams: 85_049, reps: 6, count: 4, workout: wPush)
    return ProgressionEngine.compute(input: input(workouts: [wLegs, wPush], sets: allSets),
                                     config: config, calendar: cal, asOf: date(2025, 6, 5, 20))
}

// MARK: - PL invariance across the legs split (stability is sacred)

@Suite("Legs split — PL invariance")
struct LegsSplitPLInvarianceTests {

    /// Identical sets must produce identical strengthScore/powerLevel whether the
    /// lower-body work is tagged legacy `.legs`, the split groups, or a mixture —
    /// the lower bucket takes ONE best e1RM across all of `Muscle.lowerBody`.
    @Test("Same sets, same PL: .legs vs split groups vs mixed tags")
    func splitTagsDoNotMovePL() throws {
        let config = try ProgressionConfig.load()
        let legacy = snapshot(squatMuscle: .legs, rdlMuscle: .legs, config: config)
        let split = snapshot(squatMuscle: .quadriceps, rdlMuscle: .hamstrings, config: config)
        let mixed = snapshot(squatMuscle: .glutes, rdlMuscle: .legs, config: config)

        #expect(legacy.powerLevel > 0)  // the fixture actually qualifies
        for other in [split, mixed] {
            #expect(other.powerLevel == legacy.powerLevel)
            #expect(other.strengthScore == legacy.strengthScore)
            #expect(other.weeklyVolumeLb == legacy.weeklyVolumeLb)
            #expect(other.consistencyMultiplier == legacy.consistencyMultiplier)
            #expect(other.streakWeeks == legacy.streakWeeks)
        }
    }

    /// Two split groups in one session still fill ONE strength bucket: the score
    /// counts the single best lower-body e1RM plus chest — never quads + hams.
    @Test("Lower-body groups share one bucket (best, not sum)")
    func lowerBodyBucketsBestNotSum() throws {
        let config = try ProgressionConfig.load()
        let split = snapshot(squatMuscle: .quadriceps, rdlMuscle: .hamstrings, config: config)

        let squatE1RM = ProgressEngine.e1RMGrams(weightGrams: 150_000, reps: 5)
        let rdlE1RM = ProgressEngine.e1RMGrams(weightGrams: 120_000, reps: 8)
        let benchE1RM = ProgressEngine.e1RMGrams(weightGrams: 85_049, reps: 6)
        let expected = Units.pounds(fromGrams: max(squatE1RM, rdlE1RM))
            + Units.pounds(fromGrams: benchE1RM)
        #expect(split.strengthScore == Int(expected.rounded()))
    }

    /// The bucket map itself: every lower-body case (legacy `.legs` included)
    /// resolves to the same bucket; non-scoring groups resolve to none — the
    /// coverage badge counts buckets, so ANY lower group fills the lower slot.
    @Test("strengthBucketIndex: one shared lower bucket, core/other excluded")
    func bucketIndexes() {
        #expect(ProgressionEngine.strengthBuckets.count == 6)
        let lower = ProgressionEngine.strengthBucketIndex(for: .legs)
        #expect(lower != nil)
        for muscle in Muscle.lowerBody {
            #expect(ProgressionEngine.strengthBucketIndex(for: muscle) == lower)
        }
        let uppers: [Muscle] = [.chest, .triceps, .biceps, .shoulders, .back]
        let indexes = uppers.compactMap(ProgressionEngine.strengthBucketIndex(for:)) + [lower!]
        #expect(Set(indexes).count == 6)   // six distinct buckets, no overlap
        #expect(ProgressionEngine.strengthBucketIndex(for: .core) == nil)
        #expect(ProgressionEngine.strengthBucketIndex(for: .other) == nil)
    }
}

// MARK: - LegsMigration remap

@Suite("Legs split — LegsMigration")
struct LegsMigrationTests {

    /// Every catalog leg-exercise name lands per the re-assignment table,
    /// regardless of casing (the store may carry either).
    @Test("Catalog names map per the table")
    func catalogNames() {
        let table: [(String, Muscle)] = [
            ("Squat", .quadriceps),
            ("Hack Squat", .quadriceps),
            ("Bulgarian Split Squat", .quadriceps),
            ("Leg Extension", .quadriceps),
            ("Lunges", .quadriceps),
            ("Leg Press", .quadriceps),
            ("Leg Curl", .hamstrings),
            ("Romanian Deadlift", .hamstrings),
            ("Hip Thrust", .glutes),
            ("Sumo Deadlift", .glutes),
            ("Kickbacks", .glutes),
            ("Standing Calf Raises", .calves),
            ("Seated Calf Raises", .calves),
        ]
        for (name, expected) in table {
            #expect(LegsMigration.remap(exerciseName: name) == expected, "\(name)")
            #expect(LegsMigration.remap(exerciseName: name.uppercased()) == expected, "\(name) uppercased")
        }
    }

    /// Keyword rules are checked IN ORDER — the specific tissue word must beat
    /// the generic movement word later in the list.
    @Test("Keyword ordering: specific tissue beats generic movement")
    func keywordOrdering() {
        // calf precedes press — a calf press is calves, not a quad press.
        #expect(LegsMigration.remap(exerciseName: "Seated Calf Press") == .calves)
        // nordic precedes curl (both hamstrings, but the ordering is the point).
        #expect(LegsMigration.remap(exerciseName: "Nordic Ham Curl") == .hamstrings)
        // glute ham precedes glute — a GHR is hamstrings work, not glutes.
        #expect(LegsMigration.remap(exerciseName: "Glute Ham Raise") == .hamstrings)
        // stiff precedes deadlift — a stiff-leg pull is hamstrings, not glutes.
        #expect(LegsMigration.remap(exerciseName: "Stiff Leg Deadlift") == .hamstrings)
        // sumo precedes deadlift (both glutes; order still documented by test).
        #expect(LegsMigration.remap(exerciseName: "Sumo Squat Deadlift") == .glutes)
        // curl precedes squat — a leg-curl variant never re-buckets to quads.
        #expect(LegsMigration.remap(exerciseName: "Squat Stand Leg Curl") == .hamstrings)
    }

    @Test("Custom-name keywords land on the right group")
    func customKeywords() {
        let cases: [(String, Muscle)] = [
            ("Donkey Calve Raise", .calves),
            ("Soleus Press", .calves),
            ("Gastrocnemius Raise", .calves),
            ("Tibialis Raise", .calves),
            ("Barbell Good Morning", .hamstrings),
            ("Dumbbell RDL", .hamstrings),
            ("Glute Bridge", .glutes),
            ("Cable Pull Through", .glutes),
            ("Cable Pull-Through", .glutes),
            ("Hip Abduction Machine", .glutes),
            ("Hip Extension", .glutes),          // "hip ext" precedes "extension"
            ("45 Degree Hyperextension", .glutes),
            ("Hip Hinge Drill", .glutes),
            ("Sissy Squat", .quadriceps),
            ("Walking Lunge", .quadriceps),
            ("Step Ups", .quadriceps),
            ("Hip Adduction Machine", .quadriceps),
        ]
        for (name, expected) in cases {
            #expect(LegsMigration.remap(exerciseName: name) == expected, "\(name)")
        }
    }

    /// Anything unrecognizable falls back to quadriceps — the group closest to
    /// the old undifferentiated legs bucket.
    @Test("Unrecognized names fall back to quadriceps")
    func fallback() {
        #expect(LegsMigration.remap(exerciseName: "Wall Sit") == .quadriceps)
        #expect(LegsMigration.remap(exerciseName: "") == .quadriceps)
        #expect(LegsMigration.remap(exerciseName: "  Mystery Machine Move  ") == .quadriceps)
    }
}

// MARK: - Volume landmarks sanity

@Suite("Legs split — volume landmarks")
struct VolumeLandmarksTests {

    /// Every charted group carries landmarks and the bands nest sanely:
    /// maintenance ≤ floor < sweetLow ≤ sweetHigh < ceiling.
    @Test("Bands nest for every volume group")
    func bandsNest() {
        for muscle in Muscle.volumeGroups {
            let marks = VolumeLandmarks.landmarks(for: muscle)
            guard let marks else {
                Issue.record("\(muscle) has no landmarks")
                continue
            }
            #expect(marks.maintenance <= marks.floor, "\(muscle)")
            #expect(marks.floor < marks.sweetLow, "\(muscle)")
            #expect(marks.sweetLow <= marks.sweetHigh, "\(muscle)")
            #expect(marks.sweetHigh < marks.ceiling, "\(muscle)")
        }
    }

    /// Legacy `.legs` and `.other` have no defensible numbers — charts skip them.
    @Test("No landmarks for .legs (legacy) and .other")
    func excludedGroups() {
        #expect(VolumeLandmarks.landmarks(for: .legs) == nil)
        #expect(VolumeLandmarks.landmarks(for: .other) == nil)
    }

    /// The API-contract constants slices B and C consume.
    @Test("Contract shape: groups, order, lowerBody, session and weekly bounds")
    func contractShape() {
        #expect(Muscle.volumeGroups == [
            .chest, .back, .shoulders, .biceps, .triceps, .core,
            .quadriceps, .hamstrings, .glutes, .calves,
        ])
        #expect(Muscle.lowerBody == [.legs, .glutes, .hamstrings, .quadriceps, .calves])
        #expect(VolumeLandmarks.perSessionMax == 10)
        #expect(VolumeLandmarks.weeklyTotalRange == 60...100)
        // Spot the researched numbers the charts anchor on: hamstrings run the
        // deliberately lowest band; back the highest.
        #expect(VolumeLandmarks.landmarks(for: .hamstrings)?.sweetHigh == 10)
        #expect(VolumeLandmarks.landmarks(for: .back)?.ceiling == 22)
    }

    /// Display strings the chips and pickers consume.
    @Test("displayName and shortLabel per the contract")
    func displayStrings() {
        #expect(Muscle.legs.displayName == "Legs (legacy)")
        #expect(Muscle.quadriceps.displayName == "Quadriceps")
        #expect(Muscle.glutes.displayName == "Glutes")
        #expect(Muscle.chest.displayName == "Chest")
        #expect(Muscle.quadriceps.shortLabel == "QUADS")
        #expect(Muscle.hamstrings.shortLabel == "HAMS")
        #expect(Muscle.glutes.shortLabel == "GLUTES")
        #expect(Muscle.calves.shortLabel == "CALVES")
        #expect(Muscle.chest.shortLabel == "CHEST")
        // Old data still decodes: the legacy raw value must round-trip.
        #expect(Muscle(rawValue: "legs") == .legs)
    }
}
