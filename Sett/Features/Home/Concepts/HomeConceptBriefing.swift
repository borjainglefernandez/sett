import SwiftUI
import SwiftData
import SettCore

// MARK: - Concept 1 — "BRIEFING" (the scouter telemetry HUD)
//
// The two-second total read: a strict grid of HUD tiles on the dungeon background,
// everything mono except the one gold Power Level numeral. Flighty-density data,
// F1-telemetry grammar, terminal boot sequence — the screen POWERS UP on appear:
// each tile's rule draws, its numerals flicker from scramble to value, and a single
// 1px scanline sweeps once. Two mono sizes only (10 / 13); the discipline IS the
// aesthetic. Color law holds: gold = PL numeral only, cyan = ki/action, crimson =
// the ONE Vexeth tile, scouter green = the live START control (session grammar).
// Reduce Motion: everything lands instantly — no sweep, no scramble, no stagger.
struct HomeConceptBriefingView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var frequencyGoals: [Goal]
    @Query private var badgeAwards: [BadgeAward]

    // MARK: Boot state (the signature moment)

    /// Flips once on first appearance; every tile keys its staggered entrance off it.
    @State private var booted = false
    @State private var hasBooted = false
    /// The gold numeral rolls 0 → PL during the boot (odometer feel via numericText).
    @State private var plShown = 0
    /// One-shot scanline sweep: 0 → 1 travel, then the layer fades out and unmounts.
    @State private var scanProgress: CGFloat = 0
    @State private var scanOpacity: Double = 0

    /// This week's hard working sets — a SwiftData relationship walk, so it's
    /// computed in a task and cached here, never in `body` (per the CPU traps).
    @State private var weekSetCount: Int?
    @State private var isShowingStreak = false
    /// Rotating SYSTEM ticker line index (advances every ~6s while mounted).
    @State private var tickerIndex = 0

    init() {
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        _finishedWorkouts = Query(filter: finishedFilter,
                                  sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])

        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])

        let goalFilter = #Predicate<Goal> { $0.kindRaw == "frequency" && $0.isActive && $0.deletedAt == nil }
        _frequencyGoals = Query(filter: goalFilter)

        let badgeFilter = #Predicate<BadgeAward> { $0.deletedAt == nil }
        _badgeAwards = Query(filter: badgeFilter,
                             sort: [SortDescriptor(\BadgeAward.earnedAt, order: .reverse)])
    }

    /// Streaks and weekly buckets use ISO weeks (Monday start), matching the engines.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                grid
                ticker
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 88) // clear the floating tab bar
        }
        .scrollIndicators(.hidden)
        .dungeonBackground()
        .onAppear(perform: boot)
        .task(id: finishedWorkouts.count) { loadWeekSets() }
        .task { await rotateTicker() }
        .onChange(of: services.progression.snapshotPowerLevel) { _, newValue in
            guard hasBooted else { return }
            if reduceMotion { plShown = newValue }
            else { withAnimation(.easeOut(duration: 0.5)) { plShown = newValue } }
        }
        .sheet(isPresented: $isShowingStreak) {
            StreakSheet(state: streakState,
                        mode: services.settings.scheduleMode,
                        scheduledDays: scheduledDayNames,
                        plMultiplier: services.progression.snapshot?.consistencyMultiplier,
                        daysSinceLastWorkout: daysSinceLastWorkout)
        }
    }

    // MARK: Header (bottom-aligned in a 44pt band so the floating gear owns top-right)

    private var header: some View {
        HStack(spacing: 8) {
            Text("SETT // TELEMETRY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.heroCyan.opacity(0.85))
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.ash)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 56) // the concept shell's gear floats top-right
        .frame(minHeight: 44, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sett telemetry, \(Date.now.formatted(date: .abbreviated, time: .omitted))")
    }

    // MARK: The grid (POWER + STREAK / VEXETH / DIRECTIVE / WEEK)

    private var grid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                powerTile
                streakTile.frame(width: 132)
            }
            rivalTile
            directiveTile
            weekTile
        }
        .overlay(alignment: .top) {
            if scanOpacity > 0 { scanline }
        }
    }

    /// The 1px scanline that sweeps the grid once during the boot, then unmounts.
    private var scanline: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(SettColor.heroCyan.opacity(0.7))
                .frame(height: 1)
                .shadow(color: SettColor.heroCyan.opacity(0.5), radius: 3)
                .offset(y: scanProgress * max(0, geo.size.height - 1))
                .opacity(scanOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: POWER tile (the ONE gold element on the screen)

    private var powerTile: some View {
        let pl = services.progression.snapshotPowerLevel
        let form = UserForm.form(forPL: pl)
        return BriefingTile(label: "POWER", index: 0, booted: booted) {
            VStack(alignment: .leading, spacing: 4) {
                PowerNumeral(plShown, size: .l)
                Text(form.title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
                Text(powerStatusLine(pl: pl))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .monospacedDigit()
                    .foregroundStyle(powerStatusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power level \(pl), \(form.title.capitalized), \(powerStatusLine(pl: pl).lowercased())")
    }

    /// Week-so-far ΔPL when a session has landed this week; otherwise the chase —
    /// the peak to reclaim, or the pips to the next form. Mirrors the classic crest.
    private func powerStatusLine(pl: Int) -> String {
        guard pl > 0 else { return "AWAITING FIRST SCAN" }
        if !trainedDaysThisWeek.isEmpty, let delta = services.progression.plDeltaThisWeek {
            return "\(delta >= 0 ? "+" : "")\(delta.formatted()) THIS WEEK"
        }
        let peak = services.progression.snapshot?.allTimePeakPL ?? pl
        if peak > pl {
            return "PEAK \(peak.formatted()) · \((peak - pl).formatted()) TO RECLAIM"
        }
        let form = UserForm.form(forPL: pl)
        let next = UserForm.form(forPL: form.nextPL)
        return "\((form.nextPL - pl).formatted()) TO \(next.title)"
    }

    private var powerStatusTint: Color {
        if !trainedDaysThisWeek.isEmpty, let delta = services.progression.plDeltaThisWeek,
           delta >= 0 {
            return SettColor.positive
        }
        return SettColor.ash
    }

    // MARK: STREAK tile (flame + wk + shields — tap for the rules)

    /// The fire went cold but this user HAD a streak — read RELIGHT, never "0 WK".
    private var isRekindle: Bool { streakWeeks == 0 && streakState.bestWeeks > 0 }

    private var streakTile: some View {
        Button {
            isShowingStreak = true
        } label: {
            BriefingTile(label: "STREAK", index: 1, booted: booted) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SettColor.heroCyan.opacity(isRekindle ? 0.55 : 1))
                            .accessibilityHidden(true)
                        ScrambleNumeral(isRekindle ? "RELIGHT" : "\(streakWeeks) WK",
                                        size: 13, color: SettColor.bone,
                                        delay: tileDelay(1), active: booted)
                    }
                    HStack(spacing: 3) {
                        ForEach(0 ..< max(streakState.shields, 0), id: \.self) { _ in
                            Image(systemName: "shield.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(SettColor.heroCyan.opacity(0.7))
                        }
                        Text(streakState.shields > 0 ? "SHIELDED" : "NO SHIELD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(SettColor.ash)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text("\(trainedDaysThisWeek.count)/\(streakTarget) THIS WK")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .monospacedDigit()
                        .foregroundStyle(trainedDaysThisWeek.count >= streakTarget
                                         ? SettColor.positive : SettColor.ash)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel(streakAccessibility)
        .accessibilityHint("Shows streak rules and this week's progress")
    }

    private var streakAccessibility: String {
        let shieldPart = streakState.shields > 0
            ? ", \(streakState.shields) shield\(streakState.shields == 1 ? "" : "s") banked" : ""
        let weekPart = ", \(trainedDaysThisWeek.count) of \(streakTarget) days this week"
        if isRekindle {
            return "Streak cold, best \(streakState.bestWeeks) weeks, ready to relight\(shieldPart)\(weekPart)"
        }
        return "\(streakWeeks) week streak\(shieldPart)\(weekPart)"
    }

    // MARK: VEXETH tile (the ONLY crimson tile)

    private var rivalTile: some View {
        let pl = services.progression.snapshotPowerLevel
        let rival = services.progression.effectiveRival
        let gap = rival.pl - pl
        let taunt = services.progression.rivalTaunt
        return BriefingTile(label: "VEXETH · FORM \(rival.form)",
                            labelTint: SettColor.villainCrimson.opacity(0.9),
                            rimTint: SettColor.villainCrimson,
                            index: 2, booted: booted) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    ScrambleNumeral(gap > 0 ? "+\(gap.formatted()) PL" : "\(abs(gap).formatted()) PL",
                                    size: 13, color: SettColor.villainCrimson,
                                    delay: tileDelay(2), active: booted)
                    Text(rivalGapCaption(gap: gap))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Text(taunt)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(SettColor.ash)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: 190, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gap > 0
            ? "Vexeth form \(rival.form), \(gap) power levels ahead. \(taunt)"
            : "Vexeth form \(rival.form), \(abs(gap)) power levels behind you. \(taunt)")
    }

    /// AHEAD (+ the catch-in-N-weeks read when your pace outruns his growth) or the
    /// lead you hold. Ash, not crimson — the numeral carries the villain's hue.
    private func rivalGapCaption(gap: Int) -> String {
        guard gap > 0 else { return "BEHIND YOU" }
        let pace = services.progression.trailingWeeklyPace
        let growth = services.progression.effectiveRivalGrowth
        if pace > growth {
            let weeks = Int((Double(gap) / Double(pace - growth)).rounded(.up))
            return "AHEAD · CATCH IN \(weeks) WK"
        }
        return "AHEAD"
    }

    // MARK: DIRECTIVE tile (wide — the day's order + the live START control)

    @ViewBuilder
    private var directiveTile: some View {
        if trainedToday {
            sealedDirective
        } else if isRestDay {
            restDirective
        } else {
            liveDirective
        }
    }

    /// The next session, armed: routine + planning cues + the scouter-green START
    /// capsule (the session's live-instrument green — this is the GO control).
    private var liveDirective: some View {
        BriefingTile(label: directiveEyebrow, index: 3, booted: booted) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(todaysRoutine?.name ?? (finishedWorkouts.isEmpty ? "Enter the chamber" : "Quick Start"))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(directiveSubline)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if services.progression.snapshot?.restedBonusActive == true {
                    StatusChip("SURGE ARMED · ×1.25", tint: SettColor.heroCyan, icon: "bolt.fill")
                        .accessibilityLabel("Rested surge armed. This session's volume counts extra.")
                }
                startCapsule
                if todaysRoutine != nil {
                    quickStartGhost
                }
            }
        }
    }

    /// Today's work already landed — the tile seals instead of prompting again.
    private var sealedDirective: some View {
        BriefingTile(label: "DIRECTIVE · SEALED", index: 3, booted: booted) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SettColor.heroCyan.opacity(0.85))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today's work is logged")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let next = nextSessionInfo {
                        Text("NEXT: \(next.name.uppercased()) · \(next.day)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(SettColor.ash)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Directive sealed, today's work is logged"
                            + (nextSessionInfo.map { ", next \($0.name), \($0.day.lowercased())" } ?? ""))
    }

    /// A weekday-mode planned rest: the surge mechanic spelled out, quick start demoted.
    private var restDirective: some View {
        BriefingTile(label: "DIRECTIVE · REST", index: 3, booted: booted) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A full rest day arms tomorrow ×1.25")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                quickStartGhost
            }
        }
    }

    /// "DIRECTIVE · <why now>" — the weekday it fires on, or its slot in the cycle.
    private var directiveEyebrow: String {
        guard let routine = todaysRoutine else { return "DIRECTIVE" }
        switch services.settings.scheduleMode {
        case .weekday:
            return "DIRECTIVE · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())"
        case .rotation:
            let order = Scheduling.orderedActive(routines)
            let pos = (order.firstIndex { $0.id == routine.id } ?? 0) + 1
            return "DIRECTIVE · CYCLE \(pos)/\(order.count)"
        }
    }

    private var directiveSubline: String {
        if let routine = todaysRoutine {
            let count = routine.orderedExercises.count
            var line = "\(count) EXERCISE\(count == 1 ? "" : "S")"
            if let mins = typicalRoutineMinutes(routine) { line += " · ~\(mins) MIN" }
            return line
        }
        return "EMPTY CHAMBER — LOG AS YOU GO"
    }

    /// The GO control — scouter green, the session instrument's live hue.
    private var startCapsule: some View {
        Button(action: startPrimary) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("START")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .kerning(2)
            }
            .foregroundStyle(SettColor.etch)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(TimeChamber.scouterGreen, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Quick start a workout")
    }

    private func startPrimary() {
        if let routine = todaysRoutine { session.start(routine: routine) }
        else { session.quickStart() }
    }

    /// The docked quick start — a small cyan ghost, never a second full-width CTA.
    private var quickStartGhost: some View {
        Button {
            session.quickStart()
        } label: {
            Text("OR START EMPTY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.heroCyan)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("Start an empty workout")
    }

    // MARK: WEEK tile (7 day pips + sets vs the 60–100 weekly band)

    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    private var weekTile: some View {
        let band = VolumeLandmarks.weeklyTotalRange
        return BriefingTile(label: "WEEK", index: 4, booted: booted) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(0 ..< 7, id: \.self) { day in
                            dayPip(day)
                        }
                    }
                    Text("\(trainedDaysThisWeek.count)/\(streakTarget) DAYS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.ash)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    ScrambleNumeral(weekSetCount.map { "\($0) SETS" } ?? "— SETS",
                                    size: 13, color: SettColor.bone,
                                    delay: tileDelay(4), active: booted)
                    setBandMeter
                        .frame(width: 118, height: 5)
                    Text(setZoneCaption(band: band))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekAccessibility(band: band))
    }

    private func dayPip(_ day: Int) -> some View {
        let trained = trainedDaysThisWeek.contains(day)
        let isToday = day == todayIndex
        return VStack(spacing: 3) {
            Text(Self.dayLetters[day])
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isToday ? SettColor.heroCyan : SettColor.iron)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(trained ? SettColor.heroCyan : SettColor.cardNested)
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(trained ? .clear
                                      : (isToday ? SettColor.heroCyan.opacity(0.7) : SettColor.cardBorder),
                                      lineWidth: 1)
                }
                .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }

    /// Sets-this-week against the whole-body 60–100 weekly landmark band: the band
    /// reads as a lit region on the track, the fill marches toward (or through) it.
    private var setBandMeter: some View {
        let band = VolumeLandmarks.weeklyTotalRange
        let scaleMax = Double(band.upperBound) * 1.2 // headroom past the ceiling
        let sets = Double(weekSetCount ?? 0)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(SettColor.cardNested)
                Rectangle()
                    .fill(SettColor.heroCyan.opacity(0.18))
                    .frame(width: w * CGFloat(Double(band.count - 1) / scaleMax))
                    .offset(x: w * CGFloat(Double(band.lowerBound) / scaleMax))
                Capsule()
                    .fill(SettColor.heroCyan)
                    .frame(width: max(sets > 0 ? 3 : 0, w * CGFloat(min(sets, scaleMax) / scaleMax)))
                ForEach([band.lowerBound, band.upperBound], id: \.self) { mark in
                    Rectangle()
                        .fill(SettColor.bone.opacity(0.8))
                        .frame(width: 1.5, height: geo.size.height + 3)
                        .offset(x: w * CGFloat(Double(mark) / scaleMax))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func setZoneCaption(band: ClosedRange<Int>) -> String {
        guard let sets = weekSetCount else { return "BAND \(band.lowerBound)–\(band.upperBound)" }
        if sets < band.lowerBound { return "BELOW \(band.lowerBound)–\(band.upperBound) BAND" }
        if sets > band.upperBound { return "PAST \(band.upperBound) CEILING" }
        return "IN \(band.lowerBound)–\(band.upperBound) BAND"
    }

    private func weekAccessibility(band: ClosedRange<Int>) -> String {
        var parts = ["\(trainedDaysThisWeek.count) of \(streakTarget) training days this week"]
        if let sets = weekSetCount {
            let zone = sets < band.lowerBound ? "below" : (sets > band.upperBound ? "past" : "inside")
            parts.append("\(sets) working sets, \(zone) the \(band.lowerBound) to \(band.upperBound) weekly band")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: SYSTEM ticker (one rotating ash status line)

    private var ticker: some View {
        HStack(spacing: 8) {
            PulseDot()
            ZStack(alignment: .leading) {
                Text(currentTickerLine)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .id(tickerLines.isEmpty ? 0 : tickerIndex % tickerLines.count)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                              removal: .move(edge: .top).combined(with: .opacity)))
            }
            .clipped()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .opacity(booted ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22).delay(tileDelay(5)), value: booted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System status: \(currentTickerLine.lowercased())")
    }

    private var currentTickerLine: String {
        let lines = tickerLines
        guard !lines.isEmpty else { return "SYSTEMS NOMINAL" }
        return lines[tickerIndex % lines.count]
    }

    /// The rotating status bank, all real reads: the next Monday reading, this week's
    /// volume zone, an armed surge, and the latest patron word over its medallion.
    private var tickerLines: [String] {
        var lines: [String] = [readingLine]
        if let sets = weekSetCount {
            let band = VolumeLandmarks.weeklyTotalRange
            let zone = sets < band.lowerBound ? "BELOW BAND"
                     : (sets > band.upperBound ? "PAST CEILING" : "IN BAND")
            lines.append("VOLUME \(sets) SETS · \(zone) \(band.lowerBound)–\(band.upperBound)")
        }
        if services.progression.snapshot?.restedBonusActive == true {
            lines.append("SURGE ARMED · NEXT SESSION COUNTS ×1.25")
        }
        if let key = badgeAwards.first?.badgeKey, let line = PatronLines.line(forBadgeKey: key) {
            lines.append("PATRON · \(line)")
        }
        return lines
    }

    /// Days until the next Weekly Power Reading (Mondays, ISO weeks).
    private var readingLine: String {
        let todayIdx = (Self.isoCalendar.component(.weekday, from: .now) + 5) % 7
        let days = (7 - todayIdx) % 7
        return days == 0 ? "WEEKLY READING · TODAY" : "WEEKLY READING · IN \(days)D"
    }

    private func rotateTicker() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                tickerIndex &+= 1
            }
        }
    }

    // MARK: Boot orchestration

    private func boot() {
        let pl = services.progression.snapshotPowerLevel
        guard !hasBooted else { plShown = pl; return }
        hasBooted = true
        guard !reduceMotion else {
            booted = true
            plShown = pl
            return
        }
        booted = true // tiles animate in via their delayed .animation(value:)
        withAnimation(.easeOut(duration: 0.7).delay(0.12)) { plShown = pl }
        scanOpacity = 1
        withAnimation(.linear(duration: 0.5)) { scanProgress = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.2)) { scanOpacity = 0 }
        }
        Haptics.light()
    }

    /// Boot stagger for a tile index — shared with the tiles' scramble delays.
    private func tileDelay(_ index: Int) -> Double { 0.04 + Double(index) * 0.07 }

    // MARK: Derivations (mirroring HomeTabView so the surfaces never disagree)

    private var weeklyGoalTarget: Int {
        frequencyGoals.first?.targetValue ?? 3
    }

    /// The week's real ask: the frequency goal, capped by the weekday schedule.
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
            asOf: .now)
    }

    private var streakWeeks: Int { streakState.weeks }

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

    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
    }

    /// A weekday-mode planned rest (routines exist, none scheduled today).
    private var isRestDay: Bool {
        services.settings.scheduleMode == .weekday
            && todaysRoutine == nil
            && !Scheduling.orderedActive(routines).isEmpty
    }

    /// Typical wall-clock minutes for a routine from its own finished sessions —
    /// nil until two real sessions back the claim (sub-5-minute blips ignored).
    private func typicalRoutineMinutes(_ routine: Routine) -> Int? {
        let seconds = finishedWorkouts.compactMap { workout -> Int? in
            guard workout.routineID == routine.id, let ended = workout.endedAt else { return nil }
            let active = Int(ended.timeIntervalSince(workout.startedAt)) - workout.pausedSeconds
            return active > 300 ? active : nil
        }
        guard seconds.count >= 2 else { return nil }
        return max(1, Int((Double(seconds.reduce(0, +)) / Double(seconds.count) / 60).rounded()))
    }

    /// The next session the schedule points at — for the SEALED forward look.
    private var nextSessionInfo: (name: String, day: String)? {
        let active = Scheduling.orderedActive(routines)
        guard !active.isEmpty else { return nil }
        switch services.settings.scheduleMode {
        case .rotation:
            guard let next = Scheduling.nextRoutine(routines, settings: services.settings) else { return nil }
            return (next.name, "UP NEXT")
        case .weekday:
            let cal = Self.isoCalendar
            for offset in 1 ... 7 {
                guard let date = cal.date(byAdding: .day, value: offset, to: .now) else { continue }
                let mondayIndex = (cal.component(.weekday, from: date) + 5) % 7
                if let routine = active.first(where: { ($0.daysOfWeekMask >> mondayIndex) & 1 == 1 }) {
                    return (routine.name, date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                }
            }
            return nil
        }
    }

    private static let shortDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Short names of the scheduled weekdays for the streak sheet's caption.
    private var scheduledDayNames: [String] {
        let mask = Scheduling.orderedActive(routines).reduce(0) { $0 | $1.daysOfWeekMask }
        return (0 ..< 7).compactMap { day in
            (mask >> day) & 1 == 1 ? Self.shortDayNames[day].uppercased() : nil
        }
    }

    /// Days since the most recent logged workout — feeds the streak sheet's tease.
    private var daysSinceLastWorkout: Int? {
        guard let last = finishedWorkouts.first?.startedAt else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: last),
                                  to: cal.startOfDay(for: .now)).day
    }

    /// This week's hard working sets — a relationship walk, so it runs in a task and
    /// lands in @State, never in `body` (per the CPU traps).
    private func loadWeekSets() {
        guard let week = Self.isoCalendar.dateInterval(of: .weekOfYear, for: .now) else {
            weekSetCount = 0
            return
        }
        weekSetCount = finishedWorkouts
            .filter { week.contains($0.startedAt) }
            .flatMap(\.orderedExercises)
            .flatMap(\.orderedSets)
            .filter { !$0.isWarmup }
            .count
    }
}

// MARK: - Tile chrome (thin cardBorder rules, mono eyebrow, staggered boot entrance)

/// One HUD tile: a mono eyebrow with a hairline rule that DRAWS on boot, content
/// below, a quiet slab behind. `rimTint` (Vexeth's crimson) tints the frame; nil
/// keeps the neutral iron hairline. The entrance staggers off `index` so the grid
/// scans in top-to-bottom like a terminal powering up. Reduce Motion: instant.
private struct BriefingTile<Content: View>: View {
    let label: String
    var labelTint: Color = SettColor.ash
    var rimTint: Color? = nil
    let index: Int
    let booted: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(labelTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Rectangle()
                    .fill(rimTint?.opacity(0.35) ?? SettColor.cardBorder)
                    .frame(height: 1)
                    .scaleEffect(x: booted || reduceMotion ? 1 : 0, anchor: .leading)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(delay + 0.06),
                               value: booted)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettColor.card.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(rimTint?.opacity(0.4) ?? SettColor.cardBorder, lineWidth: 1)
                }
        }
        .opacity(booted ? 1 : 0)
        .offset(y: booted || reduceMotion ? 0 : 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22).delay(delay), value: booted)
    }

    private var delay: Double { 0.04 + Double(index) * 0.07 }
}

// MARK: - Scramble numeral (digits flicker from noise to value on boot)

/// A mono readout whose DIGITS flicker through ~4 scramble frames before settling —
/// the boot's terminal feel without heavy effects (pure text swaps, a finite task).
/// Letters and punctuation hold still so the line never reads as garbage. Reduce
/// Motion (or an already-settled boot) renders the value directly.
private struct ScrambleNumeral: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = SettColor.bone
    var delay: Double = 0
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String
    @State private var run: Task<Void, Never>?
    @State private var fired = false

    init(_ text: String, size: CGFloat = 13, color: Color = SettColor.bone,
         delay: Double = 0, active: Bool) {
        self.text = text
        self.size = size
        self.color = color
        self.delay = delay
        self.active = active
        _shown = State(initialValue: text)
    }

    var body: some View {
        Text(shown)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .onAppear { if active { fire() } }
            .onChange(of: active) { _, isOn in
                if isOn { fire() }
            }
            .onChange(of: text) { _, newText in
                run?.cancel()
                shown = newText
            }
            .onDisappear {
                run?.cancel()
                shown = text
            }
            .accessibilityLabel(text)
    }

    private func fire() {
        guard !fired else { return }
        fired = true
        guard !reduceMotion else {
            shown = text
            return
        }
        run?.cancel()
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            var rng = BriefingRNG(seed: UInt64(truncatingIfNeeded: text.hashValue) | 1)
            for _ in 0 ..< 4 {
                guard !Task.isCancelled else { return }
                shown = String(text.map { ch in
                    ch.isNumber ? Self.digits[min(9, Int(rng.unit() * 10))] : ch
                })
                try? await Task.sleep(for: .milliseconds(45))
            }
            guard !Task.isCancelled else { return }
            shown = text
        }
    }

    private static let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
}

/// Minimal seeded LCG (Knuth MMIX) for the scramble frames — never SystemRandom in
/// a render path, matching the app's deterministic-chrome rule.
private struct BriefingRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - Pulse dot (the ticker's live-link light)

/// A 5pt scouter-green dot breathing at a slow ease — opacity on a tiny layer only
/// (CPU law: no shadow/blur loops, no large surfaces). Reduce Motion holds it lit.
private struct PulseDot: View {
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(TimeChamber.scouterGreen)
            .frame(width: 5, height: 5)
            .opacity(reduceMotion ? 0.9 : (lit ? 1 : 0.35))
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    lit = true
                }
            }
    }
}
