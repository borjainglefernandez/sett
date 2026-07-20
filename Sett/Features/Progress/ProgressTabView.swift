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
    /// Which graph the switcher is showing. `.power` leads (the headline number);
    /// reload() drops it to the first backed section when the ledger is too thin.
    @State private var section: ProgressSection = .power
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
                    sectionChips
                    // The W/M/Y control belongs only to the bucketed cards — showing it
                    // above Power/PRs/Weight/Goals/Insights would just be a dead knob.
                    if showsPeriodPicker {
                        periodPicker
                    }
                    // One graph at a time; swapping sections crossfades on `.snappy`.
                    sectionContent
                        .id(section)
                        .transition(.opacity)
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

    // MARK: Section switcher (chip bar + the one visible graph)
    //
    // Availability rule (the cleaner of the two the brief offered): the seven
    // workout-derived chips are hidden wholesale until the old 2-workout gate clears,
    // and `section` snaps to the first backed graph in reload(). weight/goals/insights
    // ride their own data, so a chip is always present — the locked panel only surfaces
    // in the (unreachable-in-practice) case where nothing at all is backed.

    /// Graphs the ledger can currently back, in declaration = left-to-right order.
    private var availableSections: [ProgressSection] {
        ProgressSection.allCases.filter(isAvailable)
    }

    private func isAvailable(_ section: ProgressSection) -> Bool {
        switch section {
        case .weight:           return !bodyweightEntries.isEmpty
        case .goals, .insights: return true
        // power/net/volume/muscles/strength/sleep/prs all read finished workouts.
        default:                return workoutSamples.count >= 2
        }
    }

    /// Only the three bucketed cards take `period`; the rest ignore it.
    private var showsPeriodPicker: Bool {
        switch section {
        case .net, .volume, .muscles: return true
        default:                      return false
        }
    }

    /// Horizontal because there are ~10 sections — the `ChamberSegments` capsule
    /// grammar, made scrollable, with the active chip pulling itself into view.
    private var sectionChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableSections, id: \.self) { item in
                        sectionChip(item).id(item)
                    }
                }
                .padding(.vertical, 2) // breathing room so the capsules aren't clipped
            }
            .onChange(of: section) { _, selected in
                withAnimation(.snappy) { proxy.scrollTo(selected, anchor: .center) }
            }
        }
    }

    private func sectionChip(_ item: ProgressSection) -> some View {
        let isSelected = section == item
        return Button {
            Haptics.light()
            withAnimation(.snappy) { section = item }
        } label: {
            Text(item.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .lineLimit(1)
                // etch is the app's ink-on-heroCyan (see ChamberSegments); ash otherwise.
                .foregroundStyle(isSelected ? SettColor.etch : SettColor.ash)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(isSelected ? SettColor.heroCyan : SettColor.card))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The single visible graph. If the stored pick isn't backed yet (the default
    /// `.power` on a fresh ledger, before reload() snaps it), fall to the first
    /// available so the card never contradicts the chips; nil = locked panel.
    @ViewBuilder
    private var sectionContent: some View {
        if let shown = isAvailable(section) ? section : availableSections.first {
            graph(for: shown)
        } else {
            chartsLockedCard
        }
    }

    /// Each card keeps the exact arguments the old vertical stack fed it; only Power
    /// gains the breakdown panel beneath its history.
    @ViewBuilder
    private func graph(for kind: ProgressSection) -> some View {
        switch kind {
        case .power:
            // Explicit stack: `.id`/`.transition` collapse `sectionContent` into a single
            // child, so this two-card case would overlap without its own VStack.
            VStack(alignment: .leading, spacing: 16) {
                PowerHistoryCard(history: services.progression.powerLevelHistory,
                                 peakPL: services.progression.snapshot?.allTimePeakPL ?? 0)
                PLBreakdownView()
            }
        case .net:
            NetSummaryCard(samples: setSamples, period: period,
                           unit: unit, calendar: Self.isoCalendar,
                           phase: services.settings.phase)
        case .volume:
            VolumeChartCard(samples: setSamples, period: period,
                            unit: unit, calendar: Self.isoCalendar)
        case .muscles:
            MuscleBalanceCard(samples: setSamples, period: period,
                              calendar: Self.isoCalendar)
        case .strength:
            E1RMTrendsCard(samples: setSamples, exerciseNames: exerciseNames, unit: unit)
        case .sleep:
            SleepImpactCard(setSamples: setSamples, workoutSamples: workoutSamples,
                            sleepDays: sleepDays, unit: unit, calendar: Self.isoCalendar)
        case .weight:
            BodyweightCard(entries: bodyweightEntries, unit: unit)
        case .prs:
            PRFeedCard(samples: setSamples, exerciseNames: exerciseNames, unit: unit)
        case .goals:
            GoalsSection(goals: goals, setSamples: setSamples,
                         workoutSamples: workoutSamples,
                         unit: unit, calendar: Self.isoCalendar)
        case .insights:
            InsightsCard(insights: insights)
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

        // Keep the switcher on a graph the data can back: a fresh user defaults to
        // .power, but with <2 workouts the workout-derived chips are hidden, so drop
        // to the first section that actually has data (weight/goals).
        if !isAvailable(section) {
            section = availableSections.first ?? .goals
        }
    }
}

/// The switchable graphs on the Progress tab. Declaration order = chip order;
/// `title` is the short chip label (mono-uppercased in the chip itself).
private enum ProgressSection: CaseIterable, Hashable {
    case power, net, volume, muscles, strength, sleep, weight, prs, goals, insights

    var title: String {
        switch self {
        case .power:    return "Power"
        case .net:      return "Net"
        case .volume:   return "Volume"
        case .muscles:  return "Muscles"
        case .strength: return "Strength"
        case .sleep:    return "Sleep"
        case .weight:   return "Weight"
        case .prs:      return "PRs"
        case .goals:    return "Goals"
        case .insights: return "Insights"
        }
    }
}
