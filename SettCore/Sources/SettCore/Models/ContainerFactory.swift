import Foundation
import SwiftData

public extension ModelContainer {
    /// The app's on-disk container. If the store can't be opened — an incompatible
    /// schema change with no lightweight migration would otherwise `fatalError`-crash-loop
    /// every existing user on launch — the old store is quarantined and rebuilt fresh so
    /// the app still boots. Pre-sync there is no cloud copy to lose; once sync lands this
    /// should become a real `SchemaMigrationPlan` + a server re-pull.
    static func sett() throws -> ModelContainer {
        let schema = Schema(SettSchema.allModels)
        let config = ModelConfiguration("Sett", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            quarantineStore(at: config.url)
            return try ModelContainer(for: schema, configurations: [config])
        }
    }

    /// Move the SQLite store (and its -wal/-shm siblings) aside so a fresh one is built.
    private static func quarantineStore(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
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
