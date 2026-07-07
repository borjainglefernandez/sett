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
    }
}
