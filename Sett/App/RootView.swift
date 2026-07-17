import SwiftUI
import SwiftData
import SettCore

struct RootView: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
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
            ActiveWorkoutView(startsInOverview: services.settings.startsInList)
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

    @Environment(AppServices.self) private var services
    @Query private var finished: [Workout]
    @Query private var allExercises: [Exercise]
    @Query private var allInsights: [AIInsight]
    @Query private var allRoutines: [Routine]

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
        case "howpower":
            HowPowerWorksView()
        case "onboarding":
            // The harness renders this as a raw overlay (no presentation), so
            // dismiss() is a no-op there — honor "Begin training" by dropping the
            // overlay once the flow marks itself complete.
            if !services.settings.hasOnboarded {
                OnboardingView()
            }
        case "bodyweight":
            Color.clear.sheet(isPresented: .constant(true)) {
                BodyweightLogSheet(latest: nil)
            }
        case "picker":
            RoutineExercisePickerSheet { _ in }
        case "routinepicker":
            RoutineExercisePickerSheet { _ in }
        case "exercisedetail":
            if let ex = mostLoggedExercise() {
                NavigationStack { ExerciseDetailView(exercise: ex) }
            }
        case "insightdetail":
            if let digest = allInsights.first(where: { $0.kind == .weeklyDigest }) ?? allInsights.first {
                NavigationStack { InsightDetailView(insight: digest) }
            }
        case "goalprtarget":
            GoalEditorSheet(initialKind: .prTarget)
        case "gympicker":
            GymPickerSheet(currentID: nil) { _ in }
        case "routineeditor":
            if let routine = allRoutines.first(where: { $0.deletedAt == nil }) {
                NavigationStack { RoutineEditorView(routine: routine) }
            }
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

    /// The exercise with the most logged sets across finished workouts — the one whose
    /// detail charts have the richest history to eyeball.
    private func mostLoggedExercise() -> Exercise? {
        var counts: [UUID: Int] = [:]
        for workout in finished {
            for we in workout.orderedExercises { counts[we.exerciseID, default: 0] += we.orderedSets.count }
        }
        guard let topID = counts.max(by: { $0.value < $1.value })?.key else { return allExercises.first }
        return allExercises.first { $0.id == topID }
    }
}
#endif
