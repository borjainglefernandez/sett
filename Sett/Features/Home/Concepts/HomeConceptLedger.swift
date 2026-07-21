import SwiftUI
import SwiftData
import SettCore

// MARK: - Concept 4 — "LEDGER" (minimal-first)
//
// Radical quiet. One number, one sentence, one action — the confidence to show
// almost nothing. The canvas is a near-black void with a whisper of the user's
// realm hue; the Power Level lands in the center like a fine watch dial's single
// complication, a priority-ladder sentence beneath it, a hair-thin week meter far
// below, and ONE action bar at the bottom. Everything else lives behind a swipe:
// THE LEDGER, a receipt-grammar sheet of this week's lines.
//
// SIGNATURE: the numeral SETTLES on appear — lands with mass (tiny overshoot +
// one soft haptic), then is utterly still. The sentence types in quietly after.
// Nothing loops. The stillness is the signature.
struct HomeConceptLedgerView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var frequencyGoals: [Goal]

    @State private var isShowingLedger = false
    @State private var isShowingStreak = false

    // The settle entrance — one shot, then stillness.
    @State private var numeralLanded = false
    @State private var supportRevealed = false
    @State private var typedSentence = ""

    init() {
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        let finishedSort = [SortDescriptor(\Workout.startedAt, order: .reverse)]
        _finishedWorkouts = Query(filter: finishedFilter, sort: finishedSort)

        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])

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
        ZStack {
            // The void at its darkest: the dungeon backdrop with a whisper of the
            // user's realm hue in the corners, then dimmed a further step so the
            // gold numeral is the single light source on screen.
            DungeonBackground(realmTint: realmHue)
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                centerBlock
                Spacer(minLength: 0)
                weekMeter
                    .padding(.bottom, 44)
                chevronWhisper
                    .padding(.bottom, 14)
                actionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 84) // clears the floating tab bar
            }
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        // Swipe up anywhere raises THE LEDGER (the chevron whisper is the same door).
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    if value.translation.height < -60, abs(value.translation.width) < 90 {
                        openLedger()
                    }
                }
        )
        .task { await runEntrance() }
        // Data moved under us (a session sealed, a recompute landed): the sentence
        // swaps directly — the typewriter is an entrance beat, never a re-run.
        .onChange(of: contextSentence) { _, sentence in
            if numeralLanded { typedSentence = sentence }
        }
        .sheet(isPresented: $isShowingLedger) {
            LedgerReceiptSheet(
                weekCaption: weekCaption,
                sessionsThisWeek: sessionsThisWeek,
                pace: services.progression.trailingWeeklyPace,
                plDeltaThisWeek: services.progression.plDeltaThisWeek,
                powerLevel: services.progression.snapshotPowerLevel,
                rivalGap: services.progression.effectiveRival.pl - services.progression.snapshotPowerLevel,
                surgeArmed: services.progression.snapshot?.restedBonusActive == true,
                unit: services.settings.unit,
                streakState: streakState,
                scheduleMode: services.settings.scheduleMode,
                scheduledDays: scheduledDayNames,
                plMultiplier: services.progression.snapshot?.consistencyMultiplier,
                daysSinceLastWorkout: daysSinceLastWorkout
            )
        }
        .sheet(isPresented: $isShowingStreak) {
            StreakSheet(state: streakState,
                        mode: services.settings.scheduleMode,
                        scheduledDays: scheduledDayNames,
                        plMultiplier: services.progression.snapshot?.consistencyMultiplier,
                        daysSinceLastWorkout: daysSinceLastWorkout)
        }
    }

    // MARK: Center — the sacred number, at its most sacred

    /// The most reverent rendering of the Power Level anywhere in the app: 96pt
    /// engraved gold over the void, the maker's-mark sigil above, the form word in
    /// tiny wide-tracked cyan mono beneath, then the one sentence.
    private var centerBlock: some View {
        let pl = services.progression.snapshotPowerLevel
        let form = UserForm.form(forPL: pl)
        return VStack(spacing: 0) {
            VStack(spacing: 16) {
                SettSigil(size: 15, color: SettColor.saiyanGold.opacity(0.5))
                Text("\(pl)")
                    .font(PowerFont.xl(96).italic())
                    .monospacedDigit()
                    .foregroundStyle(Aura.gold)
                    // The engraved cut at dial scale — PowerNumeral's hard outline,
                    // widened for the 96pt face.
                    .shadow(color: SettColor.etch, radius: 0, x: 1.5, y: 1.5)
                    .shadow(color: SettColor.etch, radius: 0, x: -1.5, y: 1.5)
                    .auraGlow(SettColor.saiyanGold, radius: 18)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 28)
                    .contentTransition(.numericText(value: Double(pl)))
                    .animation(.snappy(duration: 0.4), value: pl)
                Text(form.title)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .kerning(4)
                    .foregroundStyle(SettColor.heroCyan)
            }
            .scaleEffect(numeralLanded ? 1 : 1.12)
            .opacity(numeralLanded ? 1 : 0)

            // The one sentence. A hidden copy of the full line reserves the final
            // frame so the canvas never shifts while the typewriter runs.
            ZStack {
                Text(contextSentence).hidden()
                Text(typedSentence.isEmpty ? " " : typedSentence)
                    .frame(maxWidth: .infinity)
            }
            .font(.callout)
            .foregroundStyle(SettColor.bone)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 40)
            .padding(.top, 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power level \(pl), \(form.title.capitalized). \(contextSentence)")
    }

    /// The priority ladder — exactly one line wins, terse, zero hype.
    private var contextSentence: String {
        let pl = services.progression.snapshotPowerLevel
        guard !finishedWorkouts.isEmpty else { return "The chamber waits. Begin." }
        if trainedToday {
            if let delta = todaysPLDelta, delta > 0 {
                return "Sealed. +\(delta.formatted()) PL banked."
            }
            return "Sealed. The chamber cools."
        }
        if services.progression.snapshot?.restedBonusActive == true {
            return "Rest banked — today counts ×1.25."
        }
        if let routine = todaysRoutine {
            if let mins = typicalRoutineMinutes(routine) {
                return "\(routine.name) waits · ~\(mins) min."
            }
            return "\(routine.name) waits."
        }
        if isRestDay { return "Rest day. The chamber holds." }
        let gap = services.progression.effectiveRival.pl - pl
        if abs(gap) < 300 {
            return gap >= 0 ? "Vexeth: \(gap.formatted()) ahead."
                            : "Vexeth: \(abs(gap).formatted()) behind."
        }
        return "The chamber holds."
    }

    // MARK: Week meter — seven one-point ticks, floating far beneath

    /// The only other mark on the canvas: Monday→Sunday as hair-thin ticks, trained
    /// days lit ki-cyan, today a breath taller. It is the streak surface — tap for
    /// the full rules, shields, and this week's target.
    private var weekMeter: some View {
        Button {
            isShowingStreak = true
            Haptics.light()
        } label: {
            HStack(spacing: 7) {
                ForEach(0 ..< 7, id: \.self) { day in
                    Capsule()
                        .fill(tickColor(day))
                        .frame(width: 22, height: day == todayIndex ? 2 : 1)
                }
            }
            .padding(.vertical, 14) // whisper visuals, honest tap target
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(supportRevealed ? 1 : 0)
        .accessibilityLabel(weekMeterAccessibility)
        .accessibilityHint("Shows streak rules and this week's progress")
    }

    private func tickColor(_ day: Int) -> Color {
        if trainedDaysThisWeek.contains(day) { return SettColor.heroCyan.opacity(0.9) }
        if day == todayIndex { return SettColor.ash.opacity(0.6) }
        return SettColor.iron.opacity(0.35)
    }

    private var weekMeterAccessibility: String {
        let days = trainedDaysThisWeek.count
        var label = "\(days) of \(streakTarget) days trained this week"
        if streakState.weeks > 0 { label += ", \(streakState.weeks) week streak" }
        if streakState.shields > 0 {
            label += ", \(streakState.shields) shield\(streakState.shields == 1 ? "" : "s") banked"
        }
        return label
    }

    // MARK: Chevron whisper — the door to THE LEDGER

    private var chevronWhisper: some View {
        Button {
            openLedger()
        } label: {
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SettColor.ash.opacity(0.55))
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(supportRevealed ? 1 : 0)
        .accessibilityLabel("Open the ledger")
        .accessibilityHint("This week's lines — sessions, sets, streak, Vexeth")
    }

    private func openLedger() {
        Haptics.light()
        isShowingLedger = true
    }

    // MARK: Action bar — the only strong color block

    /// One full-width bar. Scouter-green fill when a session should start (the day's
    /// routine, or an empty chamber when nothing is scheduled); after sealing or on a
    /// planned rest day it recedes to a ghost LOG.
    @ViewBuilder
    private var actionBar: some View {
        if !trainedToday && !isRestDay {
            Button {
                startPrimary()
            } label: {
                Text(startLabel)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(SettColor.etch)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(TimeChamber.scouterGreen,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: TimeChamber.scouterGreen.opacity(0.3), radius: 10, y: 2)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableSlabStyle(haptic: .light))
            .opacity(supportRevealed ? 1 : 0)
            .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Start a workout")
        } else {
            Button {
                session.quickStart()
            } label: {
                Text("LOG")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(SettColor.ash)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(SettColor.cardBorder, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableSlabStyle(haptic: .light))
            .opacity(supportRevealed ? 1 : 0)
            .accessibilityLabel("Log a workout")
        }
    }

    private var startLabel: String {
        guard let routine = todaysRoutine else { return "BEGIN" }
        return "BEGIN · \(routine.name.uppercased())"
    }

    private func startPrimary() {
        if let routine = todaysRoutine { session.start(routine: routine) }
        else { session.quickStart() }
    }

    // MARK: The settle (signature motion — one shot, then stillness)

    /// Numeral lands with mass (spring overshoot + one soft haptic at touchdown),
    /// the quiet chrome fades up, then the sentence types in. Reduce Motion: a
    /// plain fade, the sentence set whole. Total stagger stays under ~600 ms.
    @MainActor
    private func runEntrance() async {
        guard !numeralLanded else {
            typedSentence = contextSentence
            return
        }
        let sentence = contextSentence
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.35)) {
                numeralLanded = true
                supportRevealed = true
            }
            typedSentence = sentence
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { numeralLanded = true }
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }
        Haptics.light() // the soft touchdown
        withAnimation(.easeOut(duration: 0.5)) { supportRevealed = true }
        try? await Task.sleep(for: .milliseconds(140))
        for index in sentence.indices {
            guard !Task.isCancelled else { return }
            typedSentence = String(sentence[...index])
            try? await Task.sleep(for: .milliseconds(14))
        }
        typedSentence = sentence
    }

    // MARK: Derivations (mirroring the classic Home — never faked)

    /// The routine you'd start now — today's weekday routine, or the rotation's next up.
    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
    }

    private var weeklyGoalTarget: Int {
        frequencyGoals.first?.targetValue ?? 3
    }

    /// The week's real commitment: the explicit weekly goal, capped by the weekday
    /// schedule when one exists (you can't owe five days when three are scheduled).
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

    private var trainedToday: Bool { trainedDaysThisWeek.contains(todayIndex) }

    /// A weekday-mode rest day: nothing scheduled today, but routines DO exist.
    private var isRestDay: Bool {
        services.settings.scheduleMode == .weekday
            && todaysRoutine == nil
            && !Scheduling.orderedActive(routines).isEmpty
    }

    /// Sessions logged this ISO week (cheap — a filter over the query result).
    private var sessionsThisWeek: Int {
        guard let week = Self.isoCalendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return finishedWorkouts.filter { week.contains($0.startedAt) }.count
    }

    /// Today's ΔPL — the jump from the previous training day's landing to now. Reads
    /// the in-memory trajectory (not SwiftData), so it's safe in `body`.
    private var todaysPLDelta: Int? {
        let history = services.progression.snapshot?.powerLevelHistory ?? []
        guard history.count >= 2 else { return nil }
        return history[history.count - 1].pl - history[history.count - 2].pl
    }

    /// The typical wall-clock length of this routine, from its own finished sessions.
    /// nil until two real sessions exist; sub-5-minute blips are ignored.
    private func typicalRoutineMinutes(_ routine: Routine) -> Int? {
        let seconds = finishedWorkouts.compactMap { workout -> Int? in
            guard workout.routineID == routine.id, let ended = workout.endedAt else { return nil }
            let active = Int(ended.timeIntervalSince(workout.startedAt)) - workout.pausedSeconds
            return active > 300 ? active : nil
        }
        guard seconds.count >= 2 else { return nil }
        return max(1, Int((Double(seconds.reduce(0, +)) / Double(seconds.count) / 60).rounded()))
    }

    /// Short names of the scheduled weekdays for the streak sheet's caption.
    private var scheduledDayNames: [String] {
        let mask = Scheduling.orderedActive(routines).reduce(0) { $0 | $1.daysOfWeekMask }
        return (0..<7).compactMap { day in
            TrainDays.isSet(mask, day: day) ? TrainDays.shortNames[day].uppercased() : nil
        }
    }

    private var daysSinceLastWorkout: Int? {
        guard let last = finishedWorkouts.first?.startedAt else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: last),
                                  to: cal.startOfDay(for: .now)).day
    }

    /// "WK 30 · JUL 20 – JUL 26" — the receipt's dateline.
    private var weekCaption: String {
        let cal = Self.isoCalendar
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return "" }
        let style = Date.FormatStyle().month(.abbreviated).day()
        let end = week.end.addingTimeInterval(-1)
        return "WK \(cal.component(.weekOfYear, from: .now)) · \(week.start.formatted(style)) – \(end.formatted(style))"
            .uppercased()
    }

    /// A whisper of the chosen realm's hue for the void's dark corners — the one
    /// place this concept admits color beyond the number, the ki, and the bar.
    private var realmHue: Color {
        switch ChamberBackground.resolve(services.settings.chamberBackground) {
        case .nebula: TimeChamber.indigo
        case .white: TimeChamber.iceBlue
        case .volcanic: Color(dynamicLight: 0xFF7A3C, dark: 0xFF7A3C)
        case .storm: TimeChamber.scouterSteel
        case .aurora: TimeChamber.teal
        case .sanctuary: Color(dynamicLight: 0xC79A4B, dark: 0xC79A4B)
        }
    }
}

// MARK: - THE LEDGER (receipt-grammar sheet: this week's lines, strict mono)

/// The details on demand: sessions, sets, tonnage, ΔPL cadence, streak + shields,
/// the rival gap, and a volume-zones summary — printed like a till receipt with
/// dot leaders and dashed rules. The set/tonnage/zone lines are a SwiftData
/// relationship walk, so they're computed once in a task on open (never in `body`,
/// per the CPU traps) and print "—" until the ink dries.
private struct LedgerReceiptSheet: View {
    let weekCaption: String
    let sessionsThisWeek: Int
    let pace: Int
    let plDeltaThisWeek: Int?
    let powerLevel: Int
    let rivalGap: Int          // rival PL − user PL (positive = Vexeth ahead)
    let surgeArmed: Bool
    let unit: WeightUnit
    let streakState: StreakEngine.StreakState
    let scheduleMode: ScheduleMode
    let scheduledDays: [String]
    let plMultiplier: Double?
    let daysSinceLastWorkout: Int?

    @Environment(\.modelContext) private var modelContext
    @State private var stats: WeekStats?
    @State private var isShowingStreak = false

    private struct WeekStats {
        let sets: Int
        let tonnageGrams: Int
        let zonesInSweet: Int
        let zonesBuilding: Int
    }

    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                rule
                receiptRow("SESSIONS", "\(sessionsThisWeek)")
                receiptRow("SETS", stats.map { "\($0.sets) WORKING" } ?? "—")
                receiptRow("TONNAGE", tonnageValue)
                receiptRow("CADENCE", pace > 0 ? "+\(pace.formatted()) PL/WK" : "—")
                receiptRow("THIS WEEK", thisWeekValue, tint: thisWeekTint)
                if surgeArmed {
                    receiptRow("SURGE", "ARMED ×1.25", tint: SettColor.heroCyan)
                }
                rule
                streakRow
                receiptRow("VEXETH", rivalValue, tint: SettColor.villainCrimson)
                receiptRow("VOLUME", volumeValue)
                rule
                receiptRow("CARRIED FWD", "\(powerLevel.formatted()) PL")
                perforation
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .materialize()
        }
        .scrollIndicators(.hidden)
        .background(DungeonBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { loadStats() }
        .sheet(isPresented: $isShowingStreak) {
            StreakSheet(state: streakState,
                        mode: scheduleMode,
                        scheduledDays: scheduledDays,
                        plMultiplier: plMultiplier,
                        daysSinceLastWorkout: daysSinceLastWorkout)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("THE LEDGER")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(4)
                .foregroundStyle(SettColor.bone)
            Text(weekCaption)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    // MARK: Lines

    private var tonnageValue: String {
        guard let stats else { return "—" }
        guard stats.tonnageGrams > 0 else { return "0 \(unit.symbol.uppercased())" }
        return "\(WeightFormat.compactTonnage(grams: stats.tonnageGrams, unit: unit)) \(unit.symbol.uppercased())"
    }

    private var thisWeekValue: String {
        guard let delta = plDeltaThisWeek else { return "—" }
        return "\(delta >= 0 ? "+" : "")\(delta.formatted()) PL"
    }

    /// The user's own delta wears deltaInk — a down-week is a toll, never an alarm.
    private var thisWeekTint: Color {
        plDeltaThisWeek.map { SettColor.deltaInk($0) } ?? SettColor.ash
    }

    private var rivalValue: String {
        if rivalGap > 0 { return "\(rivalGap.formatted()) AHEAD" }
        if rivalGap < 0 { return "\(abs(rivalGap).formatted()) BEHIND YOU" }
        return "DEAD LEVEL"
    }

    private var volumeValue: String {
        guard let stats else { return "—" }
        guard stats.sets > 0 else { return "NO SETS YET" }
        return "\(stats.zonesInSweet) IN ZONE · \(stats.zonesBuilding) BUILDING"
    }

    private var streakValue: String {
        let shields = streakState.shields
        return "\(streakState.weeks) WK · \(shields) SHIELD\(shields == 1 ? "" : "S")"
    }

    /// The one interactive line — the streak opens its own sheet.
    private var streakRow: some View {
        Button {
            isShowingStreak = true
            Haptics.light()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                rowLabel("STREAK")
                dotLeader
                rowValue(streakValue, tint: SettColor.heroCyan)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SettColor.iron)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Streak: \(streakState.weeks) weeks, \(streakState.shields) shields banked")
        .accessibilityHint("Shows streak rules and this week's progress")
    }

    // MARK: Receipt grammar

    private func receiptRow(_ label: String, _ value: String,
                            tint: Color = SettColor.bone) -> some View {
        HStack(alignment: .center, spacing: 8) {
            rowLabel(label)
            dotLeader
            rowValue(value, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .kerning(1)
            .foregroundStyle(SettColor.ash)
            .layoutPriority(1)
    }

    private func rowValue(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .layoutPriority(1)
    }

    /// The dotted run between a label and its figure — the receipt's connective tissue.
    private var dotLeader: some View {
        LedgerRuleLine()
            .stroke(SettColor.iron.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// A dashed section rule — the tear line between blocks.
    private var rule: some View {
        LedgerRuleLine()
            .stroke(SettColor.iron.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .frame(height: 1)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    private var perforation: some View {
        Text("· · · · · · · · · · · ·")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(SettColor.iron.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }

    // MARK: Stats (the relationship walk — task-only, per the CPU traps)

    @MainActor
    private func loadStats() {
        let samples = SampleExtractor.setSamples(context: modelContext)
        guard let week = Self.isoCalendar.dateInterval(of: .weekOfYear, for: .now) else { return }
        var sets = 0
        var tonnage = 0
        var counts: [Muscle: Int] = [:]
        for sample in samples where !sample.isWarmup && week.contains(sample.completedAt) {
            sets += 1
            tonnage += sample.weightGrams * sample.reps
            counts[sample.muscle, default: 0] += 1
        }
        var inSweet = 0
        var building = 0
        for muscle in Muscle.volumeGroups {
            guard let landmarks = VolumeLandmarks.landmarks(for: muscle),
                  let count = counts[muscle], count > 0 else { continue }
            if count >= landmarks.sweetLow && count <= landmarks.sweetHigh {
                inSweet += 1
            } else if count >= landmarks.floor && count < landmarks.sweetLow {
                building += 1
            }
        }
        stats = WeekStats(sets: sets, tonnageGrams: tonnage,
                          zonesInSweet: inSweet, zonesBuilding: building)
    }
}

/// A single horizontal line, stroked dashed for the receipt's rules and leaders.
private struct LedgerRuleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
