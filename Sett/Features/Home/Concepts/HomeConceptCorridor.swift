import SwiftUI
import SwiftData
import SettCore

// MARK: - Concept 2 — "CORRIDOR" (timeline-first)
//
// Your training arc as a vertical PATH you walk — the chamber corridor. A glowing
// cyan spine runs down the leading third of the screen; everything in your week is
// a stop on that line. Behind you: the last sealed session (a medallion). Under
// your feet: TODAY, the one large realm-art doorway docked to the path. Ahead:
// the week's remaining days as ghost stops — and then the road turns CRIMSON,
// because Vexeth is literally standing on it. Past him, faint and gold, the next
// form waits as a distant gate.
//
// Signature motion: the path DRAWS downward on appear (trim-path, ~600 ms total,
// cyan first, then the crimson last segment), nodes popping in as it passes;
// TODAY's node breathes a slow ki pulse. All Reduce-Motion-safe; the glow is
// layered strokes, never an animated shadow.
struct HomeConceptCorridorView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var frequencyGoals: [Goal]

    @State private var isShowingStreak = false

    // The path-draw entrance: cyan spine first, then the crimson approach, then
    // the ghost segment to the gate. One-shot; Reduce Motion snaps all to done.
    @State private var cyanTrim: CGFloat = 0
    @State private var crimsonTrim: CGFloat = 0
    @State private var ghostOpacity: Double = 0
    /// The draw-on plays once per Home instance — popping back from a workout
    /// detail (onAppear refires) must not replay the entrance.
    @State private var hasDrawnRail = false

    init() {
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        let finishedSort = [SortDescriptor(\Workout.startedAt, order: .reverse)]
        _finishedWorkouts = Query(filter: finishedFilter, sort: finishedSort)

        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])

        let goalFilter = #Predicate<Goal> { $0.kindRaw == "frequency" && $0.isActive && $0.deletedAt == nil }
        _frequencyGoals = Query(filter: goalFilter)
    }

    /// Streaks and weekly buckets use ISO weeks (Monday start), matching the engines.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                corridor
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 88) // clear the floating tab bar
            }
            .scrollIndicators(.hidden)
            .dungeonBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: drawRail)
            .sheet(isPresented: $isShowingStreak) {
                StreakSheet(state: streakState,
                            mode: services.settings.scheduleMode,
                            scheduledDays: scheduledDayNames,
                            plMultiplier: services.progression.snapshot?.consistencyMultiplier,
                            daysSinceLastWorkout: daysSinceLastWorkout)
            }
        }
    }

    // MARK: The corridor (one column; the rail draws in its background layer)

    private var corridor: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 28)
            if let last = lastSealedWorkout {
                sealNode(last)
                    .corridorPop(0.05, reduceMotion: reduceMotion)
                    .padding(.bottom, 20)
            }
            todayNode
                .corridorPop(0.12, reduceMotion: reduceMotion)
                .padding(.bottom, 24)
            weekCluster
                .corridorPop(0.25, reduceMotion: reduceMotion)
                .padding(.bottom, 36)
            vexethNode
                .corridorPop(0.4, reduceMotion: reduceMotion)
                .padding(.bottom, 40)
            gateNode
                .corridorPop(0.5, reduceMotion: reduceMotion)
        }
        .backgroundPreferenceValue(CorridorAnchorKey.self) { anchors in
            GeometryReader { geo in
                rail(in: geo, anchors: anchors)
            }
        }
    }

    /// The rail's entrance: cyan spine (~0.4 s), then the crimson approach, then the
    /// ghost run to the gate — the whole draw lands inside ~0.6 s. RM: instant.
    private func drawRail() {
        guard !hasDrawnRail else { return }
        hasDrawnRail = true
        guard !reduceMotion else {
            cyanTrim = 1
            crimsonTrim = 1
            ghostOpacity = 1
            return
        }
        withAnimation(.easeInOut(duration: 0.38)) { cyanTrim = 1 }
        withAnimation(.easeOut(duration: 0.14).delay(0.38)) { crimsonTrim = 1 }
        withAnimation(.easeOut(duration: 0.15).delay(0.46)) { ghostOpacity = 1 }
    }

    // MARK: Rail (layered-stroke glow — never an animated shadow)

    @ViewBuilder
    private func rail(in geo: GeometryProxy, anchors: [CorridorStop: Anchor<CGPoint>]) -> some View {
        if let todayAnchor = anchors[.today] {
            let today = geo[todayAnchor]
            let x = today.x
            let topY = anchors[.seal].map { geo[$0].y } ?? (today.y - 40)
            let weekEndY = anchors[.weekEnd].map { geo[$0].y } ?? (today.y + 56)
            ZStack {
                glowStroke(RailSegment(from: CGPoint(x: x, y: topY),
                                       to: CGPoint(x: x, y: weekEndY)),
                           trim: cyanTrim, color: SettColor.heroCyan)
                if let vexethAnchor = anchors[.vexeth] {
                    let vexethY = geo[vexethAnchor].y
                    // The last walked segment turns crimson: Vexeth is ON the road.
                    // It stops at his marker and NEVER runs on toward the gold gate.
                    glowStroke(RailSegment(from: CGPoint(x: x, y: weekEndY),
                                           to: CGPoint(x: x, y: vexethY - 24)),
                               trim: crimsonTrim, color: SettColor.villainCrimson)
                    if let gateAnchor = anchors[.gate] {
                        // Past the rival the road is unwalked — a faint iron dash,
                        // keeping crimson and gold apart.
                        RailSegment(from: CGPoint(x: x, y: vexethY + 24),
                                    to: CGPoint(x: x, y: geo[gateAnchor].y - 20))
                            .stroke(SettColor.iron.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 7]))
                            .opacity(ghostOpacity)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Soft ki glow: three layered strokes of the same trimmed segment (wide faint
    /// halo → mid wash → hot core). Static styling; only the trim animates, once.
    private func glowStroke(_ segment: RailSegment, trim: CGFloat, color: Color) -> some View {
        ZStack {
            segment.trim(from: 0, to: trim)
                .stroke(color.opacity(0.12), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            segment.trim(from: 0, to: trim)
                .stroke(color.opacity(0.32), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            segment.trim(from: 0, to: trim)
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: Header — compact gold PL + form (small; the path is the hero here)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                .uppercased())
            let pl = services.progression.snapshotPowerLevel
            if pl > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    SacredNumberView(value: pl, size: .m)
                    Text(UserForm.form(forPL: pl).title)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.heroCyan)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Power level \(pl), \(UserForm.form(forPL: pl).title.capitalized)")
            } else {
                Text("The corridor opens.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SettColor.bone)
            }
        }
        // Nothing sits under the floating gear (top-right) — header stays leading.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 56)
    }

    // MARK: Seal node — the last sealed session, a medallion behind you

    private func sealNode(_ workout: Workout) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(SettColor.card)
                    Circle().strokeBorder(SettColor.heroCyan.opacity(0.45), lineWidth: 1)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SettColor.heroCyan.opacity(0.9))
                }
                .frame(width: 28, height: 28)
                .frame(width: Self.railColumnWidth)
                .anchorPreference(key: CorridorAnchorKey.self, value: .center) { [.seal: $0] }
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow("SEALED · \(sealDayLabel(workout))")
                    HStack(spacing: 8) {
                        Text(workout.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SettColor.bone)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let delta = plDelta(for: workout) {
                            Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) PL")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .kerning(0.5)
                                .monospacedDigit()
                                .foregroundStyle(SettColor.deltaInk(delta))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(SettColor.deltaInk(delta).opacity(0.12), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel(sealAccessibility(workout))
        .accessibilityHint("Opens the workout's details")
    }

    private func sealDayLabel(_ workout: Workout) -> String {
        if Calendar.current.isDateInYesterday(workout.startedAt) { return "YESTERDAY" }
        return workout.startedAt
            .formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .uppercased()
    }

    private func sealAccessibility(_ workout: Workout) -> String {
        var parts = ["Sealed: \(workout.title), \(sealDayLabel(workout).capitalized)"]
        if let delta = plDelta(for: workout) {
            parts.append(delta == 0 ? "no power change"
                                    : "\(delta > 0 ? "up" : "down") \(abs(delta)) power level")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Today node — THE stop on the line (three faces + first run)

    private var todayNode: some View {
        HStack(alignment: .center, spacing: 12) {
            KiNodeMarker(sealed: trainedToday)
                .frame(width: Self.railColumnWidth)
                .anchorPreference(key: CorridorAnchorKey.self, value: .center) { [.today: $0] }
            Group {
                if finishedWorkouts.isEmpty {
                    firstDirectiveCard
                } else if trainedToday {
                    sealedTodayCard
                } else if isRestDay {
                    restCard
                } else {
                    directiveCard
                }
            }
        }
    }

    private static let railColumnWidth: CGFloat = 40
    private let heroHeight: CGFloat = 150

    /// The NEXT DIRECTIVE face — the whole doorway starts the routine; the small
    /// "or start empty" ghost is a sibling button (never nested tap targets).
    private var directiveCard: some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                startPrimary()
            } label: {
                RealmDoorwayCard(asset: launchRealmAsset, emphasized: true, height: heroHeight) {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(todayEyebrow, tint: SettColor.heroCyan)
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
                            StatusChip("SURGE ARMED", tint: SettColor.heroCyan, icon: "bolt.fill")
                                .padding(.top, 2)
                                .accessibilityLabel("Rested surge armed — this session counts extra")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } accessory: {
                    playDisc
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableSlabStyle(haptic: .light))
            .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Quick start a workout")

            if todaysRoutine != nil {
                quickStartGhost
                    .padding(.leading, 18)
                    .padding(.bottom, 12)
            }
        }
    }

    /// The SEALED face — today's stop already stamped: ΔPL (gold on a gain, per the
    /// color law) and the next stop named. No play disc; the corridor has cooled.
    private var sealedTodayCard: some View {
        RealmDoorwayCard(asset: launchRealmAsset, emphasized: false, height: heroHeight) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow("SEALED · TODAY", tint: SettColor.heroCyan)
                if let delta = todaysPLDelta {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) ΔPL")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(delta > 0 ? SettColor.saiyanGold : SettColor.ash)
                        .shadow(color: .black.opacity(0.55), radius: 3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("The work is logged.")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                }
                if let next = nextSessionInfo {
                    Text("NEXT STOP: \(next.name) · \(next.day)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } accessory: {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(SettColor.heroCyan.opacity(0.85))
                .shadow(color: SettColor.heroCyan.opacity(0.4), radius: 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sealedTodayAccessibility)
    }

    private var sealedTodayAccessibility: String {
        var parts = ["Today's stop sealed"]
        if let delta = todaysPLDelta {
            parts.append(delta == 0 ? "no power change"
                                    : "\(delta > 0 ? "up" : "down") \(abs(delta)) power level")
        }
        if let next = nextSessionInfo { parts.append("next \(next.name), \(next.day)") }
        return parts.joined(separator: ", ")
    }

    /// The REST face — a banked surge, not a nag. Quick start demoted to the ghost.
    private var restCard: some View {
        RealmDoorwayCard(asset: launchRealmAsset, emphasized: false, height: heroHeight) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("REST STOP · SURGE BANKS", tint: SettColor.heroCyan)
                Text("A full rest day arms tomorrow's session ×1.25")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                quickStartGhost.padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } accessory: {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
        }
        .saturation(0.65)
        .brightness(-0.04)
    }

    /// Day zero: the corridor's first step, same doorway grammar.
    private var firstDirectiveCard: some View {
        Button {
            session.quickStart()
        } label: {
            RealmDoorwayCard(asset: ChamberBackground.resolve(services.settings.chamberBackground).assetName,
                             emphasized: true, height: heroHeight) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("FIRST STEP", tint: SettColor.heroCyan)
                    Text("Enter the corridor")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    Text("YOUR PATH STARTS AT THIS DOOR")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } accessory: {
                playDisc
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("Start your first workout")
    }

    private func startPrimary() {
        if let routine = todaysRoutine { session.start(routine: routine) }
        else { session.quickStart() }
    }

    private var playDisc: some View {
        ZStack {
            Circle()
                .fill(SettColor.heroCyan)
                .frame(width: 56, height: 56)
                .shadow(color: SettColor.heroCyan.opacity(0.5), radius: 8, y: 2)
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SettColor.etch)
                .offset(x: 2)
        }
        .accessibilityHidden(true)
    }

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

    // MARK: Week cluster — the remaining stops, with the streak target marked

    /// Tapping anywhere on the cluster opens the streak sheet — the week IS the streak.
    private var weekCluster: some View {
        Button {
            Haptics.light()
            isShowingStreak = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                weekHeaderRow
                    .padding(.bottom, 6)
                ForEach(Array(remainingDayIndices.enumerated()), id: \.element) { position, day in
                    ghostStopRow(day: day)
                    if position + 1 == daysStillNeeded {
                        targetLineRow
                    }
                }
                if daysStillNeeded == 0 {
                    weekSealedRow
                } else if daysStillNeeded > remainingDayIndices.count {
                    // The target can't land inside the remaining stops (short week or
                    // deep target) — mark it quietly at the cluster's end, never a scold.
                    targetLineRow
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .anchorPreference(key: CorridorAnchorKey.self, value: .bottom) { [.weekEnd: $0] }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekAccessibility)
        .accessibilityHint("Shows streak rules and this week's progress")
    }

    private var weekHeaderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SettColor.heroCyan.opacity(isRekindle ? 0.55 : 1))
                .frame(width: Self.railColumnWidth)
            HStack(spacing: 8) {
                Eyebrow("THIS WEEK")
                // The target pips: one per required day, charged as days land.
                HStack(spacing: 4) {
                    ForEach(0 ..< max(1, streakTarget), id: \.self) { index in
                        Circle()
                            .fill(index < trainedDaysThisWeek.count
                                  ? SettColor.heroCyan
                                  : SettColor.heroCyan.opacity(0.15))
                            .frame(width: 5, height: 5)
                    }
                }
                Text("\(trainedDaysThisWeek.count)/\(streakTarget)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.heroCyan)
                if isRekindle {
                    Text("· RELIGHT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.heroCyan.opacity(0.8))
                } else if streakWeeks > 0 {
                    Text("· \(streakWeeks) WK")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.heroCyan.opacity(0.8))
                }
                if streakState.shields > 0 {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(SettColor.heroCyan.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// A ghost stop: hollow marker on the rail, weekday letter, and (weekday mode)
    /// the routine scheduled to fire there — the road ahead, readable in one glance.
    private func ghostStopRow(day: Int) -> some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(SettColor.iron.opacity(0.7), lineWidth: 1)
                .frame(width: 8, height: 8)
                .frame(width: Self.railColumnWidth)
            Text(TrainDays.shortNames[day].uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.iron)
                .frame(width: 34, alignment: .leading)
            if let name = scheduledRoutineName(day: day) {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(SettColor.iron)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 26)
    }

    /// The streak-target line: a cyan tick crossing the rail where the week's ask
    /// would be met — a station marker on the road, not a deadline.
    private var targetLineRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(SettColor.heroCyan.opacity(0.7))
                .frame(width: 16, height: 2)
                .frame(width: Self.railColumnWidth)
            Text("STREAK TARGET · \(streakTarget)/WK")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.heroCyan.opacity(0.9))
            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }

    /// The week already met its ask — the target line reads as passed, quietly lit.
    private var weekSealedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: Self.railColumnWidth)
            Text("WEEK SEALED · \(trainedDaysThisWeek.count)/\(streakTarget)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .monospacedDigit()
                .foregroundStyle(SettColor.heroCyan)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private var weekAccessibility: String {
        let shieldPart = streakState.shields > 0
            ? ", \(streakState.shields) shield\(streakState.shields == 1 ? "" : "s") banked" : ""
        let firePart = isRekindle ? "streak ready to relight"
                                  : "\(streakWeeks) week streak"
        return "This week \(trainedDaysThisWeek.count) of \(streakTarget) days trained, \(firePart)\(shieldPart)"
    }

    // MARK: Vexeth node — the rival as a PLACE on your road

    private var vexethNode: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(SettColor.villainVoid)
                VexethPortraitView(form: rival.form)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                Circle().strokeBorder(SettColor.villainCrimson.opacity(0.8), lineWidth: 1.5)
            }
            .frame(width: 36, height: 36)
            .shadow(color: SettColor.villainCrimson.opacity(0.45), radius: 6)
            .frame(width: Self.railColumnWidth)
            .anchorPreference(key: CorridorAnchorKey.self, value: .center) { [.vexeth: $0] }
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(VexethArtwork.title(for: rival.form).uppercased(),
                        tint: SettColor.villainCrimson)
                Text(rivalGapLine)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .kerning(0.5)
                    .monospacedDigit()
                    .foregroundStyle(SettColor.villainCrimson)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("“\(services.progression.rivalTaunt)”")
                    .font(.footnote.italic())
                    .foregroundStyle(SettColor.villainCrimson.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vexeth, \(rivalGapLine.lowercased()). \(services.progression.rivalTaunt)")
    }

    private var rival: (pl: Int, form: Int) { services.progression.effectiveRival }

    /// "N PL AHEAD · CATCH IN W WK" — or, when the road is yours, "N PL BEHIND YOU".
    private var rivalGapLine: String {
        let gap = rival.pl - services.progression.snapshotPowerLevel
        guard gap > 0 else { return "\(abs(gap).formatted()) PL BEHIND YOU" }
        let pace = services.progression.trailingWeeklyPace
        let growth = services.progression.effectiveRivalGrowth
        if pace > growth {
            let weeks = Int((Double(gap) / Double(pace - growth)).rounded(.up))
            return "\(gap.formatted()) PL AHEAD · CATCH IN \(weeks) WK"
        }
        return "\(gap.formatted()) PL AHEAD"
    }

    // MARK: Gate node — the next form, a distant gold gate

    private var gateNode: some View {
        let pl = services.progression.snapshotPowerLevel
        let form = UserForm.form(forPL: pl)
        let next = UserForm.form(forPL: form.nextPL)
        return HStack(alignment: .center, spacing: 12) {
            GateShape()
                .stroke(SettColor.saiyanGold.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 18, height: 22)
                .auraGlow(SettColor.saiyanGold.opacity(0.5), radius: 5)
                .frame(width: Self.railColumnWidth)
                .anchorPreference(key: CorridorAnchorKey.self, value: .center) { [.gate: $0] }
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("NEXT FORM", tint: SettColor.saiyanGold.opacity(0.8))
                Text("\(next.title) · \(form.nextPL.formatted())")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .kerning(0.5)
                    .monospacedDigit()
                    .foregroundStyle(SettColor.saiyanGold.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\((form.nextPL - pl).formatted()) PL TO GO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .monospacedDigit()
                    .foregroundStyle(SettColor.iron)
            }
            Spacer(minLength: 0)
        }
        .opacity(0.9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next form: \(next.title.capitalized) at \(form.nextPL) power level, \(form.nextPL - pl) to go")
    }

    // MARK: Derivations (mirroring the classic Home so the surfaces never disagree)

    /// The most recent sealed session that is NOT today's — today's belongs to the
    /// today node. When today is untrained this is simply the latest workout.
    private var lastSealedWorkout: Workout? {
        finishedWorkouts.first { !Calendar.current.isDateInToday($0.startedAt) }
    }

    /// ΔPL a given workout's day landed vs the previous training day — read from the
    /// in-memory trajectory (never SwiftData relationship walks in `body`).
    private func plDelta(for workout: Workout) -> Int? {
        let history = services.progression.powerLevelHistory
        guard history.count >= 2 else { return nil }
        let calendar = Calendar.current
        guard let index = history.lastIndex(where: {
            calendar.isDate($0.date, inSameDayAs: workout.startedAt)
        }), index > 0 else { return nil }
        return history[index].pl - history[index - 1].pl
    }

    /// Today's ΔPL — the last two trajectory points. nil before two points.
    private var todaysPLDelta: Int? {
        let history = services.progression.powerLevelHistory
        guard history.count >= 2 else { return nil }
        return history[history.count - 1].pl - history[history.count - 2].pl
    }

    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
    }

    private var weeklyGoalTarget: Int {
        frequencyGoals.first?.targetValue ?? 3
    }

    /// The week's real commitment — goal capped by the weekday schedule (see classic).
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

    /// The fire went cold but this user HAD a streak — read patience, not zero.
    private var isRekindle: Bool { streakWeeks == 0 && streakState.bestWeeks > 0 }

    private var scheduledDayNames: [String] {
        let mask = Scheduling.orderedActive(routines).reduce(0) { $0 | $1.daysOfWeekMask }
        return (0..<7).compactMap { day in
            TrainDays.isSet(mask, day: day) ? TrainDays.shortNames[day].uppercased() : nil
        }
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

    private var todayIndex: Int {
        (Self.isoCalendar.component(.weekday, from: .now) + 5) % 7
    }

    private var trainedToday: Bool { trainedDaysThisWeek.contains(todayIndex) }

    /// The week's stops still ahead of today (Monday-indexed).
    private var remainingDayIndices: [Int] {
        todayIndex < 6 ? Array((todayIndex + 1)...6) : []
    }

    /// Days still needed this week to hit the streak target.
    private var daysStillNeeded: Int {
        max(0, streakTarget - trainedDaysThisWeek.count)
    }

    private var isRestDay: Bool {
        services.settings.scheduleMode == .weekday
            && todaysRoutine == nil
            && !Scheduling.orderedActive(routines).isEmpty
    }

    private var daysSinceLastWorkout: Int? {
        guard let last = finishedWorkouts.first?.startedAt else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: last),
                                       to: calendar.startOfDay(for: .now)).day
    }

    /// Weekday-mode: the routine scheduled on a given future day (rotation shows none —
    /// the cycle only knows its next stop, which the today node already names).
    private func scheduledRoutineName(day: Int) -> String? {
        guard services.settings.scheduleMode == .weekday else { return nil }
        return Scheduling.orderedActive(routines)
            .first { TrainDays.isSet($0.daysOfWeekMask, day: day) }?.name
    }

    /// "TODAY · <why now>" — the weekday it fires on, or the rotation slot.
    private var todayEyebrow: String {
        guard let routine = todaysRoutine else {
            return "TODAY · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())"
        }
        switch services.settings.scheduleMode {
        case .weekday:
            return "TODAY · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())"
        case .rotation:
            let order = Scheduling.orderedActive(routines)
            let position = (order.firstIndex { $0.id == routine.id } ?? 0) + 1
            return "TODAY · CYCLE \(position)/\(order.count)"
        }
    }

    private var launchSubline: String {
        if let routine = todaysRoutine {
            let count = routine.orderedExercises.count
            var line = "\(count) EXERCISE\(count == 1 ? "" : "S")"
            if let minutes = typicalRoutineMinutes(routine) { line += " · ~\(minutes) MIN" }
            return line
        }
        return "EMPTY CHAMBER — LOG AS YOU GO"
    }

    /// Typical wall-clock length from this routine's own finished sessions (active
    /// time; needs two real sessions; sub-5-minute blips ignored). Mirrors classic.
    private func typicalRoutineMinutes(_ routine: Routine) -> Int? {
        let seconds = finishedWorkouts.compactMap { workout -> Int? in
            guard workout.routineID == routine.id, let ended = workout.endedAt else { return nil }
            let active = Int(ended.timeIntervalSince(workout.startedAt)) - workout.pausedSeconds
            return active > 300 ? active : nil
        }
        guard seconds.count >= 2 else { return nil }
        return max(1, Int((Double(seconds.reduce(0, +)) / Double(seconds.count) / 60).rounded()))
    }

    /// The realm behind today's doorway — the routine's own domain, else a realm
    /// deliberately different from the app-default sky. Mirrors classic.
    private var launchRealmAsset: String {
        if let raw = todaysRoutine?.domainRaw {
            return ChamberBackground.resolve(raw).assetName
        }
        let home = ChamberBackground.resolve(services.settings.chamberBackground)
        let preferred: [ChamberBackground] = [.nebula, .storm, .aurora, .volcanic, .sanctuary, .white]
        return (preferred.first { $0 != home } ?? .nebula).assetName
    }

    /// The next stop after a sealed today — rotation's next-up, or the next scheduled
    /// weekday within a week. Mirrors classic.
    private var nextSessionInfo: (name: String, day: String)? {
        let active = Scheduling.orderedActive(routines)
        guard !active.isEmpty else { return nil }
        switch services.settings.scheduleMode {
        case .rotation:
            guard let next = Scheduling.nextRoutine(routines, settings: services.settings) else { return nil }
            return (next.name, "UP NEXT")
        case .weekday:
            let calendar = Self.isoCalendar
            for offset in 1...7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { continue }
                let mondayIndex = (calendar.component(.weekday, from: date) + 5) % 7
                if let routine = active.first(where: { ($0.daysOfWeekMask >> mondayIndex) & 1 == 1 }) {
                    return (routine.name, date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                }
            }
            return nil
        }
    }
}

// MARK: - Corridor plumbing (anchors, rail geometry, node chrome)

/// The stops whose rail geometry the background path needs. Week ghost stops sit
/// on the line but don't bend it, so only the cluster's end is anchored.
private enum CorridorStop: Hashable {
    case seal, today, weekEnd, vexeth, gate
}

private struct CorridorAnchorKey: PreferenceKey {
    static let defaultValue: [CorridorStop: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [CorridorStop: Anchor<CGPoint>],
                       nextValue: () -> [CorridorStop: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One straight rail segment in the corridor's own coordinate space. Drawn with
/// absolute points (the shape ignores its rect), so `.trim` gives the draw-on.
private struct RailSegment: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

/// The distant gold gate: two posts under an arch with a keystone tick — quad
/// curves only, so the arch renders identically in SwiftUI's flipped space.
private struct GateShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let springY = rect.minY + rect.height * 0.42
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: springY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: springY),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Keystone tick at the crown.
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + 3))
        return path
    }
}

/// TODAY's marker — the pulsing ki node on the line. A soft halo breathes via a
/// small scale/opacity loop (30 pt layer — cheap, per the CPU law); the core dot
/// and ring stay still so the station never blurs. Sealed swaps the pulse for a
/// solid, quiet stamp. Reduce Motion holds a fixed mid-breath halo.
private struct KiNodeMarker: View {
    var sealed: Bool

    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !sealed {
                Circle()
                    .fill(SettColor.heroCyan.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .scaleEffect(reduceMotion ? 1.05 : (breathing ? 1.25 : 0.9))
                    .opacity(reduceMotion ? 0.7 : (breathing ? 0.4 : 0.95))
            }
            Circle()
                .strokeBorder(SettColor.heroCyan.opacity(sealed ? 0.5 : 0.85), lineWidth: 1.5)
                .frame(width: 20, height: 20)
            Circle()
                .fill(SettColor.heroCyan.opacity(sealed ? 0.7 : 1))
                .frame(width: 8, height: 8)
                .shadow(color: SettColor.heroCyan.opacity(0.8), radius: 4)
        }
        .frame(width: 32, height: 32)
        .onAppear {
            guard !sealed, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Node entrance: a quick assemble (opacity + slight leading-anchored scale),
/// staggered down the path so stops appear as the rail reaches them. All delays
/// land inside ~0.6 s. Reduce Motion shows everything immediately.
private struct CorridorPop: ViewModifier {
    let delay: Double
    let reduceMotion: Bool

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94, anchor: .leading)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75).delay(delay)) {
                        shown = true
                    }
                }
            }
    }
}

private extension View {
    func corridorPop(_ delay: Double, reduceMotion: Bool) -> some View {
        modifier(CorridorPop(delay: delay, reduceMotion: reduceMotion))
    }
}
