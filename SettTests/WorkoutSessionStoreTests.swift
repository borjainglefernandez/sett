import Testing
import Foundation
import SwiftData
@testable import Sett
@testable import SettCore

/// The store's mutation methods run @MainActor over a real (in-memory) SwiftData
/// container — the exact churned paths (duplicate / move / delete) that had no coverage
/// because they live in the app module, not SettCore.
@MainActor
@Suite("WorkoutSessionStore mutations")
struct WorkoutSessionStoreTests {

    private func makeStore() throws -> (store: WorkoutSessionStore, ctx: ModelContext) {
        let container = try ModelContainer.settTest()
        let store = WorkoutSessionStore(container: container,
                                        settings: UserSettingsStore(),
                                        progression: ProgressionStore())
        return (store, container.mainContext)
    }

    @discardableResult
    private func seedWorkout(_ ctx: ModelContext, setCount: Int)
        -> (workout: Workout, exercise: WorkoutExercise, sets: [SetEntry]) {
        let ex = Exercise(name: "Bench", muscle: .chest, equipment: .barbell)
        ctx.insert(ex)
        let workout = Workout(title: "Test")
        ctx.insert(workout)
        let we = WorkoutExercise(orderIndex: 0, exercise: ex)
        we.workout = workout
        ctx.insert(we)
        var sets: [SetEntry] = []
        for i in 0..<setCount {
            let s = SetEntry(orderIndex: i, weightGrams: 100_000 + i * 10_000, entryUnit: .lb, reps: 5)
            s.workoutExercise = we
            ctx.insert(s)
            sets.append(s)
        }
        try? ctx.save()
        return (workout, we, sets)
    }

    @Test("duplicateSet clones into the next slot and bumps siblings — dense, no collision")
    func duplicateSet() throws {
        let (store, ctx) = try makeStore()
        let (_, we, sets) = seedWorkout(ctx, setCount: 3)   // orderIndex 0,1,2
        store.duplicateSet(sets[0])                          // clone right after set 0
        let ordered = we.orderedSets
        #expect(ordered.count == 4)
        #expect(ordered[1].weightGrams == sets[0].weightGrams)
        #expect(ordered[1].reps == sets[0].reps)
        #expect(ordered[1].id != sets[0].id)
        #expect(ordered.map(\.orderIndex) == [0, 1, 2, 3])   // densified, no duplicate index
    }

    @Test("moveSet reorders within the exercise and re-densifies orderIndex")
    func moveSet() throws {
        let (store, ctx) = try makeStore()
        let (_, we, sets) = seedWorkout(ctx, setCount: 3)
        let firstWeight = sets[0].weightGrams
        store.moveSet(in: we, from: IndexSet(integer: 0), to: 3)  // first → end
        let ordered = we.orderedSets
        #expect(ordered.count == 3)
        #expect(ordered.map(\.orderIndex) == [0, 1, 2])
        #expect(ordered.last?.weightGrams == firstWeight)
    }

    @Test("deleteWorkout tombstones the workout AND every child set + exercise")
    func deleteWorkout() throws {
        let (store, ctx) = try makeStore()
        let (workout, we, sets) = seedWorkout(ctx, setCount: 2)
        store.deleteWorkout(workout)
        #expect(workout.deletedAt != nil)
        #expect(we.deletedAt != nil)
        #expect(sets.allSatisfy { $0.deletedAt != nil })
        // sync discipline held on every tombstoned row
        #expect(workout.needsPush)
        #expect(sets.allSatisfy { $0.needsPush })
    }
}
