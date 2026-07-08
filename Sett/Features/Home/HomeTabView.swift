import SwiftUI
import SwiftData
import SettCore

/// Tab 1 — the dashboard. Answers "what do I do right now?":
/// greeting + streak, 7-Slot Burst Row, start button, bodyweight chip,
/// Directive Panel, latest insight, recent workouts.
struct HomeTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var insights: [AIInsight]
    @Query private var frequencyGoals: [Goal]
    @Query private var latestBodyweight: [BodyweightEntry]

    @State private var isShowingSettings = false

    init() {
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        let finishedSort = [SortDescriptor(\Workout.startedAt, order: .reverse)]
        _finishedWorkouts = Query(filter: finishedFilter, sort: finishedSort)

        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])

        let insightFilter = #Predicate<AIInsight> { $0.deletedAt == nil }
        _insights = Query(filter: insightFilter, sort: [SortDescriptor(\AIInsight.createdAt, order: .reverse)])

        let goalFilter = #Predicate<Goal> { $0.kindRaw == "frequency" && $0.isActive && $0.deletedAt == nil }
        _frequencyGoals = Query(filter: goalFilter)

        let bodyweightFilter = #Predicate<BodyweightEntry> { $0.deletedAt == nil }
        var bodyweightDescriptor = FetchDescriptor<BodyweightEntry>(
            predicate: bodyweightFilter,
            sortBy: [SortDescriptor(\BodyweightEntry.loggedAt, order: .reverse)]
        )
        bodyweightDescriptor.fetchLimit = 1
        _latestBodyweight = Query(bodyweightDescriptor)
    }

    /// Streaks and weekly goals use ISO weeks (Monday start), matching the engines.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if finishedWorkouts.isEmpty {
                        firstRunCard
                    } else {
                        SevenSlotBurstRow(trainedDays: trainedDaysThisWeek, goalTarget: weeklyGoalTarget)
                        NetGlanceStrip()
                        startCard
                    }
                    BodyweightChipCard(latest: latestBodyweight.first)
                    DirectivePanel()
                    if let insight = insights.first {
                        insightTeaser(insight)
                    }
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .dungeonBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
        }
    }

    // MARK: Header (greeting + streak chip)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(greeting)
                .font(.largeTitle.bold())
            Spacer()
            if streakWeeks > 0 {
                Label("\(streakWeeks) wk", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.heroCyan) // gold audit: gold is the PL's, streak is ki
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SettColor.card, in: Capsule())
                    .accessibilityLabel("\(streakWeeks) week streak")
            }
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: "Good morning"
        case ..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var streakWeeks: Int {
        StreakEngine.streakWeeks(
            workoutDates: finishedWorkouts.map(\.startedAt),
            minDaysPerWeek: 2,
            calendar: Self.isoCalendar,
            asOf: .now
        )
    }

    // MARK: 7-Slot Burst Row inputs

    private var weeklyGoalTarget: Int {
        frequencyGoals.first?.targetValue ?? 3
    }

    /// Trained days of the current ISO week as 0 = Monday … 6 = Sunday.
    private var trainedDaysThisWeek: Set<Int> {
        let calendar = Self.isoCalendar
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        let indices = finishedWorkouts
            .filter { week.contains($0.startedAt) }
            .map { (calendar.component(.weekday, from: $0.startedAt) + 5) % 7 }
        return Set(indices)
    }

    // MARK: Start card

    /// Today's routine per `daysOfWeekMask` (bit 0 = Monday … bit 6 = Sunday).
    private var todaysRoutine: Routine? {
        let weekday = Calendar.current.component(.weekday, from: .now) // 1 = Sunday … 7 = Saturday
        let mondayIndex = (weekday + 5) % 7
        return routines.first { ($0.daysOfWeekMask >> mondayIndex) & 1 == 1 }
    }

    private var startCard: some View {
        VStack(spacing: 12) {
            Button {
                if let routine = todaysRoutine {
                    session.start(routine: routine)
                } else {
                    session.quickStart()
                }
            } label: {
                Text(todaysRoutine.map { "Start \($0.name)" } ?? "Quick Start")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Aura.cyan, in: Capsule())
            }
            if todaysRoutine != nil {
                Button("Quick Start") {
                    session.quickStart()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var firstRunCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 44))
                .foregroundStyle(Aura.cyan)
            Text("Your training arc starts here")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Button {
                session.quickStart()
            } label: {
                Text("Start your first workout")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Aura.cyan, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .settCard()
    }

    // MARK: Insight teaser

    private func insightTeaser(_ insight: AIInsight) -> some View {
        NavigationLink {
            InsightDetailView(insight: insight)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(SettColor.heroCyan) // gold audit: insights are ki, not PL
                Text(firstLine(of: insight.body))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .settCard()
        }
        .buttonStyle(.plain)
    }

    private func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }

    // MARK: Recent workouts

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
                NavigationLink("All Workouts") {
                    HistoryListView()
                }
                .font(.subheadline.weight(.semibold))
            }
            if finishedWorkouts.isEmpty {
                Text("No workouts yet — your history writes itself.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settCard()
            } else {
                VStack(spacing: 8) {
                    ForEach(finishedWorkouts.prefix(3)) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            recentRow(workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func recentRow(_ workout: Workout) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(WorkoutFormat.duration(workout.durationSeconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .settCard()
    }

    // MARK: Onboarding

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !services.settings.hasOnboarded },
            set: { isPresented in
                if !isPresented { services.settings.hasOnboarded = true }
            }
        )
    }
}
