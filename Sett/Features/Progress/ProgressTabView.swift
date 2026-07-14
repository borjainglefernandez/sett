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

    @State private var period: Period = .week
    @State private var setSamples: [SetSample] = []
    @State private var workoutSamples: [WorkoutSample] = []
    @State private var exerciseNames: [UUID: String] = [:]

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

    /// Themed capsule segments — the stock white segmented control was the one
    /// off-world element on the page.
    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(Period.allCases) { candidate in
                Button {
                    period = candidate
                    Haptics.selection()
                } label: {
                    Text(candidate.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(period == candidate ? SettColor.etch : SettColor.ash)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if period == candidate {
                                Capsule().fill(SettColor.heroCyan)
                            } else {
                                Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.rawValue.capitalized)
                .accessibilityAddTraits(period == candidate ? [.isSelected] : [])
            }
        }
    }

    // MARK: Empty state — "Charts unlock after 2 workouts"

    private static let placeholderBars: [Double] = [3, 5, 4, 7, 6, 9, 8, 10]

    private var chartsLockedCard: some View {
        VStack(spacing: 12) {
            Chart {
                ForEach(Array(Self.placeholderBars.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Period", item.offset),
                            y: .value("Volume", item.element))
                        .foregroundStyle(Color(uiColor: .systemGray4))
                        .cornerRadius(3)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .opacity(0.4)
            .frame(height: 120)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            Text("Charts unlock after 2 workouts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .settCard()
    }

    // MARK: Data (extracted once per appearance, reused across period switches)

    private func reload() {
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
