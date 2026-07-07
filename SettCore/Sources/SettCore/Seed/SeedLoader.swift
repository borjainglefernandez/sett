import Foundation
import SwiftData

/// Loads the frozen 67-exercise catalog. Idempotent: inserts only ids not already present,
/// so re-running never duplicates and never touches user edits.
@MainActor
public enum SeedLoader {
    public struct SeedExercise: Decodable {
        public let id: UUID
        public let name: String
        public let muscle: String
        public let equipment: String
    }

    @discardableResult
    public static func seedExercises(into context: ModelContext) throws -> Int {
        guard let url = Bundle.module.url(forResource: "ExerciseSeed", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let seeds = try JSONDecoder().decode([SeedExercise].self, from: Data(contentsOf: url))

        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingIDs = Set(existing.map(\.id))

        var inserted = 0
        for seed in seeds where !existingIDs.contains(seed.id) {
            let exercise = Exercise(
                id: seed.id,
                name: seed.name,
                muscle: Muscle(rawValue: seed.muscle) ?? .other,
                equipment: Equipment(rawValue: seed.equipment) ?? .machine,
                isCustom: false
            )
            exercise.needsPush = false // catalog rows are shared with the server already
            context.insert(exercise)
            inserted += 1
        }
        if inserted > 0 { try context.save() }
        return inserted
    }
}
