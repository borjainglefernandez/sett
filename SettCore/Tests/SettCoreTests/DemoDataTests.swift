import Foundation
import SwiftData
import Testing
@testable import SettCore

@MainActor
@Suite("DemoData seeding")
struct DemoDataTests {

    private func finishedWorkouts(_ context: ModelContext) throws -> [Workout] {
        try context.fetch(FetchDescriptor<Workout>())
            .filter { $0.endedAt != nil && $0.deletedAt == nil }
            .sorted { $0.startedAt < $1.startedAt }
    }

    @Test("seed produces a dense six-month history across every surface")
    func seedVolume() throws {
        let container = try ModelContainer.settTest()
        let context = container.mainContext
        DemoData.seed(context: context, monthsBack: 6)

        let workouts = try finishedWorkouts(context)
        #expect(workouts.count > 70)
        #expect(workouts.allSatisfy { $0.needsPush == false })
        #expect(workouts.allSatisfy { $0.routineID != nil && $0.routineNameSnapshot != nil })
        #expect(workouts.allSatisfy { $0.gymID != nil && $0.gymNameSnapshot != nil })

        let sleepDays = try context.fetch(FetchDescriptor<SleepDay>())
        #expect(sleepDays.count > 170)

        let routines = try context.fetch(FetchDescriptor<Routine>()).filter { $0.deletedAt == nil }
        #expect(routines.count == 3)
        #expect(Set(routines.map { $0.name }) == ["Push Day", "Pull Day", "Leg Day"])

        let gyms = try context.fetch(FetchDescriptor<Gym>()).filter { $0.deletedAt == nil }
        #expect(gyms.count == 2)
        #expect(gyms.contains { $0.name == "Iron Temple" && $0.isHome })
        #expect(gyms.contains { $0.name == "Hotel Chamber" && $0.dayPassPriceCents == 1500 && $0.quickRating == 4 })

        let goals = try context.fetch(FetchDescriptor<Goal>()).filter { $0.deletedAt == nil }
        #expect(goals.count == 3)
        #expect(goals.contains { $0.kind == .frequency && !$0.isActive && $0.completedAt != nil })
        #expect(goals.contains { $0.kind == .frequency && $0.isActive })
        #expect(goals.contains { $0.kind == .prTarget && $0.isActive && $0.exerciseID != nil })

        let digests = try context.fetch(FetchDescriptor<AIInsight>())
            .filter { $0.deletedAt == nil && $0.kind == .weeklyDigest }
        #expect(digests.count == 1)
        #expect(digests.first?.source == .server)
        #expect(digests.first?.body.contains("Plateau Watch") == true)
    }

    @Test("history contains a 20+ day training gap")
    func trainingGap() throws {
        let container = try ModelContainer.settTest()
        let context = container.mainContext
        DemoData.seed(context: context, monthsBack: 6)

        let dates = try finishedWorkouts(context).map { $0.startedAt }
        var maxGap: TimeInterval = 0
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            maxGap = max(maxGap, later.timeIntervalSince(earlier))
        }
        #expect(maxGap >= 20 * 86_400)
    }

    @Test("seeding is deterministic across containers")
    func determinism() throws {
        let containerA = try ModelContainer.settTest()
        let containerB = try ModelContainer.settTest()
        DemoData.seed(context: containerA.mainContext, monthsBack: 6)
        DemoData.seed(context: containerB.mainContext, monthsBack: 6)

        let workoutsA = try finishedWorkouts(containerA.mainContext)
        let workoutsB = try finishedWorkouts(containerB.mainContext)
        #expect(!workoutsA.isEmpty)
        #expect(workoutsA.count == workoutsB.count)
        #expect(workoutsA.first?.startedAt == workoutsB.first?.startedAt)
        #expect(workoutsA.last?.startedAt == workoutsB.last?.startedAt)

        let setsA = try containerA.mainContext.fetchCount(FetchDescriptor<SetEntry>())
        let setsB = try containerB.mainContext.fetchCount(FetchDescriptor<SetEntry>())
        #expect(setsA == setsB)

        let sleepA = try containerA.mainContext.fetchCount(FetchDescriptor<SleepDay>())
        let sleepB = try containerB.mainContext.fetchCount(FetchDescriptor<SleepDay>())
        #expect(sleepA == sleepB)
    }

    @Test("seedIfRequested no-ops once finished workouts exist")
    func seedIfRequestedIdempotent() throws {
        let container = try ModelContainer.settTest()
        let context = container.mainContext

        DemoData.seedIfRequested(context: context)
        let workoutsAfterFirst = try finishedWorkouts(context).count
        let sleepAfterFirst = try context.fetchCount(FetchDescriptor<SleepDay>())
        #expect(workoutsAfterFirst > 0)

        DemoData.seedIfRequested(context: context)
        let workoutsAfterSecond = try finishedWorkouts(context).count
        let sleepAfterSecond = try context.fetchCount(FetchDescriptor<SleepDay>())
        #expect(workoutsAfterSecond == workoutsAfterFirst)
        #expect(sleepAfterSecond == sleepAfterFirst)
    }
}
