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
                ZStack(alignment: .top) {
                    realmGlow
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        powerCrest
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
                    .padding(.bottom, 72) // last Recent row must clear the floating tab bar
                }
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

    // MARK: Realm glow — the chamber sky bleeding into home

    /// A dim wash of the user's chamber realm behind the header, fading to void by the
    /// first card. The session screens live under this sky; home now shares the world
    /// instead of opening on flat black. Scrolls with content, never intercepts touches.
    private var realmGlow: some View {
        Image(ChamberBackground.resolve(services.settings.chamberBackground).assetName)
            .resizable()
            .scaledToFill()
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .clipped()
            .opacity(0.45)
            .mask {
                LinearGradient(stops: [.init(color: .white, location: 0),
                                       .init(color: .white.opacity(0.5), location: 0.45),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Power crest — the sacred number, finally on home

    /// Current PL in gold under the greeting (gold audit: the power level is the ONE
    /// gold-led element, so home's single gold moment is exactly here). Display-only;
    /// the Power tab holds the full character sheet.
    @ViewBuilder
    private var powerCrest: some View {
        let pl = services.progression.snapshotPowerLevel
        if pl > 0 {
            HStack(spacing: 10) {
                SettSigil(size: 20, color: SettColor.saiyanGold)
                VStack(alignment: .leading, spacing: 1) {
                    Text("POWER LEVEL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1.8)
                        .foregroundStyle(SettColor.ash)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        PowerNumeral(pl, size: .m)
                        if let peak = services.progression.snapshot?.allTimePeakPL, peak > pl {
                            Text("PEAK \(peak.formatted())")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .kerning(1)
                                .foregroundStyle(SettColor.ash)
                        }
                    }
                }
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Power level \(pl)")
        }
    }

    // MARK: Header (date eyebrow + chips, then the greeting on its own row)

    /// The greeting used to share a baseline HStack with two rigid chips, so it was the
    /// element SwiftUI squeezed — wrapping "Good afternoon" onto two lines. Chips now live
    /// on the mono date eyebrow, and the greeting gets the full width plus scale-to-fit.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                        .uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.ash)
                    .lineLimit(1)
                Spacer()
                phaseBadge
                if streakWeeks > 0 {
                    Label("\(streakWeeks) wk", systemImage: "flame.fill")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(SettColor.heroCyan) // gold audit: gold is the PL's, streak is ki
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SettColor.card, in: Capsule())
                        .accessibilityLabel("\(streakWeeks) week streak")
                }
            }
            Text(greeting)
                .font(.largeTitle.bold())
                .foregroundStyle(SettColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, 8)
    }

    /// One-tap phase switch — the scoring lens every new workout is stamped with.
    private var phaseBadge: some View {
        Menu {
            Picker("Training phase", selection: Binding(
                get: { services.settings.phase },
                set: { services.settings.trainingPhase = $0.rawValue
                       services.settings.hasChosenPhase = true
                       Haptics.selection() }
            )) {
                ForEach(TrainingPhase.allCases) { phase in
                    Label(phase.title, systemImage: phase.symbolName).tag(phase)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: services.settings.phase.symbolName)
                Text(services.settings.phase.title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1)
            }
            .foregroundStyle(SettColor.heroCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SettColor.card, in: Capsule())
        }
        .accessibilityLabel("Training phase: \(services.settings.phase.title)")
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

    /// The routine you'd start now — today's weekday routine, or the rotation's next up.
    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
    }

    /// The NEXT DIRECTIVE launch card — the doorway wears the destination. The routine's
    /// own chamber-realm art (the same sky the session plays under), scouter reticles,
    /// and the Train tab's white play control; the surge chip docks inside. The old
    /// generic blue capsule was the most off-world element on home.
    private var startCard: some View {
        VStack(spacing: 10) {
            Button {
                if let routine = todaysRoutine {
                    session.start(routine: routine)
                } else {
                    session.quickStart()
                }
            } label: {
                launchCardLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Quick start a workout")
            if todaysRoutine != nil {
                Button("Quick Start") {
                    session.quickStart()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var launchCardLabel: some View {
        ZStack {
            Image(launchRealmAsset)
                .resizable()
                .aspectRatio(contentMode: .fill)
            // Legibility: darker on the text side, easing to reveal the realm.
            LinearGradient(colors: [.black.opacity(0.84), .black.opacity(0.6), .black.opacity(0.28)],
                           startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT DIRECTIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(SettColor.heroCyan)
                    Text(todaysRoutine?.name ?? "Quick Start")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    Text(launchSubline)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.75))
                    if services.progression.snapshot?.restedBonusActive == true {
                        restedChip
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 54, height: 54)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: 2)
                }
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(height: services.progression.snapshot?.restedBonusActive == true ? 148 : 124)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SettColor.heroCyan.opacity(0.35), lineWidth: 1)
            CornerTicksShape(length: 7, inset: 8)
                .stroke(SettColor.heroCyan.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The realm behind the launch card: the routine's own domain, else the app default.
    private var launchRealmAsset: String {
        ChamberBackground.resolve(todaysRoutine?.domainRaw ?? services.settings.chamberBackground).assetName
    }

    private var launchSubline: String {
        if let routine = todaysRoutine {
            let count = routine.orderedExercises.count
            return "\(count) EXERCISE\(count == 1 ? "" : "S")"
        }
        return "EMPTY CHAMBER — LOG AS YOU GO"
    }

    /// The rested-bonus mechanic was computed but never shown. Surface it: a full
    /// rest day arms a 1.25× XP surge on the next workout. Cyan (ki), not gold.
    private var restedChip: some View {
        Label("SURGE ARMED · 1.25× XP", systemImage: "bolt.fill")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .kerning(1)
            .foregroundStyle(SettColor.heroCyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(SettColor.heroCyan.opacity(0.12))
                Capsule().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1)
            }
            .accessibilityLabel("Rested surge armed. Your next workout earns 1.25 times XP.")
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
        HStack(spacing: 12) {
            // The session's opening lift wears its warrior medallion — recent rows
            // read like miniature exercise cards, not a plain text log.
            if let first = workout.orderedExercises.first {
                ExerciseIcon(name: first.exerciseNameSnapshot,
                             equipment: first.equipment,
                             muscle: first.muscle,
                             size: 40, color: SettColor.heroCyan)
            }
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
        .hudCard()
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
