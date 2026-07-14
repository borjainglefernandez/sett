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
        .overlay { debugOverlays }
        #endif
    }

    #if DEBUG
    private static let debugGlyphs = ProcessInfo.processInfo.environment["SETT_DEBUG_GLYPHS"] ?? ""
    private static let debugIconLab = ProcessInfo.processInfo.environment["SETT_DEBUG_ICONLAB"] ?? ""
    private static let debugSurface = ProcessInfo.processInfo.environment["SETT_DEBUG_SURFACE"] ?? ""

    @ViewBuilder
    private var debugOverlays: some View {
        if !Self.debugGlyphs.isEmpty { ExerciseGlyphContactSheet() }
        if !Self.debugIconLab.isEmpty { IconLabSheet() }
        if !Self.debugSurface.isEmpty { DebugSurfaceHost(surface: Self.debugSurface) }
    }
    #endif
}

#if DEBUG
/// Screenshot harness for sheet/push surfaces the simulator can't be clicked into
/// (SETT_DEBUG_SURFACE=forge|history|detail). Renders the surface full-screen over
/// the tabs — same env-hook pattern as the glyph sheets.
struct DebugSurfaceHost: View {
    let surface: String

    @Query private var finished: [Workout]

    init(surface: String) {
        self.surface = surface
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        _finished = Query(filter: finishedFilter,
                          sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])
    }

    var body: some View {
        switch surface {
        case "forge":
            CreateExerciseSheet(initialName: "")
        case "history":
            NavigationStack { HistoryListView() }
        case "detail":
            if let workout = finished.first {
                NavigationStack { WorkoutDetailView(workout: workout) }
            }
        case "settings":
            SettingsView()
        case "picker":
            ExercisePickerSheet()
        case "routinepicker":
            RoutineExercisePickerSheet { _ in }
        case "streak":
            StreakSheet(
                state: StreakEngine.streakState(
                    workoutDates: finished.map(\.startedAt),
                    weeklyTarget: 3,
                    calendar: SevenSlotBurstRow.isoCalendar,
                    asOf: .now),
                mode: .rotation,
                scheduledDays: [])
        default:
            EmptyView()
        }
    }
}
#endif
