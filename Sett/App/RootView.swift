import SwiftUI
import SwiftData
import SettCore

struct RootView: View {
    @Environment(WorkoutSessionStore.self) private var session
    @State private var selectedTab: Tab = .home

    enum Tab: Hashable {
        case home, train, progress, power
    }

    var body: some View {
        @Bindable var session = session
        TabView(selection: $selectedTab) {
            HomeTabView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            TrainTabView()
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                .tag(Tab.train)
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
            PowerTabView()
                .tabItem { Label("Power", systemImage: "bolt.fill") }
                .tag(Tab.power)
        }
        .fullScreenCover(isPresented: $session.isPresentingWorkout) {
            ActiveWorkoutView()
        }
        .sheet(item: $session.completedSummary) { summary in
            WorkoutSummaryView(summary: summary)
        }
        .onAppear {
            #if DEBUG
            switch ProcessInfo.processInfo.environment["SETT_DEBUG_TAB"] {
            case "train": selectedTab = .train
            case "progress": selectedTab = .progress
            case "power": selectedTab = .power
            default: break
            }
            // "1" → demo workout + overview sheet; "player" → demo workout, scouter only.
            if let flag = ProcessInfo.processInfo.environment["SETT_DEBUG_OVERVIEW"], !flag.isEmpty {
                session.debugStartOverviewDemo()
            }
            #endif
        }
        #if DEBUG
        .overlay {
            if let flag = ProcessInfo.processInfo.environment["SETT_DEBUG_GLYPHS"], !flag.isEmpty {
                ExerciseGlyphContactSheet()
            }
            if let flag = ProcessInfo.processInfo.environment["SETT_DEBUG_ICONLAB"], !flag.isEmpty {
                IconLabSheet()
            }
        }
        #endif
    }
}
