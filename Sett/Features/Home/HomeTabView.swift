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
    /// Today's total working tonnage (grams), cached for the SEALED hero — a SwiftData
    /// relationship walk, so it's computed in a task, never in `body`. nil until loaded.
    @State private var sealedTonnageGrams: Int?
    /// Armed once when a shield absorbed a missed week since the last Home open — leads
    /// the next open with a one-time banner, then dismisses.
    @State private var shieldSpentAbsorbed = 0
    @State private var isShowingShieldBanner = false
    /// One-shot flame-flare on the streak chip the moment the week seals.
    @State private var chipFlareScale: CGFloat = 1

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
                    // ONE stable stack. The primary action (the doorway hero) never
                    // migrates: its FACE changes with the day, its slot never does.
                    // header → crest → transient banners → doorway → week card →
                    // bodyweight strip → insight → recent.
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        powerCrest
                        // Transient one-time beats live between the crest and the doorway,
                        // so the doorway below them holds its slot no matter which fire.
                        if let form = services.progression.pendingAscension {
                            // Persistent ascension beat — a Form crossing that landed via a
                            // recompute or between sessions still gets its banner. The store
                            // is the single source of truth, so acknowledging clears Power too.
                            LevelUpBanner(form: form) {
                                withAnimation(.snappy) { services.progression.acknowledgeAscension() }
                            }
                        }
                        if isShowingShieldBanner {
                            shieldSpentBanner
                        }
                        if !finishedWorkouts.isEmpty, shouldShowWeeklyReading {
                            weeklyReadingCard
                        }
                        if session.rotationCycleSealed {
                            rotationSealBanner
                        }
                        // The doorway — one ~170pt realm-art card, three faces (next
                        // directive / sealed / rest), always in this slot.
                        heroCard
                        // The one weekly card — day slots + counters + net, merged.
                        if !finishedWorkouts.isEmpty {
                            SevenSlotBurstRow(trainedDays: trainedDaysThisWeek,
                                              goalTarget: weeklyGoalTarget,
                                              streakWeeks: streakWeeks)
                        }
                        // The day's NON-workout asks (log bodyweight, later sleep/rest).
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
            // The SEALED hero's tonnage is a relationship walk — done here, cached in
            // @State, re-run when a workout lands (never in `body`, per the CPU traps).
            .task(id: finishedWorkouts.count) { loadSealedSlab() }
            .onAppear { armShieldBannerIfNeeded() }
            // The moment the week hits target, flare the chip (the week card runs its
            // own cyan slot-sweep off the same crossing). Live transitions only.
            .onChange(of: trainedDaysThisWeek.count) { oldCount, newCount in
                if oldCount < streakTarget && newCount >= streakTarget { flareChip() }
            }
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
                            plMultiplier: services.progression.snapshot?.consistencyMultiplier,
                            daysSinceLastWorkout: daysSinceLastWorkout)
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
        .frame(height: 400)
        .frame(maxWidth: .infinity)
        .clipped()
        .opacity(0.45)
        // Fade in from the very top (no hard seam under the nav bar), then HOLD the sky
        // ~0.65 bright down past the crest before it fades — so the gold power level
        // floats in the chamber sky instead of on flat black, and the doorway below
        // still meets void.
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .white, location: 0.2),
                                   .init(color: .white.opacity(0.65), location: 0.72),
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
                            if !trainedDaysThisWeek.isEmpty, let delta = services.progression.plDeltaThisWeek {
                                // Week-so-far ΔPL — momentum, not reward, so it never
                                // wears gold: positive green, negative quiet ash. Gated to
                                // weeks with a logged session: before the first set lands the
                                // rolling window only decays, so an ungated Monday read "-72".
                                Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) THIS WEEK")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .kerning(1)
                                    .foregroundStyle(delta >= 0 ? SettColor.positive : SettColor.ash)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            } else {
                                // No session yet this week: the chase, not a phantom loss —
                                // the peak to reclaim, or the pips to the next form.
                                Text(crestChaseLine(pl: pl))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .kerning(1)
                                    .foregroundStyle(SettColor.ash)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
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
                if !trainedDaysThisWeek.isEmpty, let delta = services.progression.plDeltaThisWeek {
                    label += delta == 0 ? ", no change this week"
                                        : ", \(delta > 0 ? "up" : "down") \(abs(delta)) this week"
                } else {
                    label += ", \(crestChaseLine(pl: pl).replacingOccurrences(of: "·", with: ","))"
                }
                return label
            }())
            .accessibilityHint("Shows how the power level works")
        }
    }

    // MARK: Header (date eyebrow + chips, then the greeting on its own row)

    /// Date eyebrow + streak chip on one row, greeting below. The training-phase badge
    /// used to live here too, but phase now has its home in Settings (TRAINING PHASE
    /// section) — the header just carries the date and the streak, breathing.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                        .uppercased())
                Spacer()
                streakChip
            }
            Text(greeting)
                .font(.largeTitle.bold())
                .foregroundStyle(SettColor.bone)
                // Two lines, not one: "The chamber's warm — Push Day waits." was
                // clipping the routine name even at 0.7 scale. Wrap instead of shrink.
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    /// The fire went cold but this user HAD a streak — the chip reads a rekindling
    /// state (ember flame + RELIGHT) rather than a cold "0 wk".
    private var isRekindleChip: Bool { streakWeeks == 0 && streakState.bestWeeks > 0 }

    /// The streak is now a control, not a caption — tap for the rules, this week's
    /// target, and the shields that keep a vacation from killing the fire. Shown from
    /// the very first workout (a 0-week streak with a session logged is a fire being
    /// lit, and the sheet explains how to keep it). The flame FLARES once the moment
    /// the week seals; when the fire is out it dims to an ember and reads RELIGHT.
    @ViewBuilder
    private var streakChip: some View {
        if streakWeeks > 0 || !finishedWorkouts.isEmpty {
            Button {
                isShowingStreak = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(SettColor.heroCyan.opacity(isRekindleChip ? 0.55 : 1))
                        .scaleEffect(chipFlareScale)
                    if isRekindleChip {
                        Text("RELIGHT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .kerning(0.5)
                            .lineLimit(1)
                    } else {
                        Text("\(streakWeeks) wk")
                            .monospacedDigit()
                            .lineLimit(1)
                    }
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
            .accessibilityLabel(streakChipAccessibility)
            .accessibilityHint("Shows streak rules and this week's progress")
        }
    }

    private var streakChipAccessibility: String {
        let shieldPart = streakState.shields > 0
            ? ", \(streakState.shields) shield\(streakState.shields == 1 ? "" : "s") banked" : ""
        if isRekindleChip {
            return "Streak cold, best \(streakState.bestWeeks) weeks, ready to relight\(shieldPart)"
        }
        return "\(streakWeeks) week streak\(shieldPart)"
    }

    /// One quick flame punch on the chip when the week first seals. Aligns with the
    /// week card's cyan slot-sweep (both key off the same trained-day transition);
    /// the haptic lives with the sweep so the chip flare stays silent. RM holds still.
    private func flareChip() {
        guard !reduceMotion else { return }
        chipFlareScale = 1.5
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { chipFlareScale = 1 }
    }

    // MARK: Weekly Power Reading (Monday's scouter report)

    /// Monday-only, dismissible per ISO week — the week opens with a reading, not a
    /// guilt trip: last week's ΔPL, the form target, the rival gap, the fire.
    private var shouldShowWeeklyReading: Bool {
        #if DEBUG
        if !(ProcessInfo.processInfo.environment["SETT_DEBUG_READING"] ?? "").isEmpty { return true }
        if UserDefaults.standard.bool(forKey: "sett.debug.forceReading") { return true }
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
        if !(ProcessInfo.processInfo.environment["SETT_DEBUG_READING"] ?? "").isEmpty
            || UserDefaults.standard.bool(forKey: "sett.debug.forceReading") {
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

    /// Today as 0 = Monday … 6 = Sunday.
    private var todayIndex: Int {
        (Self.isoCalendar.component(.weekday, from: .now) + 5) % 7
    }

    /// Today's work is already sealed — a session landed today.
    private var trainedToday: Bool { trainedDaysThisWeek.contains(todayIndex) }

    /// A weekday-mode rest day: nothing is scheduled today, but routines DO exist (a
    /// planned rest, not an empty app). Rotation always has a next-up, so it never rests.
    private var isRestDay: Bool {
        services.settings.scheduleMode == .weekday
            && todaysRoutine == nil
            && !Scheduling.orderedActive(routines).isEmpty
    }

    // MARK: The doorway hero (ONE card, three faces — its slot never moves)

    /// The routine you'd start now — today's weekday routine, or the rotation's next up.
    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
    }

    /// The doorway. One ~170pt realm-art card whose FACE changes with the day while its
    /// slot in the stack never does. First run → the first-directive doorway. Trained
    /// today → the SEALED trophy slab (evening home is a shelf, not another prompt). Rest
    /// day → the dimmed REST slab (a banked surge, not a nag). Otherwise → the NEXT
    /// DIRECTIVE doorway with the big play disc + docked quick-start ghost.
    @ViewBuilder
    private var heroCard: some View {
        if finishedWorkouts.isEmpty {
            firstRunCard
        } else if trainedToday {
            sealedHero
        } else if isRestDay {
            restHero
        } else {
            nextDirectiveHero
        }
    }

    private let heroHeight: CGFloat = 170

    // MARK: Face — NEXT DIRECTIVE (morning / not yet trained today)

    /// The next session as a doorway: routine name (.title2), the big play disc, the
    /// SURGE ARMED chip when a rest day banked the bonus, and the docked "or start empty"
    /// ghost. The whole card starts the routine (a real Button, with press feedback); the
    /// ghost is a sibling overlay button, so the two tap targets never nest.
    private var nextDirectiveHero: some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                startPrimary()
            } label: {
                RealmDoorwayCard(asset: launchRealmAsset, emphasized: true, height: heroHeight) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(launchEyebrow, tint: SettColor.heroCyan)
                        Text(todaysRoutine?.name ?? "Quick Start")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                        Text(launchSubline)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(.white.opacity(0.75))
                        if services.progression.snapshot?.restedBonusActive == true {
                            restedChip.padding(.top, 2)
                        }
                    }
                    // Top-align so the routine info sits up top and the bottom-leading
                    // ghost has clear air beneath it.
                    .frame(maxHeight: .infinity, alignment: .top)
                } accessory: {
                    playDisc
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableSlabStyle(haptic: .light))
            .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Quick start a workout")

            // Docked quick start — a small ghost text control, not a full-width 2nd CTA.
            // Only when there's a planned routine to start empty INSTEAD of.
            if todaysRoutine != nil {
                quickStartGhost
                    .padding(.leading, 18)
                    .padding(.bottom, 14)
            }
        }
    }

    private func startPrimary() {
        if let routine = todaysRoutine { session.start(routine: routine) }
        else { session.quickStart() }
    }

    // MARK: Face — SEALED (trained today: a trophy shelf, not a prompt)

    /// Same realm art, no play disc: today's ΔPL (gold if a gain, per the color law; ash
    /// otherwise) and the tonnage moved, with a quiet mono line naming the next session.
    private var sealedHero: some View {
        RealmDoorwayCard(asset: launchRealmAsset, emphasized: false, height: heroHeight) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("SEALED · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())",
                        tint: SettColor.heroCyan)
                if let delta = todaysPLDelta {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) ΔPL")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(delta > 0 ? SettColor.saiyanGold : SettColor.ash)
                        .shadow(color: .black.opacity(0.55), radius: 3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                if let grams = sealedTonnageGrams {
                    Text("\(WeightFormat.compactTonnage(grams: grams, unit: services.settings.unit)) \(services.settings.unit.symbol.uppercased()) MOVED")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.75))
                }
                if let next = nextSessionInfo {
                    Text("NEXT: \(next.name) · \(next.day)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } accessory: {
            // A quiet seal in place of the play disc — the evening chamber has cooled.
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(SettColor.heroCyan.opacity(0.85))
                .shadow(color: SettColor.heroCyan.opacity(0.4), radius: 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sealedAccessibility)
    }

    private var sealedAccessibility: String {
        var parts = ["Today's session sealed"]
        if let delta = todaysPLDelta {
            parts.append(delta == 0 ? "no power change"
                                    : "\(delta > 0 ? "up" : "down") \(abs(delta)) power level")
        }
        if let grams = sealedTonnageGrams {
            parts.append("\(WeightFormat.compactTonnage(grams: grams, unit: services.settings.unit)) \(services.settings.unit.symbol) moved")
        }
        if let next = nextSessionInfo { parts.append("next \(next.name), \(next.day)") }
        return parts.joined(separator: ", ")
    }

    // MARK: Face — REST DAY (a banked surge, not a nag)

    /// Dimmed realm art, the surge mechanic spelled out, quick start demoted to the ghost.
    private var restHero: some View {
        RealmDoorwayCard(asset: launchRealmAsset, emphasized: false, height: heroHeight) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("REST DAY · SURGE BANKS", tint: SettColor.heroCyan)
                Text("A full rest day arms tomorrow's session ×1.25")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                quickStartGhost.padding(.top, 2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } accessory: {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
        }
        // Dimmed art (desaturated + a hair darker); white text has no saturation to lose,
        // so it stays legible while the realm reads dormant.
        .saturation(0.65)
        .brightness(-0.04)
    }

    /// The docked quick start — a small cyan ghost text control ("or start empty"). Its
    /// own button (never nested inside the card button), never a full-width second CTA.
    private var quickStartGhost: some View {
        Button {
            session.quickStart()
        } label: {
            Text("or start empty")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.heroCyan)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("Start an empty workout")
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

    /// The cyan play disc the next-directive doorway docks as its trailing accessory —
    /// the Train tab's white play control, bumped to 64pt so it reads as THE action.
    private var playDisc: some View {
        ZStack {
            Circle()
                .fill(SettColor.heroCyan)
                .frame(width: 64, height: 64)
                .shadow(color: SettColor.heroCyan.opacity(0.5), radius: 8, y: 2)
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SettColor.etch)
                .offset(x: 2)
        }
        .accessibilityHidden(true)
    }

    /// The realm behind the doorway: the routine's own domain if it has one. When it
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

    /// The rested-bonus mechanic, surfaced: after a full rest day the next session is
    /// surged — its volume counts ×1.25 inside the scanner window. Cyan (ki), not gold.
    private var restedChip: some View {
        StatusChip("SURGE ARMED · REST BANKED", tint: SettColor.heroCyan, icon: "bolt.fill")
            .accessibilityLabel("Rested surge armed. This session's volume counts extra in the scanner.")
    }

    /// The next session the schedule points at — for the SEALED slab's forward look.
    /// Rotation: the next-up (the cursor has advanced past today's finished session).
    /// Weekday: scan forward up to a week for the next scheduled day.
    private var nextSessionInfo: (name: String, day: String)? {
        let active = Scheduling.orderedActive(routines)
        guard !active.isEmpty else { return nil }
        switch services.settings.scheduleMode {
        case .rotation:
            guard let next = Scheduling.nextRoutine(routines, settings: services.settings) else { return nil }
            return (next.name, "UP NEXT")
        case .weekday:
            let cal = Self.isoCalendar
            for offset in 1...7 {
                guard let date = cal.date(byAdding: .day, value: offset, to: .now) else { continue }
                let mondayIndex = (cal.component(.weekday, from: date) + 5) % 7
                if let routine = active.first(where: { ($0.daysOfWeekMask >> mondayIndex) & 1 == 1 }) {
                    return (routine.name, date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                }
            }
            return nil
        }
    }

    /// Today's ΔPL — the jump from the previous training day's landing to now. Reads the
    /// in-memory trajectory (not SwiftData), so it's safe in `body`. nil before two points.
    private var todaysPLDelta: Int? {
        let history = services.progression.snapshot?.powerLevelHistory ?? []
        guard history.count >= 2 else { return nil }
        return history[history.count - 1].pl - history[history.count - 2].pl
    }

    /// Days since the most recent logged workout — feeds the streak sheet's Reforged tease.
    private var daysSinceLastWorkout: Int? {
        guard let last = finishedWorkouts.first?.startedAt else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: .now)).day
    }

    /// Today's finished workout (latest one that started today), for the SEALED tonnage.
    private var todaysFinishedWorkout: Workout? {
        finishedWorkouts.first { Calendar.current.isDateInToday($0.startedAt) }
    }

    /// Cache today's working tonnage for the SEALED slab — a relationship walk, so it runs
    /// in a task and lands in @State, never in `body` (per the CPU traps).
    private func loadSealedSlab() {
        guard trainedToday, let workout = todaysFinishedWorkout else {
            sealedTonnageGrams = nil
            return
        }
        sealedTonnageGrams = workout.orderedExercises
            .flatMap { $0.orderedSets.filter { !$0.isWarmup } }
            .reduce(0) { $0 + $1.weightGrams * $1.reps }
    }

    /// The crest's chase line when there's no session this week to read a ΔPL from: the
    /// all-time peak to reclaim, else the pips to the next form. Same slot as the ΔPL.
    private func crestChaseLine(pl: Int) -> String {
        let peak = services.progression.snapshot?.allTimePeakPL ?? pl
        if peak > pl {
            return "PEAK \(peak.formatted()) · \((peak - pl).formatted()) TO RECLAIM"
        }
        let form = UserForm.form(forPL: pl)
        let next = UserForm.form(forPL: form.nextPL)
        return "\((form.nextPL - pl).formatted()) TO \(next.title)"
    }

    // MARK: Shield-spent banner (a shield absorbed a missed week — held the line)

    /// One-time, on the next Home open after a shield absorbed a missed week: a shield
    /// dropped since we last recorded the count, and a drop can only mean it was spent.
    /// First run just records the baseline (never fires retroactively).
    private func armShieldBannerIfNeeded() {
        let key = "sett.streak.shieldsSeen"
        let defaults = UserDefaults.standard
        let current = streakState.shields
        defer { defaults.set(current, forKey: key) }
        guard defaults.object(forKey: key) != nil else { return }
        let seen = defaults.integer(forKey: key)
        if current < seen {
            shieldSpentAbsorbed = seen - current
            withAnimation(.snappy) { isShowingShieldBanner = true }
        }
    }

    /// Reuses the rotation-seal banner grammar — cyan (the shield/streak are ki, never
    /// gold). Non-toxic: it CELEBRATES the shield holding the line, never scolds the miss.
    private var shieldSpentBanner: some View {
        Button {
            withAnimation(.snappy) { isShowingShieldBanner = false }
            Haptics.light()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SettColor.heroCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("SHIELD HELD THE LINE", tint: SettColor.heroCyan)
                    Text(shieldSpentCopy)
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
        .hudCard()
        .materialize()
        .accessibilityLabel("\(shieldSpentCopy). Dismisses this banner.")
    }

    private var shieldSpentCopy: String {
        let absorbed = max(1, shieldSpentAbsorbed)
        let lead = absorbed == 1 ? "One week absorbed" : "\(absorbed) weeks absorbed"
        return "\(lead) — \(streakWeeks) wk fire intact."
    }

    /// Day zero's doorway wears the same chamber-art card as every other day — the
    /// post-onboarding home continues the pitch instead of dropping to a stock card.
    private var firstRunCard: some View {
        Button {
            session.quickStart()
        } label: {
            RealmDoorwayCard(asset: ChamberBackground.resolve(services.settings.chamberBackground).assetName,
                             emphasized: true, height: heroHeight) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("FIRST DIRECTIVE", tint: SettColor.heroCyan)
                    Text("Enter the chamber")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    Text("YOUR TRAINING ARC STARTS HERE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } accessory: {
                // The empty chamber reads as an ember waiting to be lit — a soft ki
                // bloom breathes behind the play disc, not a dead control.
                playDisc
                    .background { IgnitionBloom() }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .materialize()
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

/// A soft heroCyan bloom that breathes behind the first-run play disc — the empty
/// Home reads as an ember waiting to be lit rather than dead. Cyan, not gold: this
/// is ki/action, not a reward. Reduce Motion holds a fixed static glow (no pulse).
private struct IgnitionBloom: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [SettColor.heroCyan.opacity(0.55), .clear],
                                 center: .center, startRadius: 0, endRadius: 58))
            .frame(width: 116, height: 116)
            .scaleEffect(reduceMotion ? 1 : (lit ? 1.1 : 0.82))
            .opacity(reduceMotion ? 0.5 : (lit ? 0.85 : 0.4))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}
