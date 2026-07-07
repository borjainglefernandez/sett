import SwiftUI
import SwiftData
import UIKit
import SettCore

@main
struct SettApp: App {
    let container: ModelContainer
    @State private var services: AppServices

    init() {
        Self.configureDungeonChrome()
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
                .preferredColorScheme(.dark) // The dungeon has no light mode.
        }
        .modelContainer(container)
    }

    /// Dungeon chrome: opaque near-black nav and tab bars (matching
    /// SettColor.screen, #0A0D12) with a hairline border shadow and cyan tint,
    /// so the system bars never flash a lighter gray at scroll edges.
    private static func configureDungeonChrome() {
        let screen = UIColor(red: 0x0A / 255, green: 0x0D / 255, blue: 0x12 / 255, alpha: 1)
        let border = UIColor(red: 0x2A / 255, green: 0x35 / 255, blue: 0x48 / 255, alpha: 0.6)
        let cyan = UIColor(red: 0x64 / 255, green: 0xD2 / 255, blue: 0xFF / 255, alpha: 1)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = screen
        nav.shadowColor = border
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = cyan

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = screen
        tab.shadowColor = border
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = cyan
    }
}
