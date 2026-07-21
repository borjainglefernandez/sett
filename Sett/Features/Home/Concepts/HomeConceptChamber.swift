import SwiftUI
import SwiftData
import SettCore

// MARK: - HOME CONCEPT 3 — "CHAMBER" (the world IS the interface)
//
// A full-bleed realm scene under a dark vignette; the chamber DOOR is the start
// button; the stats are diegetic etchings on its frame. The power level floats
// in the sky as gold engraving; the streak burns in a sconce on the left jamb;
// the week's pips are carved down the right; Vexeth is a crimson glint on the
// far horizon. Tap the door and light floods from within before the session
// cover launches. Zelda-title-screen energy, Monument Valley restraint: the
// scene carries everything, the text budget stays under a sentence.
//
// Self-contained by design: every data derivation mirrors HomeTabView's (same
// queries, same engines) — duplicated here on purpose so the shared files stay
// owned by the integrator while five concepts build in parallel.

struct HomeConceptChamberView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var frequencyGoals: [Goal]

    @State private var isShowingStreak = false
    /// Entrance stagger token — sky, door, etchings rise in over ≤0.6 s.
    @State private var assembled = false
    /// The armed door's inner light breathes — opacity of one small gradient
    /// layer, never a shadow radius (CPU law).
    @State private var breathe = false
    /// 0…1 — the tap flare: light floods the arch before the session launches.
    @State private var flare: Double = 0
    /// Scale punch on the door during the flare.
    @State private var doorPunch: CGFloat = 1
    /// Debounce so a double-tap can't start two sessions mid-flare.
    @State private var opening = false

    init() {
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        _finishedWorkouts = Query(filter: finishedFilter,
                                  sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])

        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])

        let goalFilter = #Predicate<Goal> { $0.kindRaw == "frequency" && $0.isActive && $0.deletedAt == nil }
        _frequencyGoals = Query(filter: goalFilter)
    }

    /// Streaks and weekly pips use ISO weeks (Monday start), matching the engines.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    private static let doorWidth: CGFloat = 150
    private static let doorHeight: CGFloat = 228

    var body: some View {
        ZStack {
            ChamberRealmScene(asset: realmAsset)
            content
            // The launch wash — for one beat the door's light reaches the sky.
            Color.white.opacity(0.16 * flare)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(SettColor.screen)
        .onAppear(perform: enter)
        .sheet(isPresented: $isShowingStreak) {
            StreakSheet(state: streakState,
                        mode: services.settings.scheduleMode,
                        scheduledDays: scheduledDayNames,
                        plMultiplier: services.progression.snapshot?.consistencyMultiplier,
                        daysSinceLastWorkout: daysSinceLastWorkout)
        }
    }

    // MARK: Composition (sky → horizon → threshold)

    private var content: some View {
        VStack(spacing: 0) {
            skyBlock
                .padding(.top, 10)
                .modifier(ChamberRiseIn(shown: assembled, delay: 0))
            rivalGlint
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 28)
                .padding(.top, 16)
                .modifier(ChamberRiseIn(shown: assembled, delay: 0.22))
            Spacer(minLength: 10)
            doorBlock
                .modifier(ChamberRiseIn(shown: assembled, delay: 0.1))
            ghostLine
                .padding(.top, 8)
                .modifier(ChamberRiseIn(shown: assembled, delay: 0.22))
        }
        .padding(.bottom, 88) // the threshold clears the floating tab bar
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sky — the power level engraved in gold (the ONE gold-led element)

    @ViewBuilder
    private var skyBlock: some View {
        let pl = services.progression.snapshotPowerLevel
        VStack(spacing: 6) {
            if pl > 0 {
                SacredNumberView(value: pl, size: .xl)
                Text(UserForm.form(forPL: pl).title)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .kerning(5)
                    .foregroundStyle(.white.opacity(0.72))
                    .shadow(color: .black.opacity(0.7), radius: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                // Day zero: the sky holds a quiet sigil, not a fake zero.
                SettSigil(size: 26, color: SettColor.bone.opacity(0.55))
                Text("POWER UNREAD")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(.white.opacity(0.55))
                    .shadow(color: .black.opacity(0.7), radius: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pl > 0
            ? "Power level \(pl), \(UserForm.form(forPL: pl).title.capitalized)"
            : "Power level unread")
    }

    // MARK: Horizon — the crimson glint (the ONLY crimson, far from the gold sky)

    /// Vexeth's live gap vs the user. nil hides the glint (no PL to race yet).
    private var rivalGap: Int? {
        let pl = services.progression.snapshotPowerLevel
        guard pl > 0, services.progression.snapshot != nil else { return nil }
        return services.progression.effectiveRival.pl - pl
    }

    @ViewBuilder
    private var rivalGlint: some View {
        if let gap = rivalGap {
            HStack(spacing: 5) {
                Circle()
                    .fill(SettColor.villainCrimson)
                    .frame(width: 4, height: 4)
                    .shadow(color: SettColor.villainCrimson.opacity(0.9), radius: 3)
                Text(gap > 0 ? "VEXETH · \(gap.formatted()) AHEAD"
                             : "VEXETH · \(abs(gap).formatted()) BEHIND")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.villainCrimson.opacity(0.85))
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gap > 0 ? "Vexeth \(gap) power ahead"
                                        : "Vexeth \(abs(gap)) power behind you")
        }
    }

    // MARK: The door (frame etchings flanking, engraved lintel above)

    /// Which face the door wears today — the same day logic as classic Home's hero.
    private enum DoorFace { case first, directive, sealed, rest }

    private var face: DoorFace {
        if finishedWorkouts.isEmpty { return .first }
        if trainedToday { return .sealed }
        if isRestDay { return .rest }
        return .directive
    }

    /// Armed = tapping it starts the day's work and the inner light breathes.
    private var doorIsArmed: Bool { face == .directive || face == .first }

    private var surgeArmed: Bool {
        services.progression.snapshot?.restedBonusActive == true
    }

    private var doorBlock: some View {
        VStack(spacing: 12) {
            lintel
            HStack(alignment: .center, spacing: 18) {
                streakSconce
                door
                weekPips
            }
            // Light pooling on the threshold — static blur, never animated.
            Ellipse()
                .fill(SettColor.heroCyan.opacity(doorIsArmed ? 0.2 : 0.07))
                .frame(width: 128, height: 12)
                .blur(radius: 7)
                .padding(.top, -2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The engraved line above the arch — the door names its work, nothing more.
    private var lintel: some View {
        VStack(spacing: 6) {
            Text(lintelText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.82))
                .shadow(color: .black.opacity(0.75), radius: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 24)
            if face == .directive, surgeArmed {
                StatusChip("SURGE ARMED", tint: SettColor.heroCyan, icon: "bolt.fill")
            }
        }
        .accessibilityHidden(true) // the door button carries the full label
    }

    private var lintelText: String {
        switch face {
        case .first:
            return "FIRST DIRECTIVE"
        case .sealed:
            return "SEALED · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())"
        case .rest:
            return "REST DAY"
        case .directive:
            guard let routine = todaysRoutine else { return "EMPTY CHAMBER" }
            var line = routine.name.uppercased()
            if let mins = typicalRoutineMinutes(routine) { line += " · ~\(mins) MIN" }
            return line
        }
    }

    @ViewBuilder
    private var door: some View {
        if face == .sealed {
            // Sealed is a monument, not a control — the evening chamber cooled.
            doorBody
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(sealedAccessibility)
        } else {
            Button(action: openDoor) {
                doorBody
                    .contentShape(PortalArchShape())
            }
            .buttonStyle(PressableSlabStyle(haptic: nil)) // the flare owns the haptics
            .disabled(opening)
            .accessibilityLabel(doorAccessibility)
        }
    }

    private var doorBody: some View {
        ZStack {
            // Through the aperture: the SAME realm, but lit — brighter and more
            // saturated than the vignetted world outside the frame.
            Image(realmAsset)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.doorWidth, height: Self.doorHeight)
                .scaleEffect(1.35)
                .saturation(faceArt.saturation)
                .brightness(faceArt.brightness)
            if face == .sealed {
                Color.black.opacity(0.35) // the door has closed for the day
            } else if face == .rest {
                Color.black.opacity(0.25) // dormant, moonlit
            }
            innerLight
            faceContent
        }
        .frame(width: Self.doorWidth, height: Self.doorHeight)
        .clipShape(PortalArchShape())
        .overlay {
            // Outer jamb — carved stone hairline.
            PortalArchShape().stroke(.white.opacity(0.32), lineWidth: 1.5)
        }
        .overlay {
            // Inner hairline — cyan when armed (action), gold-kissed when sealed
            // (the day's reward), near-nothing when dormant.
            PortalArchShape().stroke(frameTint, lineWidth: 1).padding(4)
        }
        .overlay { flareOverlay }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8) // static — never animated
        .scaleEffect(doorPunch)
    }

    private var faceArt: (saturation: Double, brightness: Double) {
        switch face {
        case .directive, .first: (1.15, 0.05)
        case .sealed: (0.8, -0.04)
        case .rest: (0.55, -0.07)
        }
    }

    private var frameTint: Color {
        switch face {
        case .directive, .first: SettColor.heroCyan.opacity(0.55)
        case .sealed: SettColor.saiyanGold.opacity(0.35)
        case .rest: .white.opacity(0.12)
        }
    }

    /// The light inside the door. Armed: a white-cyan flood from the threshold
    /// that breathes (one small gradient layer's opacity — RM holds it still).
    /// Sealed/rest: a faint remainder so the aperture never reads dead.
    private var innerLight: some View {
        let base: Double = doorIsArmed ? 1 : (face == .sealed ? 0.24 : 0.16)
        return RadialGradient(
            colors: [.white.opacity(0.55), SettColor.heroCyan.opacity(0.32), .clear],
            center: UnitPoint(x: 0.5, y: 0.88),
            startRadius: 4, endRadius: Self.doorHeight * 0.8
        )
        .opacity(base * lightBreath)
        .allowsHitTesting(false)
    }

    private var lightBreath: Double {
        guard doorIsArmed else { return 1 }
        if reduceMotion { return 0.8 }
        return breathe ? 1.0 : 0.6
    }

    @ViewBuilder
    private var faceContent: some View {
        switch face {
        case .directive, .first:
            // The invite is the light itself; one word at the threshold. Etch ink
            // on the lit pool, per the ink rule for text on heroCyan.
            VStack {
                Spacer()
                Text("ENTER")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(SettColor.etch.opacity(0.78))
                    .padding(.bottom, 16)
            }
        case .sealed:
            // The wax over the arch — gold is sanctioned: the seal and ΔPL are
            // the day's REWARD (ash when flat, per the color law; never red).
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(SettColor.saiyanGold.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 56, height: 56)
                    SettSigil(size: 24, color: SettColor.saiyanGold)
                }
                .shadow(color: SettColor.saiyanGold.opacity(0.45), radius: 8)
                if let delta = todaysPLDelta {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) ΔPL")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(delta > 0 ? SettColor.saiyanGold : SettColor.ash)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        case .rest:
            // Dormant under the moon — the surge mechanic, spelled in four glyphs.
            VStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
                Text("SURGE BANKS ×1.25")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(color: .black.opacity(0.7), radius: 2)
            }
        }
    }

    /// The signature moment: on tap, light floods the arch (radial fill rising
    /// from the threshold) while the door punches forward — THEN the session
    /// cover takes over. A one-shot on a door-sized layer, never a loop.
    private var flareOverlay: some View {
        PortalArchShape()
            .fill(RadialGradient(
                colors: [.white.opacity(0.95), SettColor.heroCyan.opacity(0.55), .clear],
                center: UnitPoint(x: 0.5, y: 0.65),
                startRadius: 4, endRadius: Self.doorHeight * 0.9))
            .opacity(flare)
            .scaleEffect(0.75 + 0.35 * flare, anchor: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Sconces — the frame carries the stats

    /// Left jamb: the streak fire. Tap → the streak sheet (rules, shields, margin).
    private var streakSconce: some View {
        Button {
            Haptics.light()
            isShowingStreak = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    // A cold fire dims to an ember — remembered, not extinguished.
                    .foregroundStyle(SettColor.heroCyan.opacity(streakWeeks > 0 ? 1 : 0.45))
                    .shadow(color: SettColor.heroCyan.opacity(streakWeeks > 0 ? 0.6 : 0.2), radius: 4)
                Text("\(streakWeeks)")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                Text("WK")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 44)
            .padding(.vertical, 10)
            .background { Capsule().fill(.black.opacity(0.35)) }
            .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableSlabStyle(haptic: nil))
        .accessibilityLabel(streakAccessibility)
        .accessibilityHint("Shows streak rules and this week's progress")
    }

    private var streakAccessibility: String {
        let shieldPart = streakState.shields > 0
            ? ", \(streakState.shields) shield\(streakState.shields == 1 ? "" : "s") banked" : ""
        return "\(streakWeeks) week streak\(shieldPart)"
    }

    /// Right jamb: the week carved as seven pips, Monday-first. Lit = trained;
    /// the ring marks today.
    private var weekPips: some View {
        VStack(spacing: 7) {
            ForEach(0..<7, id: \.self) { day in
                ZStack {
                    Circle()
                        .fill(trainedDaysThisWeek.contains(day)
                              ? AnyShapeStyle(SettColor.heroCyan)
                              : AnyShapeStyle(.white.opacity(0.18)))
                        .frame(width: 6, height: 6)
                        .shadow(color: trainedDaysThisWeek.contains(day)
                                ? SettColor.heroCyan.opacity(0.8) : .clear, radius: 3)
                    if day == todayIndex {
                        Circle()
                            .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                            .frame(width: 11, height: 11)
                    }
                }
                .frame(width: 11, height: 11)
            }
        }
        .frame(width: 44)
        .padding(.vertical, 12)
        .background { Capsule().fill(.black.opacity(0.35)) }
        .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trainedDaysThisWeek.count) of \(streakTarget) days trained this week")
    }

    // MARK: Ghost — quick start stays one tap away on every face

    @ViewBuilder
    private var ghostLine: some View {
        if face == .directive, todaysRoutine != nil {
            ghostButton("or start empty")
        } else if face == .sealed {
            ghostButton("enter again")
        } else {
            // First-run / rest / no-routine: the door itself quick-starts.
            Color.clear.frame(height: 1)
        }
    }

    private func ghostButton(_ label: String) -> some View {
        Button {
            session.quickStart()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.heroCyan)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("Start an empty workout")
    }

    // MARK: Actions

    /// The door opens: rigid haptic on the latch, light floods (~0.3 s), the
    /// session starts under the flare's peak, then the scene settles for the
    /// return. Reduce Motion: a brief fade, then the launch — no flood, no punch.
    private func openDoor() {
        guard !opening else { return }
        opening = true
        Haptics.rigid()
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) { flare = 0.5 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                startPrimary()
                withAnimation(.easeOut(duration: 0.25)) { flare = 0 }
                opening = false
            }
            return
        }
        withAnimation(.easeIn(duration: 0.28)) { flare = 1 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) { doorPunch = 1.05 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            Haptics.medium()
            startPrimary()
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeOut(duration: 0.35)) {
                flare = 0
                doorPunch = 1
            }
            opening = false
        }
    }

    private func startPrimary() {
        if let routine = todaysRoutine { session.start(routine: routine) }
        else { session.quickStart() }
    }

    private func enter() {
        assembled = true // each block animates via its own ChamberRiseIn
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }

    // MARK: Accessibility for the door faces

    private var doorAccessibility: String {
        switch face {
        case .first:
            return "Enter the chamber. Starts your first workout"
        case .rest:
            return "Rest day, surge banks times 1.25. Starts an empty workout anyway"
        case .directive:
            if let routine = todaysRoutine {
                var label = "Start \(routine.name)"
                if let mins = typicalRoutineMinutes(routine) { label += ", about \(mins) minutes" }
                if surgeArmed { label += ", surge armed" }
                return label
            }
            return "Quick start a workout"
        case .sealed:
            return sealedAccessibility // unreachable (sealed isn't a button)
        }
    }

    private var sealedAccessibility: String {
        var parts = ["Today's session sealed"]
        if let delta = todaysPLDelta {
            parts.append(delta == 0 ? "no power change today"
                                    : "\(delta > 0 ? "up" : "down") \(abs(delta)) power today")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Derivations (mirroring HomeTabView — never fake a number)

    private var realmAsset: String {
        ChamberBackground.resolve(services.settings.chamberBackground).assetName
    }

    /// The routine you'd start now — today's weekday routine, or the rotation's next up.
    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
    }

    /// The typical wall-clock length of this routine, from its own finished sessions
    /// (active time — paused seconds subtracted). nil until two real sessions exist;
    /// sub-5-minute blips are ignored. (Mirrors HomeTabView.)
    private func typicalRoutineMinutes(_ routine: Routine) -> Int? {
        let seconds = finishedWorkouts.compactMap { workout -> Int? in
            guard workout.routineID == routine.id, let ended = workout.endedAt else { return nil }
            let active = Int(ended.timeIntervalSince(workout.startedAt)) - workout.pausedSeconds
            return active > 300 ? active : nil
        }
        guard seconds.count >= 2 else { return nil }
        return max(1, Int((Double(seconds.reduce(0, +)) / Double(seconds.count) / 60).rounded()))
    }

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

    private var trainedToday: Bool { trainedDaysThisWeek.contains(todayIndex) }

    /// A weekday-mode rest day: nothing scheduled today, but routines DO exist.
    private var isRestDay: Bool {
        services.settings.scheduleMode == .weekday
            && todaysRoutine == nil
            && !Scheduling.orderedActive(routines).isEmpty
    }

    /// The week's real commitment: the weekly goal, capped by the schedule mask
    /// in weekday mode (you can't owe five days when three are scheduled).
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

    /// Short names of the scheduled weekdays for the streak sheet's caption.
    private var scheduledDayNames: [String] {
        let mask = Scheduling.orderedActive(routines).reduce(0) { $0 | $1.daysOfWeekMask }
        return (0..<7).compactMap { day in
            TrainDays.isSet(mask, day: day) ? TrainDays.shortNames[day].uppercased() : nil
        }
    }

    /// Days since the most recent logged workout — the streak sheet's Reforged tease.
    private var daysSinceLastWorkout: Int? {
        guard let last = finishedWorkouts.first?.startedAt else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: last),
                                  to: cal.startOfDay(for: .now)).day
    }

    /// Today's ΔPL — the jump from the previous training day's landing to now.
    /// Reads the in-memory trajectory (not SwiftData), so it's safe in `body`.
    private var todaysPLDelta: Int? {
        let history = services.progression.snapshot?.powerLevelHistory ?? []
        guard history.count >= 2 else { return nil }
        return history[history.count - 1].pl - history[history.count - 2].pl
    }
}

// MARK: - Portal arch (the door: straight jambs under a full-semicircle crown)

private struct PortalArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width / 2, rect.height / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius),
                 radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - The realm scene (full-bleed art, drifting imperceptibly, motes rising)

/// The world behind everything: the user's chosen chamber art on a 24 s scale
/// breath (base 1.06 covers the safe-area bleed; the drift adds +0.04 — alive,
/// never noticed), scrimmed so the gold engraving and the lit door pass
/// contrast. Reduce Motion holds a fixed mid-drift crop. Sparse dormant motes
/// keep the air moving (capped, 20 fps — the same layer classic Home runs).
private struct ChamberRealmScene: View {
    let asset: String

    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SettColor.screen
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(reduceMotion ? 1.08 : (drift ? 1.1 : 1.06))
                    .clipped()
                scrims(in: geo.size)
                MoteField(tier: .dormant, maxCount: 12)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func scrims(in size: CGSize) -> some View {
        ZStack {
            // Sky scrim — enough dark for the gold engraving to pass contrast.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.5), location: 0),
                .init(color: .black.opacity(0.2), location: 0.22),
                .init(color: .clear, location: 0.4),
            ], startPoint: .top, endPoint: .bottom)
            // Floor scrim — the world darkens toward the threshold so the lit
            // door reads as THE light source (and the tab bar floats on dark).
            LinearGradient(stops: [
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.45), location: 0.78),
                .init(color: .black.opacity(0.8), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // Edge vignette — the torchlit-center rule, in the app's grammar.
            RadialGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(0.45), location: 1),
            ], center: .center, startRadius: 0,
               endRadius: max(size.width, size.height) * 0.72)
        }
    }
}

// MARK: - Entrance stagger (≤0.6 s total; Reduce Motion = pure fade)

private struct ChamberRiseIn: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(.easeOut(duration: 0.38).delay(reduceMotion ? 0 : delay), value: shown)
    }
}
