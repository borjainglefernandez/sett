import Foundation
import SwiftData

public extension ModelContainer {
    /// The app's on-disk container.
    static func sett() throws -> ModelContainer {
        let schema = Schema(SettSchema.allModels)
        let config = ModelConfiguration("Sett", schema: schema)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// In-memory container for tests and previews.
    static func settTest() throws -> ModelContainer {
        let schema = Schema(SettSchema.allModels)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

public extension ModelContext {
    /// Fetch-or-create the SaiyanState singleton.
    func saiyanState() -> SaiyanState {
        let descriptor = FetchDescriptor<SaiyanState>()
        if let existing = (try? fetch(descriptor))?.first { return existing }
        let fresh = SaiyanState()
        insert(fresh)
        return fresh
    }

    /// Fetch-or-create the SyncState singleton.
    func syncState() -> SyncState {
        let descriptor = FetchDescriptor<SyncState>()
        if let existing = (try? fetch(descriptor))?.first { return existing }
        let fresh = SyncState()
        insert(fresh)
        return fresh
    }
}
