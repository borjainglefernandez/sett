import SwiftUI
import SwiftData
import SettCore

/// Tab 1 — the dashboard. Answers "what do I do right now?":
/// greeting + streak, power crest, 7-Slot Burst Row, launch card,
/// Directive Panel, latest insight, recent workouts.
struct HomeTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var insights: [AIInsight]
    @Query private var frequencyGoals: [Goal]

    @State private var isShowingSettings = false
    @State private var isShowingStreak = false
    @State private var isShowingHowPowerWorks = false
    @State private var readingDismissedKey = UserDefaults.standard.string(forKey: "sett.reading.dismissed") ?? ""
    /// Last completed week's net vs the week before — reps + volume for the reading.
    @State private var weeklyReadingNet: NetSummary?
    /// The ΔPL headline counts up from 0 on appear (the "power gained" tally).
    @State private var readingDeltaShown = 0

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
                            if shouldShowWeeklyReading {
                                weeklyReadingCard
                            }
                            if session.rotationCycleSealed {
                                rotationSealBanner
                            }
                            // A zero week means the call to action outranks the zeros:
                            // the launch card rides above the stat slabs until a session lands.
                            if trainedDaysThisWeek.isEmpty {
                                startCard
                                SevenSlotBurstRow(trainedDays: trainedDaysThisWeek,
                                                  goalTarget: weeklyGoalTarget,
                                                  streakWeeks: streakWeeks)
                                NetGlanceStrip()
                            } else {
                                SevenSlotBurstRow(trainedDays: trainedDaysThisWeek,
                                                  goalTarget: weeklyGoalTarget,
                                                  streakWeeks: streakWeeks)
                                NetGlanceStrip()
                                startCard
                            }
                        }
                        // Bodyweight lives on the directive panel's row now — one
                        // surface for the day's asks, not a chip AND a directive.
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
            .task { WeeklyReadingNotifier.schedule() }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingHowPowerWorks) {
                HowPowerWorksView()
            }
            .sheet(isPresented: $isShowingStreak) {
                StreakSheet(state: streakState,
                            mode: services.settings.scheduleMode,
                            scheduledDays: scheduledDayNames,
                            plMultiplier: services.progression.snapshot?.consistencyMultiplier)
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
        ZStack {
            Image(ChamberBackground.resolve(services.settings.chamberBackground).assetName)
                .resizable()
                .scaledToFill()
            // A sparse drift of dormant motes in the sky — the chamber is alive even
            // before a session starts. Same mask, so they fade out with the glow.
            MoteField(tier: .dormant, maxCount: 10)
        }
        .frame(height: 340)
        .frame(maxWidth: .infinity)
        .clipped()
        .opacity(0.45)
        // Fade in from the very top (no hard seam under the nav bar) AND out by the
        // first card — the sky bleeds behind the status bar instead of being sliced.
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .white, location: 0.22),
                                   .init(color: .white.opacity(0.5), location: 0.6),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Power crest — the sacred number, finally on home

    /// Current PL in gold under the greeting (gold audit: the power level is the ONE
    /// gold-led element, so home's single gold moment is exactly here). The number is
    /// the sacred odometer — it ROLLS when a recompute moves it — and the crest is a
    /// tappable doorway into the "how power works" primer.
    @ViewBuilder
    private var powerCrest: some View {
        let pl = services.progression.snapshotPowerLevel
        if pl > 0 {
            Button {
                isShowingHowPowerWorks = true
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Eyebrow("POWER LEVEL")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            SacredNumberView(value: pl, size: .m)
                            Text(UserForm.form(forPL: pl).title)
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .kerning(1.5)
                                .foregroundStyle(SettColor.heroCyan)
                            if let delta = services.progression.plDeltaThisWeek {
                                // Week-so-far ΔPL — momentum, not reward, so it never
                                // wears gold: positive green, negative quiet ash.
                                Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) THIS WEEK")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .kerning(1)
                                    .foregroundStyle(delta >= 0 ? SettColor.positive : SettColor.ash)
                            }
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel({
                // Mirror what the crest shows sighted: the form rank, and the weekly
                // ΔPL momentum when the delta row is visible (non-nil), read naturally.
                var label = "Power level \(pl), \(UserForm.form(forPL: pl).title.capitalized)"
                if let delta = services.progression.plDeltaThisWeek {
                    label += delta == 0 ? ", no change this week"
                                        : ", \(delta > 0 ? "up" : "down") \(abs(delta)) this week"
                }
                return label
            }())
            .accessibilityHint("Shows how the power level works")
        }
    }

    // MARK: Header (date eyebrow + chips, then the greeting on its own row)

    /// The greeting used to share a baseline HStack with two rigid chips, so it was the
    /// element SwiftUI squeezed — wrapping "Good afternoon" onto two lines. Chips now live
    /// on the mono date eyebrow, and the greeting gets the full width plus scale-to-fit.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                        .uppercased())
                Spacer()
                phaseBadge
                streakChip
            }
            Text(greeting)
                .font(.largeTitle.bold())
                .foregroundStyle(SettColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, 8)
    }

    /// The streak is now a control, not a caption — tap for the rules, this week's
    /// target, and the shields that keep a vacation from killing the fire. Shown from
    /// the very first workout (a 0-week streak with a session logged is a fire being
    /// lit, and the sheet explains how to keep it).
    @ViewBuilder
    private var streakChip: some View {
        if streakWeeks > 0 || !finishedWorkouts.isEmpty {
            Button {
                isShowingStreak = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                    Text("\(streakWeeks) wk")
                        .monospacedDigit()
                        .lineLimit(1)
                    if streakState.shields > 0 {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(SettColor.heroCyan.opacity(0.7))
                    }
                }
                .fixedSize()
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SettColor.heroCyan) // gold audit: gold is the PL's, streak is ki
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SettColor.card, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(streakWeeks) week streak\(streakState.shields > 0 ? ", \(streakState.shields) shield\(streakState.shields == 1 ? "" : "s") banked" : "")")
            .accessibilityHint("Shows streak rules and this week's progress")
        }
    }

    // MARK: Weekly Power Reading (Monday's scouter report)

    /// Monday-only, dismissible per ISO week — the week opens with a reading, not a
    /// guilt trip: last week's ΔPL, the form target, the rival gap, the fire.
    private var shouldShowWeeklyReading: Bool {
        #if DEBUG
        if !(ProcessInfo.processInfo.environment["SETT_DEBUG_READING"] ?? "").isEmpty { return true }
        #endif
        let isoWeekday = (Calendar.current.component(.weekday, from: .now) + 5) % 7 // 0 = Monday
        let weekKey = ProgressionStore.isoWeekKey(.now)
        return isoWeekday == 0 && readingDismissedKey != weekKey
    }

    private var weeklyReadingCard: some View {
        let delta = services.progression.weeklyReadingDelta
        let pl = services.progression.snapshotPowerLevel
        let form = UserForm.form(forPL: pl)
        let rival = services.progression.effectiveRival
        let gap = rival.pl - pl
        let pace = services.progression.trailingWeeklyPace
        let growth = services.progression.effectiveRivalGrowth
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("WEEKLY POWER READING", tint: SettColor.heroCyan)
                Spacer()
                Button {
                    let weekKey = ProgressionStore.isoWeekKey(.now)
                    UserDefaults.standard.set(weekKey, forKey: "sett.reading.dismissed")
                    withAnimation(.snappy) { readingDismissedKey = weekKey }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SettColor.ash)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss this week's reading")
            }
            // ΔPL headline — the power banked last week, tallying up from 0 on appear.
            HStack(spacing: 10) {
                Text("ΔPL LAST WEEK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
                    .frame(width: 118, alignment: .leading)
                Text(delta == nil ? "—" : "\(readingDeltaShown >= 0 ? "+" : "")\(readingDeltaShown.formatted())")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(delta.map { $0 >= 0 ? SettColor.positive : SettColor.ash } ?? SettColor.ash)
                    .contentTransition(.numericText(value: Double(readingDeltaShown)))
                Spacer(minLength: 0)
            }
            .accessibilityLabel("Power gained last week: \(delta.map(String.init) ?? "not enough data")")
            if let net = weeklyReadingNet, !net.isNew {
                // Down weeks read ash, not alarm-red — the reading opens the week, not a scolding.
                readingRow("NET VS PRIOR WK", weeklyNetText(net),
                           tint: net.volumeGrams >= 0 && net.reps >= 0 ? SettColor.positive : SettColor.ash)
            }
            readingRow("FORM", "\(form.title) · \((form.nextPL - pl).formatted()) PL TO NEXT",
                       tint: SettColor.heroCyan)
            readingRow("VEXETH",
                       gap > 0 ? "\(gap.formatted()) PL AHEAD\(pace > growth ? " · CATCH IN \(Int((Double(gap) / Double(pace - growth)).rounded(.up))) WK" : "")"
                               : "\(abs(gap).formatted()) PL BEHIND YOU",
                       tint: SettColor.villainCrimson)
            readingRow("STREAK", "\(streakWeeks) WK · \(streakState.shields) SHIELD\(streakState.shields == 1 ? "" : "S")",
                       tint: SettColor.heroCyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudCard()
        .materialize()
        .onAppear(perform: loadWeeklyReading)
        .accessibilityElement(children: .combine)
    }

    /// Last completed week's net vs the week before + the ΔPL count-up, computed once
    /// when the Monday reading appears (SampleExtractor is O(all sets) — not per-frame).
    private func loadWeeklyReading() {
        #if DEBUG
        // Screenshot harness: the demo has no weekly PL snapshots, so seed two so the
        // ΔPL count-up has a real number to tally to.
        if !(ProcessInfo.processInfo.environment["SETT_DEBUG_READING"] ?? "").isEmpty {
            let cal = Calendar.current
            let lw = ProgressionStore.isoWeekKey(cal.date(byAdding: .day, value: -7, to: .now) ?? .now)
            let wb = ProgressionStore.isoWeekKey(cal.date(byAdding: .day, value: -14, to: .now) ?? .now)
            var h = UserDefaults.standard.dictionary(forKey: "sett.plHistory") as? [String: Int] ?? [:]
            if h[lw] == nil || h[wb] == nil {
                h[lw] = 6809; h[wb] = 6560
                UserDefaults.standard.set(h, forKey: "sett.plHistory")
            }
        }
        #endif
        let samples = SampleExtractor.setSamples(context: modelContext)
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        weeklyReadingNet = ProgressEngine.netSummary(samples: samples, exerciseID: nil,
                                                     period: .week, containing: lastWeek,
                                                     calendar: Self.isoCalendar)
        guard let delta = services.progression.weeklyReadingDelta else { return }
        if reduceMotion {
            readingDeltaShown = delta
        } else {
            readingDeltaShown = 0
            withAnimation(.easeOut(duration: 0.9)) { readingDeltaShown = delta }
        }
    }

    private func weeklyNetText(_ net: NetSummary) -> String {
        let unit = services.settings.unit
        let vol = Int((Double(net.volumeGrams) / unit.gramsPerUnit).rounded())
        return "\(vol >= 0 ? "+" : "")\(vol.formatted()) \(unit.symbol) · \(net.reps >= 0 ? "+" : "")\(net.reps) reps"
    }

    private func readingRow(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    /// End-of-rotation hype: the cycle wrapped back to its start — a full lap of the
    /// split. Gold is sanctioned here (a reward moment, like the weekly burst). One
    /// tap acknowledges and clears it.
    private var rotationSealBanner: some View {
        Button {
            withAnimation(.snappy) { session.acknowledgeRotationSeal() }
            Haptics.success()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SettColor.saiyanGold)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("ROTATION SEALED", tint: SettColor.saiyanGold)
                    Text(streakWeeks > 1 ? "Full cycle complete — \(streakWeeks) wk streak burning."
                                         : "Full cycle complete. Back to the top.")
                        .font(.footnote)
                        .foregroundStyle(SettColor.bone)
                }
                Spacer()
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettColor.ash)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hudCard(tint: SettColor.saiyanGold)
        .materialize()
        .accessibilityLabel("Rotation sealed: full cycle complete. Dismisses this banner.")
    }

    /// One-tap phase switch — the scoring lens every new workout is stamped with.
    private var phaseBadge: some View {
        Menu {
            Picker("Training phase", selection: Binding(
                get: { services.settings.phase },
                set: { services.settings.trainingPhase = $0.rawValue
                       services.settings.hasChosenPhase = true
                       services.session.syncActiveWorkoutPhase()
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
                    .lineLimit(1)
            }
            // The capsule always takes its ideal one-line width ("MAINTAINING" was
            // wrapping mid-word); the date eyebrow compresses instead.
            .fixedSize()
            .foregroundStyle(SettColor.heroCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SettColor.card, in: Capsule())
        }
        .accessibilityLabel("Training phase: \(services.settings.phase.title)")
    }

    /// The home marquee — the largest, most-read line. Not a to-do app's "Good
    /// evening": it speaks in the chamber's voice, keyed to the time of day and
    /// whether today's work is already sealed. Selection is deterministic per
    /// calendar day (day-of-year index, never random) so it holds steady across
    /// re-renders instead of flickering. Stays on the bone ramp — no gold (PL's)
    /// or crimson (Vexeth's) here. First launch keeps the plain time-of-day line.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let timeOfDay = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        // Before any history the plain time-of-day line is the honest first word.
        guard !finishedWorkouts.isEmpty else { return timeOfDay }

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let todayIndex = (Self.isoCalendar.component(.weekday, from: .now) + 5) % 7
        let loggedToday = trainedDaysThisWeek.contains(todayIndex)

        let lines: [String]
        if loggedToday {
            // Today's work is sealed — the chamber cools, never "come train".
            lines = ["Sealed. The chamber holds.",
                     "The work is logged. The chamber cools.",
                     "Today's set is sealed."]
        } else if let routine = todaysRoutine?.name {
            lines = ["The chamber's warm — \(routine) waits.",
                     "\(routine) is racked and waiting.",
                     "The chamber's still lit — \(routine) next."]
        } else {
            lines = ["The chamber's still lit.",
                     "The chamber waits — enter when ready.",
                     "\(timeOfDay). The chamber holds."]
        }
        return lines[dayOfYear % lines.count]
    }

    // MARK: Streak — target-aware, shield-forgiving (StreakEngine.streakState)

    /// The week's real commitment: the user's explicit weekly frequency goal (the old
    /// hardcoded `2` ignored it). In weekday mode the schedule CAPS it — you can't owe
    /// five days when only three are scheduled — but scheduling six days never raises
    /// the ask above the goal: the mask says WHICH days, the goal says HOW MANY.
    private var streakTarget: Int {
        let goal = max(1, weeklyGoalTarget)
        if services.settings.scheduleMode == .weekday {
            let mask = Scheduling.orderedActive(routines).reduce(0) { $0 | $1.daysOfWeekMask }
            let scheduled = mask.nonzeroBitCount
            if scheduled > 0 { return min(goal, scheduled) }
        }
        return goal
    }

    private var streakState: StreakEngine.StreakState {
        StreakEngine.streakState(
            workoutDates: finishedWorkouts.map(\.startedAt),
            weeklyTarget: streakTarget,
            calendar: Self.isoCalendar,
            asOf: .now
        )
    }

    private var streakWeeks: Int { streakState.weeks }

    /// Short names of the scheduled weekdays for the streak sheet's caption —
    /// Monday-first, matching the ISO weeks the streak itself counts in.
    private var scheduledDayNames: [String] {
        let mask = Scheduling.orderedActive(routines).reduce(0) { $0 | $1.daysOfWeekMask }
        return (0..<7).compactMap { day in
            TrainDays.isSet(mask, day: day) ? TrainDays.shortNames[day].uppercased() : nil
        }
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
            .buttonStyle(PressableSlabStyle(haptic: .light))
            .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Quick start a workout")
            if todaysRoutine != nil {
                // Ghost HUD control — the session's WARM-UP pill grammar, not a bare link.
                Button {
                    session.quickStart()
                } label: {
                    Text("QUICK START")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.heroCyan)
                        .frame(minWidth: 150, minHeight: 36)
                        .background {
                            Capsule().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableSlabStyle(haptic: .light))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var launchCardLabel: some View {
        RealmDoorwayCard(asset: launchRealmAsset,
                         emphasized: true,
                         height: services.progression.snapshot?.restedBonusActive == true ? 148 : 124) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(launchEyebrow, tint: SettColor.heroCyan)
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
        } accessory: {
            playDisc
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "NEXT DIRECTIVE · <why now>": the weekday it fires on, or its slot in the
    /// rotation cycle. Quick Start has no schedule to cite, so no suffix.
    private var launchEyebrow: String {
        guard let routine = todaysRoutine else { return "NEXT DIRECTIVE" }
        switch services.settings.scheduleMode {
        case .weekday:
            return "NEXT DIRECTIVE · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())"
        case .rotation:
            // Same position math as the Train tab's rotation rows — the two surfaces
            // must never disagree about where the cycle stands.
            let order = Scheduling.orderedActive(routines)
            let pos = (order.firstIndex { $0.id == routine.id } ?? 0) + 1
            return "NEXT DIRECTIVE · CYCLE \(pos)/\(order.count)"
        }
    }

    /// The cyan play disc both doorway cards dock as their trailing accessory.
    private var playDisc: some View {
        ZStack {
            Circle()
                .fill(SettColor.heroCyan)
                .frame(width: 54, height: 54)
                .shadow(color: SettColor.heroCyan.opacity(0.5), radius: 7, y: 2)
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SettColor.etch)
                .offset(x: 2)
        }
        .accessibilityHidden(true)
    }

    /// The realm behind the launch card: the routine's own domain if it has one. When it
    /// doesn't, we deliberately pick a realm OTHER than the home-hero sky, so the card and
    /// the header never render the same backdrop (they read as two places, not a smear).
    private var launchRealmAsset: String {
        if let raw = todaysRoutine?.domainRaw {
            return ChamberBackground.resolve(raw).assetName
        }
        let home = ChamberBackground.resolve(services.settings.chamberBackground)
        let preferred: [ChamberBackground] = [.nebula, .storm, .aurora, .volcanic, .sanctuary, .white]
        return (preferred.first { $0 != home } ?? .nebula).assetName
    }

    private var launchSubline: String {
        if let routine = todaysRoutine {
            let count = routine.orderedExercises.count
            return "\(count) EXERCISE\(count == 1 ? "" : "S")"
        }
        return "EMPTY CHAMBER — LOG AS YOU GO"
    }

    /// The rested-bonus mechanic was computed but never shown. Surface it: after a
    /// full rest day the next session is surged — its volume counts ×1.25 inside the
    /// scanner window. Cyan (ki), not gold.
    private var restedChip: some View {
        StatusChip("SURGE ARMED · REST BANKED", tint: SettColor.heroCyan, icon: "bolt.fill")
            .accessibilityLabel("Rested surge armed. This session's volume counts extra in the scanner.")
    }

    /// Day zero's launch card wears the same chamber-art doorway as every other day —
    /// the post-onboarding home continues the pitch instead of dropping to a stock card.
    private var firstRunCard: some View {
        Button {
            session.quickStart()
        } label: {
            RealmDoorwayCard(asset: ChamberBackground.resolve(services.settings.chamberBackground).assetName,
                             emphasized: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("FIRST DIRECTIVE", tint: SettColor.heroCyan)
                    Text("Enter the chamber")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    Text("YOUR TRAINING ARC STARTS HERE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.75))
                }
            } accessory: {
                playDisc
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("Start your first workout")
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
                    .foregroundStyle(SettColor.bone)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
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
                Eyebrow("RECENT")
                Spacer()
                NavigationLink("All Workouts") {
                    HistoryListView()
                }
                .font(.subheadline.weight(.semibold))
            }
            if finishedWorkouts.isEmpty {
                Text("No workouts yet — your history writes itself.")
                    .font(.subheadline)
                    .foregroundStyle(SettColor.ash)
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
            } else {
                // Fixed 40pt ghost slot so empty workouts don't break the row grid.
                SettSigil(size: 22, color: SettColor.iron.opacity(0.6))
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(SettColor.ash)
            }
            Spacer()
            Text(WorkoutFormat.duration(workout.durationSeconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(SettColor.ash)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(SettColor.iron)
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
