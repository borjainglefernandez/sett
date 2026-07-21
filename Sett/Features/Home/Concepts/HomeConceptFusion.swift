import SwiftUI
import SwiftData
import SettCore

// MARK: - Concept 3 — "FUSION" (Briefing's glance + Corridor's road)
//
// One screen, two questions. The TOP is Briefing compressed to its essence: a
// fixed ~205pt telemetry band in strict mono grammar — a tall POWER tile (the
// one gold numeral, form, week line, hard-set pulse) beside a STREAK-over-WEEK
// column — that answers "how am I doing" in two seconds and never scrolls.
// Vexeth has NO band tile: he is a place, not a stat, and lives only at his
// stop on the road. BELOW the band, Corridor's road answers "where am I going"
// AND "where have I been": the glowing rail drops straight out of the POWER
// tile's baseline, fades up into the recent PAST (compact sealed medallions +
// an ALL SCANS link into the full log), and walks the week — sealed yesterday,
// TODAY's doorway, the remaining stops, the crimson stretch where Vexeth
// stands, and the distant gold gate of the next form.
//
// Signature motion — ONE continuous boot: the glance band scans in (~350 ms,
// staggered tiles + digit scramble), then the rail draws downward out of the
// band (~450 ms), nodes popping as it passes. A single connected reveal, played
// once per app session. Reduce Motion: everything lands instantly.
//
// Color law holds: gold = PL numeral + the form gate ONLY; cyan = ki/action;
// crimson = Vexeth's stretch of road only, never beside gold; scouter green =
// the live START control (session grammar); deltaInk on signed numbers.
struct HomeConceptFusionView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var frequencyGoals: [Goal]

    @State private var isShowingStreak = false
    /// Non-warmup sets landed this ISO week (WeeklyHardSets) — extracted once per
    /// appearance / new finish, never derived from SwiftData in `body` (CPU law).
    @State private var weeklyHardSets = 0

    // MARK: Boot state (the single connected reveal)

    /// Flips once; glance tiles key their staggered entrance off it.
    @State private var booted = false
    /// The gold numeral rolls 0 → PL during the boot (numericText odometer).
    @State private var plShown = 0
    /// Rail draw-on: cyan spine, then the crimson approach, then the ghost dash.
    @State private var cyanTrim: CGFloat = 0
    @State private var crimsonTrim: CGFloat = 0
    @State private var ghostOpacity: Double = 0
    /// Road nodes pop off this as the rail passes them.
    @State private var roadShown = false
    /// True only for the ONE animated boot of the session. Replays (tab return,
    /// nav pop, sheet dismissal) keep it false so every `.animation(value:)`
    /// entrance resolves to nil and the screen lands fully assembled.
    @State private var animatedBoot = false

    /// The boot plays ONCE per app session — returning to the tab, popping back
    /// from a detail, or closing Settings must not replay the entrance.
    @MainActor private static var hasBootedThisSession = false

    init() {
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        _finishedWorkouts = Query(filter: finishedFilter,
                                  sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])

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
            VStack(spacing: 0) {
                glance
                ScrollView {
                    road
                        .padding(.horizontal, 16)
                        .padding(.bottom, 88) // clear the floating tab bar
                }
                .scrollIndicators(.hidden)
            }
            .dungeonBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: boot)
            // Re-extract when a session lands (count bump) and on first mount.
            .task(id: finishedWorkouts.count) { refreshWeeklySets() }
            .onChange(of: services.progression.snapshotPowerLevel) { _, newValue in
                guard booted else { return }
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
    }

    // MARK: - THE GLANCE (fixed band, never scrolls)

    private var glance: some View {
        VStack(alignment: .leading, spacing: 8) {
            glanceHeader
            // Two columns, no dead space: the tall POWER tile carries the numeral,
            // form, week line and hard-set pulse; the right column stacks the
            // compact STREAK over WEEK. Vexeth holds no tile — he waits on the road.
            HStack(alignment: .top, spacing: 8) {
                powerTile
                VStack(spacing: 8) {
                    streakTile
                    weekTile.frame(height: 56)
                }
                .frame(width: 132)
            }
            .frame(height: 150)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            // The band's floor — the road begins on the far side of this rule.
            Rectangle()
                .fill(SettColor.cardBorder)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomLeading) {
            // The rail's exit port: a cyan tick punching through the floor rule
            // under the POWER tile, where the road drops out of the band.
            RoundedRectangle(cornerRadius: 1)
                .fill(SettColor.heroCyan.opacity(0.9))
                .frame(width: 2, height: 12)
                .offset(x: 35, y: 6)
                .opacity(Double(cyanTrim))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // The band is fixed chrome: it (and its exit tick) must draw OVER road
        // content sliding underneath during a scroll.
        .zIndex(1)
    }

    private var glanceHeader: some View {
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
        .frame(minHeight: 36, alignment: .bottomLeading)
        .opacity(booted ? 1 : 0)
        .animation(animatedBoot ? .easeOut(duration: 0.18) : nil, value: booted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sett telemetry, \(Date.now.formatted(date: .abbreviated, time: .omitted))")
    }

    // MARK: POWER tile (the ONE gold element in the band — the rail hangs off it)

    private var powerTile: some View {
        let pl = services.progression.snapshotPowerLevel
        let form = UserForm.form(forPL: pl)
        return FusionTile(label: "POWER", index: 0, booted: booted, animated: animatedBoot) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plShown.formatted())
                    .font(.system(size: 48, weight: .heavy, design: .rounded).italic())
                    .monospacedDigit()
                    .foregroundStyle(Aura.gold)
                    .contentTransition(.numericText(value: Double(plShown)))
                    // Hard dark outline, then the static gold bloom (never animated).
                    .shadow(color: SettColor.etch, radius: 0, x: 1, y: 1)
                    .shadow(color: SettColor.etch, radius: 0, x: -1, y: 1)
                    .auraGlow(SettColor.saiyanGold, radius: 6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(form.title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
                Spacer(minLength: 4)
                Text(powerStatusLine(pl: pl))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .monospacedDigit()
                    .foregroundStyle(powerStatusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(weeklyHardSets.formatted()) HARD SET\(weeklyHardSets == 1 ? "" : "S") THIS WK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .monospacedDigit()
                    .foregroundStyle(SettColor.ash)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power level \(pl), \(form.title.capitalized), \(powerStatusLine(pl: pl).lowercased()), \(weeklyHardSets) hard set\(weeklyHardSets == 1 ? "" : "s") this week")
    }

    /// Week-so-far ΔPL when a session landed this week; otherwise the chase —
    /// the peak to reclaim, or the distance to the next form. Mirrors Briefing.
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

    /// The signed week line takes deltaInk (green up, iron down — never alarm red);
    /// the chase lines stay quiet ash.
    private var powerStatusTint: Color {
        if !trainedDaysThisWeek.isEmpty, let delta = services.progression.plDeltaThisWeek {
            return SettColor.deltaInk(delta)
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
            FusionTile(label: "STREAK", index: 1, booted: booted, animated: animatedBoot) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SettColor.heroCyan.opacity(isRekindle ? 0.55 : 1))
                            .accessibilityHidden(true)
                        FusionScramble(isRekindle ? "RELIGHT" : "\(streakWeeks) WK",
                                       size: 13, color: SettColor.bone,
                                       delay: tileDelay(1), active: booted,
                                       animated: animatedBoot)
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

    // MARK: WEEK tile (7 pips + n/target)
    // (No VEXETH tile — the rival is a PLACE, not a stat: he lives only at his
    // stop on the road below, which keeps gap + form + taunt + catch states.)

    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    private var weekTile: some View {
        FusionTile(label: "WEEK", index: 2, booted: booted, animated: animatedBoot) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0 ..< 7, id: \.self) { day in
                        dayPip(day)
                    }
                }
                Spacer(minLength: 4)
                FusionScramble("\(trainedDaysThisWeek.count)/\(streakTarget)",
                               size: 13, color: SettColor.bone,
                               delay: tileDelay(2), active: booted,
                               animated: animatedBoot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trainedDaysThisWeek.count) of \(streakTarget) training days this week")
    }

    /// Pips only — the letter row clipped in the band's fixed tile height, and the
    /// today-ring + fill already say everything the letters did at this size.
    private func dayPip(_ day: Int) -> some View {
        let trained = trainedDaysThisWeek.contains(day)
        let isToday = day == todayIndex
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(trained ? SettColor.heroCyan : SettColor.cardNested)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(trained ? .clear
                                  : (isToday ? SettColor.heroCyan.opacity(0.7) : SettColor.cardBorder),
                                  lineWidth: 1)
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }

    // MARK: - THE ROAD (scrolls; the rail draws in its background layer)

    private var road: some View {
        let pastRows = pastSealedWorkouts
        return VStack(alignment: .leading, spacing: 0) {
            if !finishedWorkouts.isEmpty {
                // The PAST rides above the seal: the ALL SCANS corner link, then up
                // to two older medallions, oldest furthest up the fading rail.
                pastSection(pastRows)
                    .fusionPop(0.3, active: roadShown, animated: animatedBoot)
                    .padding(.top, 10)
            } else {
                Color.clear.frame(height: 16)
            }
            if let last = lastSealedWorkout {
                sealNode(last)
                    .fusionPop(0.34, active: roadShown, animated: animatedBoot)
                    .padding(.bottom, 16)
            }
            todayNode
                .fusionPop(0.42, active: roadShown, animated: animatedBoot)
                .padding(.bottom, 20)
            weekCluster
                .fusionPop(0.52, active: roadShown, animated: animatedBoot)
                .padding(.bottom, 28)
            vexethNode
                .fusionPop(0.62, active: roadShown, animated: animatedBoot)
                .padding(.bottom, 32)
            gateNode
                .fusionPop(0.7, active: roadShown, animated: animatedBoot)
        }
        .backgroundPreferenceValue(FusionStopKey.self) { anchors in
            GeometryReader { geo in
                rail(in: geo, anchors: anchors, fadesPast: !pastRows.isEmpty)
            }
        }
    }

    // MARK: Rail (layered-stroke glow — never an animated shadow)

    /// The cyan spine starts at y = 0 — the top edge of the scroll content — so it
    /// visually pours out of the glance band's exit tick under the POWER tile.
    @ViewBuilder
    private func rail(in geo: GeometryProxy, anchors: [FusionStop: Anchor<CGPoint>],
                      fadesPast: Bool) -> some View {
        if let todayAnchor = anchors[.today] {
            let x = geo[todayAnchor].x
            let weekEndY = anchors[.weekEnd].map { geo[$0].y } ?? (geo[todayAnchor].y + 56)
            ZStack {
                spine(x: x, endY: weekEndY, in: geo,
                      fadeToY: fadesPast ? anchors[.seal].map { geo[$0].y } : nil)
                if let vexethAnchor = anchors[.vexeth] {
                    let vexethY = geo[vexethAnchor].y
                    // The last walked stretch turns crimson: Vexeth is ON the road.
                    // It stops at his marker and NEVER runs on toward the gold gate.
                    glowStroke(FusionRailSegment(from: CGPoint(x: x, y: weekEndY),
                                                 to: CGPoint(x: x, y: vexethY - 22)),
                               trim: crimsonTrim, color: SettColor.villainCrimson)
                    if let gateAnchor = anchors[.gate] {
                        // Past the rival the road is unwalked — a faint iron dash,
                        // keeping crimson and gold apart.
                        FusionRailSegment(from: CGPoint(x: x, y: vexethY + 22),
                                          to: CGPoint(x: x, y: geo[gateAnchor].y - 18))
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

    /// The cyan spine — full strength from the seal node down; when the PAST rides
    /// above it, the stretch up through the medallions fades toward history. The
    /// fade is a static mask over the ONE trimmed path, so the boot still draws a
    /// single connected stroke out of the band's exit tick.
    @ViewBuilder
    private func spine(x: CGFloat, endY: CGFloat, in geo: GeometryProxy,
                       fadeToY: CGFloat?) -> some View {
        let stroke = glowStroke(FusionRailSegment(from: CGPoint(x: x, y: 0),
                                                  to: CGPoint(x: x, y: endY)),
                                trim: cyanTrim, color: SettColor.heroCyan)
        if let fadeToY, geo.size.height > 1 {
            let frac = max(0.02, min(1, fadeToY / geo.size.height))
            stroke.mask {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.14), location: 0),
                    .init(color: .black, location: frac),
                    .init(color: .black, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        } else {
            stroke
        }
    }

    /// Soft ki glow: three layered strokes of the same trimmed segment (wide faint
    /// halo → mid wash → hot core). Static styling; only the trim animates, once.
    private func glowStroke(_ segment: FusionRailSegment, trim: CGFloat, color: Color) -> some View {
        ZStack {
            segment.trim(from: 0, to: trim)
                .stroke(color.opacity(0.12), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            segment.trim(from: 0, to: trim)
                .stroke(color.opacity(0.32), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            segment.trim(from: 0, to: trim)
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: The PAST — older medallions up the fading rail + the ALL SCANS link

    /// The road behind the seal node: the ALL SCANS corner chip, then up to two
    /// older sealed sessions as compact medallions (oldest at the top, where the
    /// rail fades off into history).
    private func pastSection(_ workouts: [Workout]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                allScansChip
            }
            ForEach(workouts) { workout in
                pastMedallionRow(workout)
            }
        }
        .padding(.bottom, workouts.isEmpty ? 6 : 10)
    }

    /// The corner link into the full log — a mono chip in cyan (the action voice).
    private var allScansChip: some View {
        NavigationLink {
            HistoryListView()
        } label: {
            Text("ALL SCANS ›")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.heroCyan)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(SettColor.card.opacity(0.6), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("All scans")
        .accessibilityHint("Opens the full workout history")
    }

    /// One session further back up the road — quieter chrome than the seal node,
    /// same destination on tap.
    private func pastMedallionRow(_ workout: Workout) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(SettColor.card)
                    Circle().strokeBorder(SettColor.heroCyan.opacity(0.28), lineWidth: 1)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SettColor.heroCyan.opacity(0.55))
                }
                .frame(width: 20, height: 20)
                .frame(width: Self.railColumnWidth)
                Text(workout.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SettColor.bone.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(pastDateLabel(workout))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(0.5)
                    .foregroundStyle(SettColor.ash)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let delta = plDelta(for: workout) {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) PL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .kerning(0.5)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.deltaInk(delta))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettColor.deltaInk(delta).opacity(0.12), in: Capsule())
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel(pastMedallionAccessibility(workout))
        .accessibilityHint("Opens the workout's details")
    }

    /// "YESTERDAY" / "2 DAYS AGO" — the medallions read as distance, not dates.
    private func pastDateLabel(_ workout: Workout) -> String {
        workout.startedAt
            .formatted(.relative(presentation: .named))
            .uppercased()
    }

    private func pastMedallionAccessibility(_ workout: Workout) -> String {
        var parts = ["\(workout.title), \(pastDateLabel(workout).lowercased())"]
        if let delta = plDelta(for: workout) {
            parts.append(delta == 0 ? "no power change"
                                    : "\(delta > 0 ? "up" : "down") \(abs(delta)) power level")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Seal node — the last sealed session, a medallion just behind you

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
                .anchorPreference(key: FusionStopKey.self, value: .center) { [.seal: $0] }
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

    // MARK: Today node — THE doorway on the line (four faces)

    private var todayNode: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                FusionKiNodeMarker(sealed: trainedToday)
                    .frame(width: Self.railColumnWidth)
                    .anchorPreference(key: FusionStopKey.self, value: .center) { [.today: $0] }
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
            if showsQuickStartGhost {
                quickStartGhost
                    .padding(.leading, Self.railColumnWidth + 14)
            }
        }
    }

    private static let railColumnWidth: CGFloat = 40
    /// Live face carries the START capsule inside the art, so it stands taller
    /// than the sealed/rest faces (which cooled back down to doorway height).
    private let liveHeroHeight: CGFloat = 168
    private let quietHeroHeight: CGFloat = 132

    /// The ghost quick start rides UNDER the doorway (a sibling button — never a
    /// nested tap target). Live + rest faces only; sealed needs no second door.
    private var showsQuickStartGhost: Bool {
        guard !finishedWorkouts.isEmpty, !trainedToday else { return false }
        return isRestDay || todaysRoutine != nil
    }

    /// The LIVE face — realm doorway, routine + ~min + surge chip, and the
    /// scouter-green START capsule (the session's live-instrument hue). The whole
    /// card is one button; the capsule is its visual trigger.
    private var directiveCard: some View {
        Button {
            startPrimary()
        } label: {
            RealmDoorwayCard(asset: launchRealmAsset, emphasized: true, height: liveHeroHeight) {
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
                        StatusChip("SURGE ARMED · ×1.25", tint: SettColor.heroCyan, icon: "bolt.fill")
                            .accessibilityLabel("Rested surge armed — this session counts extra")
                    }
                    startCapsule
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } accessory: {
                EmptyView()
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Quick start a workout")
    }

    /// The GO control — scouter green, etch ink. Decorative inside the card button
    /// (the card commits the action), styled exactly like the session's grammar.
    private var startCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
            Text("START")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(2)
        }
        .foregroundStyle(SettColor.etch)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(TimeChamber.scouterGreen, in: Capsule())
        .accessibilityHidden(true) // the card button carries the label
    }

    /// The SEALED face — today's stop already stamped: ΔPL (gold on a gain, per
    /// the color law) and the next stop named. The corridor has cooled.
    private var sealedTodayCard: some View {
        RealmDoorwayCard(asset: launchRealmAsset, emphasized: false, height: quietHeroHeight) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow("SEALED · TODAY", tint: SettColor.heroCyan)
                if let delta = todaysPLDelta {
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) ΔPL")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
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
                    Text("NEXT STOP: \(next.name.uppercased()) · \(next.day)")
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
                .font(.system(size: 26, weight: .bold))
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
        RealmDoorwayCard(asset: launchRealmAsset, emphasized: false, height: quietHeroHeight) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("REST STOP · SURGE BANKS", tint: SettColor.heroCyan)
                Text("A full rest day arms tomorrow's session ×1.25")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } accessory: {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
        }
        .saturation(0.65)
        .brightness(-0.04)
    }

    /// Day zero: the road's first step, same doorway grammar, same green GO.
    private var firstDirectiveCard: some View {
        Button {
            session.quickStart()
        } label: {
            RealmDoorwayCard(asset: ChamberBackground.resolve(services.settings.chamberBackground).assetName,
                             emphasized: true, height: liveHeroHeight) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("FIRST STEP", tint: SettColor.heroCyan)
                    Text("Enter the corridor")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    Text("YOUR ROAD STARTS AT THIS DOOR")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.75))
                    startCapsule
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } accessory: {
                EmptyView()
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

    // MARK: Week cluster — the remaining stops, compressed, target tick marked

    /// Tapping the cluster opens the streak sheet — the week IS the streak.
    /// Counts (pips, n/target, streak weeks) are BAND-OWNED now: the cluster keeps
    /// only its named weekday stops, the YOU marker above it, and the streak-target
    /// tick (+SEALED chip once the week's ask is met — passed, so it leads).
    private var weekCluster: some View {
        Button {
            Haptics.light()
            isShowingStreak = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if daysStillNeeded == 0 {
                    targetRow(met: true)
                        .padding(.bottom, 2)
                }
                ForEach(Array(remainingDayIndices.enumerated()), id: \.element) { position, day in
                    ghostStopRow(day: day)
                    if daysStillNeeded > 0, position + 1 == daysStillNeeded {
                        targetRow(met: false)
                    }
                }
                if daysStillNeeded > remainingDayIndices.count {
                    // The target can't land inside the remaining stops (short week or
                    // deep target) — mark it quietly at the cluster's end, never a scold.
                    targetRow(met: false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .anchorPreference(key: FusionStopKey.self, value: .bottom) { [.weekEnd: $0] }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekClusterAccessibility)
        .accessibilityHint("Shows streak rules and this week's progress")
    }

    /// A ghost stop: hollow marker on the rail, weekday letter, and (weekday mode)
    /// the routine scheduled to fire there.
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
        .frame(height: 21)
    }

    /// The streak-target tick crossing the rail where the week's ask would be met —
    /// and, once met, the quiet SEALED chip. The counts themselves live in the band.
    private func targetRow(met: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(SettColor.heroCyan.opacity(0.7))
                .frame(width: 16, height: 2)
                .frame(width: Self.railColumnWidth)
            Text("STREAK TARGET")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.heroCyan.opacity(0.9))
            if met {
                StatusChip("SEALED", tint: SettColor.heroCyan, icon: "flame.fill")
            }
            Spacer(minLength: 0)
        }
        .frame(height: met ? 24 : 16)
    }

    private var weekClusterAccessibility: String {
        let met = daysStillNeeded == 0
        let ahead = remainingDayIndices.count
        return met
            ? "Week sealed, \(trainedDaysThisWeek.count) of \(streakTarget) days trained"
            : "\(ahead) day\(ahead == 1 ? "" : "s") left this week, \(daysStillNeeded) more to hit the streak target"
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
            .anchorPreference(key: FusionStopKey.self, value: .center) { [.vexeth: $0] }
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
            FusionGateShape()
                .stroke(SettColor.saiyanGold.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 18, height: 22)
                .auraGlow(SettColor.saiyanGold.opacity(0.5), radius: 5)
                .frame(width: Self.railColumnWidth)
                .anchorPreference(key: FusionStopKey.self, value: .center) { [.gate: $0] }
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

    // MARK: - Boot orchestration (ONE connected reveal, once per session)

    private func boot() {
        let pl = services.progression.snapshotPowerLevel
        // Replays (tab return, sheet dismissal, nav pop) and Reduce Motion land
        // everything instantly — the entrance is a first-impression, not a loop.
        if Self.hasBootedThisSession || reduceMotion {
            Self.hasBootedThisSession = true
            booted = true
            roadShown = true
            plShown = pl
            cyanTrim = 1
            crimsonTrim = 1
            ghostOpacity = 1
            return
        }
        Self.hasBootedThisSession = true
        animatedBoot = true

        // Phase 1 — the glance scans in (~0.35 s): tiles stagger + digits scramble.
        booted = true // tiles animate via their delayed .animation(value:)
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { plShown = pl }

        // Phase 2 — the rail draws out of the band (~0.45 s), nodes pop as it passes.
        withAnimation(.easeInOut(duration: 0.3).delay(0.32)) { cyanTrim = 1 }
        withAnimation(.easeOut(duration: 0.12).delay(0.62)) { crimsonTrim = 1 }
        withAnimation(.easeOut(duration: 0.12).delay(0.7)) { ghostOpacity = 1 }
        roadShown = true // node pops carry their own delays off this flip

        Haptics.light()
    }

    /// Boot stagger for a glance tile — shared with the tiles' scramble delays.
    private func tileDelay(_ index: Int) -> Double { 0.03 + Double(index) * 0.06 }

    // MARK: - Derivations (mirroring HomeTabView so the surfaces never disagree)

    /// The most recent sealed session that is NOT today's — today's belongs to the
    /// today node. When today is untrained this is simply the latest workout.
    private var lastSealedWorkout: Workout? {
        finishedWorkouts.first { !Calendar.current.isDateInToday($0.startedAt) }
    }

    /// Up to two sealed sessions BEHIND the seal node, most distant first — the
    /// road's past runs upward, so the oldest medallion sits furthest up the fade.
    private var pastSealedWorkouts: [Workout] {
        let past = finishedWorkouts.filter { !Calendar.current.isDateInToday($0.startedAt) }
        return Array(past.dropFirst().prefix(2).reversed())
    }

    /// Extract set samples ONCE per appearance/finish and fold them through the
    /// shared WeeklyHardSets engine — never a SwiftData walk in `body`.
    private func refreshWeeklySets() {
        let samples = SampleExtractor.setSamples(context: modelContext)
        weeklyHardSets = WeeklyHardSets.total(samples: samples, calendar: Self.isoCalendar)
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

    /// The week's real ask — the frequency goal, capped by the weekday schedule.
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

    /// The week's stops still ahead of today (Monday-indexed).
    private var remainingDayIndices: [Int] {
        todayIndex < 6 ? Array((todayIndex + 1)...6) : []
    }

    /// Days still needed this week to hit the streak target.
    private var daysStillNeeded: Int {
        max(0, streakTarget - trainedDaysThisWeek.count)
    }

    /// A weekday-mode planned rest (routines exist, none scheduled today).
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

    private var scheduledDayNames: [String] {
        let mask = Scheduling.orderedActive(routines).reduce(0) { $0 | $1.daysOfWeekMask }
        return (0 ..< 7).compactMap { day in
            TrainDays.isSet(mask, day: day) ? TrainDays.shortNames[day].uppercased() : nil
        }
    }

    /// Weekday-mode: the routine scheduled on a given future day (rotation shows
    /// none — the cycle only knows its next stop, which the today node names).
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

    /// Typical wall-clock minutes from this routine's own finished sessions —
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

    /// The next stop after a sealed today — rotation's next-up, or the next
    /// scheduled weekday within a week. Mirrors classic.
    private var nextSessionInfo: (name: String, day: String)? {
        let active = Scheduling.orderedActive(routines)
        guard !active.isEmpty else { return nil }
        switch services.settings.scheduleMode {
        case .rotation:
            guard let next = Scheduling.nextRoutine(routines, settings: services.settings) else { return nil }
            return (next.name, "UP NEXT")
        case .weekday:
            let calendar = Self.isoCalendar
            for offset in 1 ... 7 {
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

// MARK: - Glance tile chrome (Briefing's grammar, compressed)

/// One compressed HUD tile: a mono eyebrow with a hairline rule that DRAWS on
/// boot, content below, a quiet slab behind. `rimTint` (Vexeth's crimson) tints
/// the frame; nil keeps the neutral hairline. Entrances stagger off `index` so
/// the band scans in top-to-bottom. `animated` is false on Reduce Motion AND on
/// any replay after the session's one boot: everything lands instantly.
private struct FusionTile<Content: View>: View {
    let label: String
    var labelTint: Color = SettColor.ash
    var rimTint: Color? = nil
    let index: Int
    let booted: Bool
    let animated: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(labelTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Rectangle()
                    .fill(rimTint?.opacity(0.35) ?? SettColor.cardBorder)
                    .frame(height: 1)
                    .scaleEffect(x: booted ? 1 : 0, anchor: .leading)
                    .animation(animated ? .easeOut(duration: 0.25).delay(delay + 0.05) : nil,
                               value: booted)
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettColor.card.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(rimTint?.opacity(0.4) ?? SettColor.cardBorder, lineWidth: 1)
                }
        }
        .opacity(booted ? 1 : 0)
        .offset(y: booted ? 0 : 4)
        .animation(animated ? .easeOut(duration: 0.2).delay(delay) : nil, value: booted)
    }

    private var delay: Double { 0.03 + Double(index) * 0.06 }
}

// MARK: - Scramble numeral (Briefing's boot flicker, shortened to fit ~350 ms)

/// A mono readout whose DIGITS flicker through 3 scramble frames before settling.
/// Letters and punctuation hold still so the line never reads as garbage. Reduce
/// Motion, a replayed mount, or an already-settled boot render the value directly.
private struct FusionScramble: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = SettColor.bone
    var delay: Double = 0
    var active: Bool
    var animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String
    @State private var run: Task<Void, Never>?
    @State private var fired = false

    init(_ text: String, size: CGFloat = 13, color: Color = SettColor.bone,
         delay: Double = 0, active: Bool, animated: Bool) {
        self.text = text
        self.size = size
        self.color = color
        self.delay = delay
        self.active = active
        self.animated = animated
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
        guard animated, !reduceMotion else {
            shown = text
            return
        }
        run?.cancel()
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            var rng = FusionRNG(seed: UInt64(truncatingIfNeeded: text.hashValue) | 1)
            for _ in 0 ..< 3 {
                guard !Task.isCancelled else { return }
                shown = String(text.map { ch in
                    ch.isNumber ? Self.digits[min(9, Int(rng.unit() * 10))] : ch
                })
                try? await Task.sleep(for: .milliseconds(40))
            }
            guard !Task.isCancelled else { return }
            shown = text
        }
    }

    private static let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
}

/// Minimal seeded LCG (Knuth MMIX) for the scramble frames — never SystemRandom
/// in a render path, matching the app's deterministic-chrome rule.
private struct FusionRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - Road plumbing (anchors, rail geometry, node chrome)

/// The stops whose rail geometry the background path needs. Week ghost stops sit
/// on the line but don't bend it, so only the cluster's end is anchored.
private enum FusionStop: Hashable {
    case seal, today, weekEnd, vexeth, gate
}

private struct FusionStopKey: PreferenceKey {
    static let defaultValue: [FusionStop: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [FusionStop: Anchor<CGPoint>],
                       nextValue: () -> [FusionStop: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One straight rail segment in the road's own coordinate space. Drawn with
/// absolute points (the shape ignores its rect), so `.trim` gives the draw-on.
private struct FusionRailSegment: Shape {
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
private struct FusionGateShape: Shape {
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
private struct FusionKiNodeMarker: View {
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

// MARK: - Node entrance (pop as the rail passes — keyed off the shared boot)

/// Quick assemble (opacity + slight leading-anchored scale) keyed off the shared
/// `roadShown` flip so every node joins the ONE connected reveal — never a
/// per-node onAppear, which would replay on scroll or navigation. `animated` is
/// false on Reduce Motion and on any post-boot replay: nodes land instantly.
private struct FusionPop: ViewModifier {
    let delay: Double
    let active: Bool
    let animated: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .scaleEffect(active ? 1 : 0.95, anchor: .leading)
            .animation(animated ? .spring(response: 0.32, dampingFraction: 0.8).delay(delay) : nil,
                       value: active)
    }
}

private extension View {
    func fusionPop(_ delay: Double, active: Bool, animated: Bool) -> some View {
        modifier(FusionPop(delay: delay, active: active, animated: animated))
    }
}
