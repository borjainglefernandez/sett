import SwiftUI
import SwiftData
import SettCore

@main
struct SettApp: App {
    let container: ModelContainer
    @State private var services: AppServices

    init() {
        do {
            let container = try ModelContainer.sett()
            self.container = container
            let services = AppServices(container: container)
            self._services = State(initialValue: services)
            Task { @MainActor in
                try? SeedLoader.seedExercises(into: container.mainContext)
                #if DEBUG
                DemoData.seedIfRequested(context: container.mainContext)
                #endif
                services.progression.recompute(context: container.mainContext)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .environment(services.session)
                .environment(services.progression)
                .tint(SettColor.heroCyan)
        }
        .modelContainer(container)
    }
}
