import SwiftUI
import SwiftData
import Charts
import SettCore

/// Tab 3 — all numbers. The W/M/Y period control is the single source of truth;
/// every card animates data changes with `.snappy`. Set samples are extracted
/// once per appearance and reused across period switches (recompute is cheap).
struct ProgressTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query private var goals: [Goal]
    @Query private var insights: [AIInsight]
    @Query private var sleepDays: [SleepDay]
    @Query private var exercises: [Exercise]
    @Query private var bodyweightEntries: [BodyweightEntry]

    init() {
        let goalFilter = #Predicate<Goal> { $0.deletedAt == nil && $0.isActive }
        _goals = Query(filter: goalFilter, sort: [SortDescriptor(\Goal.createdAt, order: .reverse)])

        let insightFilter = #Predicate<AIInsight> { $0.deletedAt == nil }
        _insights = Query(filter: insightFilter, sort: [SortDescriptor(\AIInsight.createdAt, order: .reverse)])

        let exerciseFilter = #Predicate<Exercise> { $0.deletedAt == nil }
        _exercises = Query(filter: exerciseFilter)

        let bodyweightFilter = #Predicate<BodyweightEntry> { $0.deletedAt == nil }
        _bodyweightEntries = Query(filter: bodyweightFilter,
                                   sort: [SortDescriptor(\BodyweightEntry.loggedAt)])
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period: Period = .week
    @State private var setSamples: [SetSample] = []
    @State private var workoutSamples: [WorkoutSample] = []
    @State private var exerciseNames: [UUID: String] = [:]
    /// Cold load stays instant; only re-appearances animate the refreshed numbers in.
    @State private var hasLoadedOnce = false

    /// Buckets and streaks use ISO weeks (Monday start), matching the engines.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    private var unit: WeightUnit { services.settings.unit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    periodPicker
                    if workoutSamples.count < 2 {
                        chartsLockedCard
                    } else {
                        PowerHistoryCard(history: services.progression.powerLevelHistory,
                                         peakPL: services.progression.snapshot?.allTimePeakPL ?? 0)
                        NetSummaryCard(samples: setSamples, period: period,
                                       unit: unit, calendar: Self.isoCalendar,
                                       phase: services.settings.phase)
                        PRFeedCard(samples: setSamples, exerciseNames: exerciseNames, unit: unit)
                        VolumeChartCard(samples: setSamples, period: period,
                                        unit: unit, calendar: Self.isoCalendar)
                        MuscleBalanceCard(samples: setSamples, period: period,
                                          calendar: Self.isoCalendar)
                        E1RMTrendsCard(samples: setSamples, exerciseNames: exerciseNames, unit: unit)
                        SleepImpactCard(setSamples: setSamples, workoutSamples: workoutSamples,
                                        sleepDays: sleepDays, unit: unit, calendar: Self.isoCalendar)
                    }
                    // Bodyweight is its own track — a user with one workout but a month
                    // of scale entries still deserves the chart (it was gated before).
                    if !bodyweightEntries.isEmpty {
                        BodyweightCard(entries: bodyweightEntries, unit: unit)
                    }
                    GoalsSection(goals: goals, setSamples: setSamples,
                                 workoutSamples: workoutSamples,
                                 unit: unit, calendar: Self.isoCalendar)
                    InsightsCard(insights: insights)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.snappy, value: period)
            }
            .dungeonBackground()
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: reload)
        }
    }

    // MARK: Period control (single source of truth for every period-driven card)

    /// The shared themed segments (this picker was the donor for `ChamberSegments`).
    private var periodPicker: some View {
        ChamberSegments(selection: $period,
                        options: Period.allCases.map { ($0, $0.rawValue) })
    }

    // MARK: Empty state — "Charts unlock after 2 workouts"

    private static let placeholderBars: [Double] = [3, 5, 4, 7, 6, 9, 8, 10]

    private var chartsLockedCard: some View {
        ZStack {
            // Faint ghost bars sit behind the empty state so the locked card still reads
            // as a chart-to-be rather than a dead panel.
            Chart {
                ForEach(Array(Self.placeholderBars.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Period", item.offset),
                            y: .value("Volume", item.element))
                        .foregroundStyle(SettColor.iron.opacity(0.6))
                        .cornerRadius(3)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .opacity(0.4)
            .frame(height: 120)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            EmptyChamber(title: "Scouters offline",
                         message: "Log two sessions and the charts come online.",
                         compact: true) {
                ChamberCTAButton("Start a workout") { services.session.quickStart() }
            }
        }
        .frame(maxWidth: .infinity)
        .settCard()
    }

    // MARK: Data (extracted once per appearance, reused across period switches)

    private func reload() {
        if hasLoadedOnce && !reduceMotion {
            withAnimation(.snappy) { applySamples() }
        } else {
            applySamples()
        }
        hasLoadedOnce = true
    }

    private func applySamples() {
        // Progress can be the first tab shown (deep link / debug) — recompute so
        // the PL trajectory is populated even if Home/Power haven't run their .task.
        services.progression.recompute(context: modelContext)
        setSamples = SampleExtractor.setSamples(context: modelContext)
        workoutSamples = SampleExtractor.workoutSamples(context: modelContext)

        var names: [UUID: String] = [:]
        let workoutExercises = (try? modelContext.fetch(FetchDescriptor<WorkoutExercise>())) ?? []
        for workoutExercise in workoutExercises where workoutExercise.deletedAt == nil {
            names[workoutExercise.exerciseID] = workoutExercise.exerciseNameSnapshot
        }
        for exercise in exercises {
            names[exercise.id] = exercise.name
        }
        exerciseNames = names
    }
}
