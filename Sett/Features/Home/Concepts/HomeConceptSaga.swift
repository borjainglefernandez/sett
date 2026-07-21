import SwiftUI
import SwiftData
import SettCore

// MARK: - HOME CONCEPT 5 — "SAGA" (card-first)
//
// Today dealt as a HAND OF OVERSIZED CARDS you swipe — one thought per card,
// collectible-grade finish. A compact gold crest floats above a full-height
// pager of 4:5 cards (neighbors peeking at the edges), page dots in iron below.
//
// The deck: I TODAY (realm-art directive/sealed/rest faces, working play disc) ·
// II THE RACE (the ONLY crimson card — Vexeth, the gap, the taunt, the race
// sparkline) · III THE WEEK (7 slots + hard-set volume vs the landmarks; taps
// open the streak sheet) · IV THE CAST (patron of the day + a sealed whisper) ·
// V LAST SCAN (the receipt).
//
// SIGNATURE MOTION — FOIL: as the deck drags, the active card's rim runs an
// angular chrome gradient keyed to its page offset and the face catches a
// diagonal glaze, plus a ~3° trading-card tilt. Gradient/opacity/transform
// only — no blur, no repeatForever — and Reduce Motion holds the deck flat
// with a static sheen. Entrance: the five cards deal in from the right with a
// sub-600 ms stagger.

/// One fixed corner radius so all five cards read as ONE deck (the hudCard
/// groove grammar scaled up for the oversized 4:5 slab).
private let sagaCardRadius: CGFloat = 22

// MARK: - Pages

private enum SagaPage: String, CaseIterable, Hashable {
    case today, race, week, cast, scan

    var title: String {
        switch self {
        case .today: "Today"
        case .race: "The race"
        case .week: "The week"
        case .cast: "The cast"
        case .scan: "Last scan"
        }
    }

    /// Card tint. Crimson belongs to Vexeth's card and nothing else in the deck.
    var tint: Color {
        self == .race ? SettColor.villainCrimson : SettColor.heroCyan
    }
}

// MARK: - Derived caches (relationship walks live OFF `body`, per the CPU traps)

private struct SagaWeekStats {
    let sessions: Int
    let hardSets: Int
    let reps: Int
    let tonnageGrams: Int
    let groupsInZone: Int
    let groupsTotal: Int
}

private struct SagaScanStats {
    let sets: Int
    let reps: Int
    let tonnageGrams: Int
}

// MARK: - The view

struct HomeConceptSagaView: View {
    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var finishedWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var frequencyGoals: [Goal]

    /// The aligned card (drives the dots; dots drive it back).
    @State private var activePage: SagaPage? = .today
    @State private var isShowingStreak = false
    /// Flips once on appear — every card animates in off it with its own delay.
    @State private var dealtIn = false
    /// Today's working tonnage for the SEALED face — a relationship walk, cached.
    @State private var sealedTonnageGrams: Int?
    /// This week's set walk for THE WEEK card — cached, never computed in `body`.
    @State private var weekStats: SagaWeekStats?
    /// The last session's receipt numbers — cached from the same walk.
    @State private var lastScanStats: SagaScanStats?
    /// The 8-week you-vs-Vexeth race, cached for the sparkline.
    @State private var raceLines: [(you: Int, rival: Int)] = []

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
        VStack(spacing: 10) {
            header
            deck
            pageDots
        }
        // The floating tab bar lives below — the dots must clear it.
        .padding(.bottom, 78)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dungeonBackground()
        .task(id: finishedWorkouts.count) { refreshDerived() }
        .onAppear { dealtIn = true }
        .onChange(of: activePage) { _, _ in Haptics.selection() }
        .sheet(isPresented: $isShowingStreak) {
            StreakSheet(state: streakState,
                        mode: services.settings.scheduleMode,
                        scheduledDays: scheduledDayNames,
                        plMultiplier: services.progression.snapshot?.consistencyMultiplier,
                        daysSinceLastWorkout: daysSinceLastWorkout)
        }
    }

    // MARK: Header — the crest above the deck (gold is the PL's alone)

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                    .uppercased())
            if services.progression.snapshotPowerLevel > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    SacredNumberView(value: services.progression.snapshotPowerLevel, size: .m)
                    Text(UserForm.form(forPL: services.progression.snapshotPowerLevel).title)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.heroCyan)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Power level \(services.progression.snapshotPowerLevel), \(UserForm.form(forPL: services.progression.snapshotPowerLevel).title.capitalized)")
            } else {
                Text("The deck is dealt.")
                    .font(.headline)
                    .foregroundStyle(SettColor.bone)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // The floating gear overlay owns the top-right corner — stay clear of it.
        .padding(.trailing, 56)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The deck — a view-aligned pager with true neighbor peek

    /// TabView(.page) can't show resting neighbor peek, so the deck is the modern
    /// idiom for the same gesture: a view-aligned horizontal ScrollView whose card
    /// width leaves a sliver of the adjacent cards visible at rest.
    private var deck: some View {
        GeometryReader { geo in
            // 4:5 cards sized to the deck: width-led, capped by available height.
            let cardHeight = min((geo.size.width - 64) * 1.25, geo.size.height)
            let cardWidth = cardHeight * 0.8
            let margin = max((geo.size.width - cardWidth) / 2, 0)
            let deckMidX = geo.frame(in: .global).midX
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(SagaPage.allCases.enumerated()), id: \.element) { index, page in
                        card(for: page, deckMidX: deckMidX)
                            .frame(width: cardWidth, height: cardHeight)
                            // Deal-in: each card slides in from the right, staggered.
                            // RM: a plain fade, no travel, no stagger.
                            .opacity(dealtIn ? 1 : 0)
                            .offset(x: dealtIn || reduceMotion ? 0 : 90 + CGFloat(index) * 30)
                            .animation(reduceMotion
                                       ? .easeOut(duration: 0.25)
                                       : .spring(response: 0.4, dampingFraction: 0.8)
                                           .delay(Double(index) * 0.06),
                                       value: dealtIn)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $activePage)
            // Tilted card corners and drop shadows may cross the deck bounds.
            .scrollClipDisabled()
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func card(for page: SagaPage, deckMidX: CGFloat) -> some View {
        switch page {
        case .today: todayCard(deckMidX: deckMidX)
        case .race: raceCard(deckMidX: deckMidX)
        case .week: weekCard(deckMidX: deckMidX)
        case .cast: castCard(deckMidX: deckMidX)
        case .scan: scanCard(deckMidX: deckMidX)
        }
    }

    // MARK: Page dots — iron, with the active dot wearing its card's tint

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(SagaPage.allCases, id: \.self) { page in
                let active = page == (activePage ?? .today)
                Capsule()
                    .fill(active ? page.tint : SettColor.iron.opacity(0.45))
                    .frame(width: active ? 18 : 5, height: 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy) { activePage = page }
                    }
                    .accessibilityLabel(page.title)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .animation(.snappy(duration: 0.2), value: activePage)
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - CARD I — TODAY (three faces; the slot never moves)

    @ViewBuilder
    private func todayCard(deckMidX: CGFloat) -> some View {
        if trainedToday {
            sealedFace(deckMidX: deckMidX)
        } else if isRestDay {
            restFace(deckMidX: deckMidX)
        } else {
            directiveFace(deckMidX: deckMidX)
        }
    }

    /// The directive face — the whole card starts the session; the quick-start
    /// ghost is a SIBLING overlay button, so the two tap targets never nest.
    private func directiveFace(deckMidX: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Button {
                if let routine = todaysRoutine { session.start(routine: routine) }
                else { session.quickStart() }
            } label: {
                SagaCardShell(tint: SettColor.heroCyan, deckMidX: deckMidX) {
                    realmArt(dimmed: false)
                } content: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Eyebrow("I · TODAY", tint: SettColor.heroCyan)
                            Spacer()
                            if surgeArmed {
                                StatusChip("SURGE ARMED", tint: SettColor.heroCyan, icon: "bolt.fill")
                            }
                        }
                        Spacer(minLength: 0)
                        Eyebrow(directiveContext, tint: SettColor.ash)
                        Text(directiveTitle)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                        Text(directiveSubline)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack {
                            Spacer()
                            playDisc
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .buttonStyle(PressableSlabStyle(haptic: .light))
            .accessibilityLabel(todaysRoutine.map { "Start \($0.name)" } ?? "Start a workout")

            if todaysRoutine != nil {
                quickStartGhost
                    .padding(.leading, 20)
                    .padding(.bottom, 34)
            }
        }
    }

    /// The SEALED face — today's work landed; the card becomes the day's trophy.
    private func sealedFace(deckMidX: CGFloat) -> some View {
        SagaCardShell(tint: SettColor.heroCyan, deckMidX: deckMidX) {
            realmArt(dimmed: false)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Eyebrow("I · TODAY", tint: SettColor.heroCyan)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(SettColor.heroCyan.opacity(0.9))
                        .shadow(color: SettColor.heroCyan.opacity(0.4), radius: 5)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Eyebrow("SEALED · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())",
                        tint: SettColor.ash)
                if let delta = todaysPLDelta {
                    // Gold only when power was GAINED — a reward, per the color law.
                    Text("\(delta >= 0 ? "+" : "")\(delta.formatted()) ΔPL")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
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
                    Text("NEXT: \(next.name.uppercased()) · \(next.day)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The REST face — a banked surge, never a nag. Quick start stays available
    /// as the quiet ghost.
    private func restFace(deckMidX: CGFloat) -> some View {
        SagaCardShell(tint: SettColor.heroCyan, deckMidX: deckMidX) {
            realmArt(dimmed: true)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow("I · TODAY", tint: SettColor.heroCyan)
                    Spacer()
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.45))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Eyebrow("REST DAY · SURGE BANKS", tint: SettColor.ash)
                Text("A full rest day arms tomorrow's session ×1.25")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                quickStartGhost
                    .padding(.top, 2)
            }
        }
    }

    /// A dimmed sliver of the realm art with a bottom-weighted scrim so the
    /// card's numerals always read against the sky.
    private func realmArt(dimmed: Bool) -> some View {
        ZStack {
            Image(launchRealmAsset)
                .resizable()
                .aspectRatio(contentMode: .fill)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.18), location: 0.34),
                .init(color: .black.opacity(0.30), location: 0.62),
                .init(color: .black.opacity(0.86), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .saturation(dimmed ? 0.65 : 1)
        .brightness(dimmed ? -0.04 : 0)
        .accessibilityHidden(true)
    }

    private var playDisc: some View {
        ZStack {
            Circle()
                .fill(SettColor.heroCyan)
                .frame(width: 60, height: 60)
                .shadow(color: SettColor.heroCyan.opacity(0.5), radius: 8, y: 2)
            Image(systemName: "play.fill")
                .font(.system(size: 24, weight: .bold))
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
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("Start an empty workout")
    }

    private var directiveTitle: String {
        if let routine = todaysRoutine { return routine.name }
        return finishedWorkouts.isEmpty ? "Enter the chamber" : "Quick Start"
    }

    /// "NEXT DIRECTIVE · <why now>" — the weekday it fires on, or its slot in
    /// the rotation. Same position math as the Train tab, so they never disagree.
    private var directiveContext: String {
        guard let routine = todaysRoutine else {
            return finishedWorkouts.isEmpty ? "FIRST DIRECTIVE" : "NEXT DIRECTIVE"
        }
        switch services.settings.scheduleMode {
        case .weekday:
            return "NEXT DIRECTIVE · \(Date.now.formatted(.dateTime.weekday(.wide)).uppercased())"
        case .rotation:
            let order = Scheduling.orderedActive(routines)
            let pos = (order.firstIndex { $0.id == routine.id } ?? 0) + 1
            return "NEXT DIRECTIVE · CYCLE \(pos)/\(order.count)"
        }
    }

    private var directiveSubline: String {
        if let routine = todaysRoutine {
            let count = routine.orderedExercises.count
            var line = "\(count) EXERCISE\(count == 1 ? "" : "S")"
            if let mins = typicalRoutineMinutes(routine) { line += " · ~\(mins) MIN" }
            return line
        }
        return finishedWorkouts.isEmpty ? "YOUR TRAINING ARC STARTS HERE"
                                        : "EMPTY CHAMBER — LOG AS YOU GO"
    }

    // MARK: - CARD II — THE RACE (the one crimson card)

    private func raceCard(deckMidX: CGFloat) -> some View {
        let rival = services.progression.effectiveRival
        let pl = services.progression.snapshotPowerLevel
        let gap = rival.pl - pl
        let pace = services.progression.trailingWeeklyPace
        let growth = services.progression.effectiveRivalGrowth
        return SagaCardShell(tint: SettColor.villainCrimson, deckMidX: deckMidX) {
            crimsonVoid
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("II · THE RACE", tint: SettColor.villainCrimson)
                    Spacer()
                    StatusChip("CYCLE \(services.progression.rivalCycle)",
                               tint: SettColor.villainCrimson)
                }
                HStack(spacing: 12) {
                    VexethPortraitView(form: rival.form)
                        .frame(width: 54, height: 54)
                        .background(SettColor.villainVoid,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(SettColor.villainCrimson.opacity(0.4), lineWidth: 1)
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(VexethArtwork.title(for: rival.form).uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(SettColor.villainCrimson)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("“\(services.progression.rivalTaunt)”")
                            .font(.footnote)
                            .foregroundStyle(SettColor.ash)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("THE GAP", tint: SettColor.ash)
                    PowerNumeral(abs(gap), size: .xl, color: SettColor.villainCrimson)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(gap > 0 ? "PL AHEAD" : "PL BEHIND YOU")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(gap > 0 ? SettColor.ash : SettColor.bone)
                    if gap > 0, pace > growth {
                        Text("CATCH IN \(Int((Double(gap) / Double(pace - growth)).rounded(.up))) WK AT PACE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(SettColor.ash)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 2)
                if raceLines.count >= 2 {
                    raceSparkline
                }
                Text("HIM +\(growth)/WK · YOU +\(pace)/WK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .monospacedDigit()
                    .foregroundStyle(SettColor.iron)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(raceAccessibility(gap: gap, form: rival.form))
    }

    /// The crimson card's void — the rival's own darkness, a whisper of blood
    /// pooling at the top edge. Static, drawn once.
    private var crimsonVoid: some View {
        ZStack {
            Rectangle().fill(TimeChamber.void.opacity(0.84))
            LinearGradient(colors: [SettColor.villainCrimson.opacity(0.14), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .accessibilityHidden(true)
    }

    private var raceSparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let points = raceLines
                guard points.count >= 2 else { return }
                let all = points.flatMap { [$0.you, $0.rival] }
                guard let lo = all.min(), let hi = all.max(), hi > lo else { return }
                func at(_ index: Int, _ value: Int) -> CGPoint {
                    CGPoint(x: size.width * CGFloat(index) / CGFloat(points.count - 1),
                            y: (size.height - 4) * (1 - CGFloat(value - lo) / CGFloat(hi - lo)) + 2)
                }
                var you = Path()
                var rival = Path()
                for (i, p) in points.enumerated() {
                    let yp = at(i, p.you)
                    let rp = at(i, p.rival)
                    if i == 0 { you.move(to: yp); rival.move(to: rp) }
                    else { you.addLine(to: yp); rival.addLine(to: rp) }
                }
                let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                context.stroke(rival, with: .color(SettColor.villainCrimson.opacity(0.9)), style: style)
                context.stroke(you, with: .color(SettColor.bone), style: style)
                if let lastIndex = points.indices.last {
                    let yp = at(lastIndex, points[lastIndex].you)
                    let rp = at(lastIndex, points[lastIndex].rival)
                    context.fill(Path(ellipseIn: CGRect(x: rp.x - 2.5, y: rp.y - 2.5, width: 5, height: 5)),
                                 with: .color(SettColor.villainCrimson))
                    context.fill(Path(ellipseIn: CGRect(x: yp.x - 2.5, y: yp.y - 2.5, width: 5, height: 5)),
                                 with: .color(SettColor.bone))
                }
            }
            .frame(height: 40)
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                legendDot(SettColor.bone, "YOU")
                legendDot(SettColor.villainCrimson, "VEXETH")
                Spacer()
                Text("8 WK")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.iron)
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
        }
        .accessibilityHidden(true)
    }

    private func raceAccessibility(gap: Int, form: Int) -> String {
        let stance = gap > 0 ? "\(gap) power levels ahead of you" : "\(abs(gap)) power levels behind you"
        return "The race. Vexeth, form \(form), \(stance). \(services.progression.rivalTaunt)"
    }

    // MARK: - CARD III — THE WEEK (slots + the volume verdict; taps open the fire)

    private func weekCard(deckMidX: CGFloat) -> some View {
        Button {
            isShowingStreak = true
        } label: {
            SagaCardShell(tint: SettColor.heroCyan, deckMidX: deckMidX) {
                plainVoid
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Eyebrow("III · THE WEEK", tint: SettColor.heroCyan)
                        Spacer()
                        streakChip
                    }
                    daySlots
                    Text("\(trainedDaysThisWeek.count) OF \(streakTarget) DAYS SEALED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.ash)
                    sagaDivider
                    if let stats = weekStats {
                        receiptRow("HARD SETS", "\(stats.hardSets) · BAND \(VolumeLandmarks.weeklyTotalRange.lowerBound)–\(VolumeLandmarks.weeklyTotalRange.upperBound)")
                        groupsRow(stats)
                        receiptRow("SESSIONS", stats.sessions.formatted())
                        receiptRow("TONNAGE", "\(WeightFormat.compactTonnage(grams: stats.tonnageGrams, unit: services.settings.unit)) \(services.settings.unit.symbol.uppercased())")
                    } else {
                        receiptRow("SESSIONS", trainedDaysThisWeek.count.formatted())
                    }
                    Spacer(minLength: 0)
                    Eyebrow("TAP · STREAK RULES", tint: SettColor.iron)
                }
            }
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel(weekAccessibility)
        .accessibilityHint("Shows streak rules and this week's progress")
    }

    /// The flame — the streak surface's badge (cyan: the streak is ki, never gold).
    private var streakChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11))
                .foregroundStyle(SettColor.heroCyan.opacity(isRekindle ? 0.55 : 1))
            Text(isRekindle ? "RELIGHT" : "\(streakWeeks) WK")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(0.5)
                .monospacedDigit()
                .foregroundStyle(SettColor.heroCyan)
            if streakState.shields > 0 {
                Image(systemName: "shield.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(SettColor.heroCyan.opacity(0.7))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(SettColor.cardNested, in: Capsule())
        .accessibilityHidden(true)   // the card's own label carries the streak
    }

    private var daySlots: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { day in
                let trained = trainedDaysThisWeek.contains(day)
                let isToday = day == todayIndex
                Text(TrainDays.letters[day])
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(trained ? SettColor.etch
                                     : (isToday ? SettColor.heroCyan : SettColor.iron))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(trained ? SettColor.heroCyan : SettColor.cardNested)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isToday ? SettColor.heroCyan.opacity(0.8)
                                                  : SettColor.cardBorder, lineWidth: 1)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// "N OF 10 GROUPS IN ZONE" with a 10-pip strip — the week's volume verdict
    /// against the evidence-based landmarks, one pip per trainable group.
    private func groupsRow(_ stats: SagaWeekStats) -> some View {
        HStack(spacing: 8) {
            Text("IN ZONE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<stats.groupsTotal, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < stats.groupsInZone ? SettColor.heroCyan
                                                         : SettColor.cardNested)
                        .frame(width: 6, height: 9)
                }
            }
            Text("\(stats.groupsInZone)/\(stats.groupsTotal)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
        }
    }

    private var weekAccessibility: String {
        var parts = ["The week. \(trainedDaysThisWeek.count) of \(streakTarget) days sealed"]
        parts.append(isRekindle ? "streak ready to relight" : "\(streakWeeks) week streak")
        if let stats = weekStats {
            parts.append("\(stats.hardSets) hard sets")
            parts.append("\(stats.groupsInZone) of \(stats.groupsTotal) muscle groups in zone")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - CARD IV — THE CAST (the patron of the day speaks)

    private func castCard(deckMidX: CGFloat) -> some View {
        let patron = patronOfDay
        return SagaCardShell(tint: SettColor.heroCyan, deckMidX: deckMidX) {
            plainVoid
        } content: {
            VStack(spacing: 10) {
                HStack {
                    Eyebrow("IV · THE CAST", tint: SettColor.heroCyan)
                    Spacer()
                    StatusChip("\(awakenedCast.count)/7 AWAKE", tint: SettColor.ash)
                }
                Spacer(minLength: 0)
                CharacterAvatarView(character: patron,
                                    tier: services.progression.userFormTier,
                                    size: 96)
                Eyebrow("PATRON OF THE DAY", tint: SettColor.ash)
                Text(patron.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SettColor.bone)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("“\(patronLine)”")
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                Spacer(minLength: 0)
                sagaDivider
                sealedWhisper
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    /// The next voice still sealed — silhouette + the awakening whisper. When
    /// the cast is complete, a quiet line holds the slot instead.
    @ViewBuilder
    private var sealedWhisper: some View {
        if let sealed = nextSealedPatron {
            HStack(spacing: 10) {
                CharacterAvatarView(character: sealed, tier: .base, size: 38, locked: true)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("A VOICE STILL SEALED", tint: SettColor.iron)
                    Text(PatronUnlocks.requirement(for: sealed))
                        .font(.caption2)
                        .foregroundStyle(SettColor.iron)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        } else {
            Eyebrow("SEVEN VOICES · THE CAST HOLDS", tint: SettColor.iron)
        }
    }

    /// The awakened cast in canonical order — the day's patron rotates through it.
    private var awakenedCast: [CharacterKey] {
        CharacterKey.allCases.filter { services.progression.unlockedPatrons.contains($0) }
    }

    private var patronOfDay: CharacterKey {
        let cast = awakenedCast
        guard !cast.isEmpty else { return .vego }
        return cast[dayOfYear % cast.count]
    }

    private var nextSealedPatron: CharacterKey? {
        CharacterKey.allCases.first { !services.progression.unlockedPatrons.contains($0) }
    }

    /// Deterministic per calendar day (never random — no per-render flicker).
    private var patronLine: String {
        let bank = Self.castLines[patronOfDay] ?? []
        guard !bank.isEmpty else { return "" }
        return bank[dayOfYear % bank.count]
    }

    private var dayOfYear: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
    }

    /// One line per patron per day, in each voice (matching the PatronLines
    /// registers: Vego proud, Barok earthbound, Nyra precise, Torren stern,
    /// Luma nerdy-warm, Gosi hungry, Zyn quiet). Terse, zero hype.
    private static let castLines: [CharacterKey: [String]] = [
        .vego:   ["Train like the ceiling insulted you.",
                  "I watch. Impress me.",
                  "Another rung waits. Take it."],
        .gosi:   ["Something new on the plate today? Good appetite.",
                  "The early iron tastes best. Just saying.",
                  "Try a lift you've been ignoring. For me."],
        .barok:  ["Move the weight. The ground keeps count.",
                  "Slow is fine. Heavy is the point.",
                  "Stack the tons. The mountain remembers."],
        .nyra:   ["The pattern holds if you hold it.",
                  "Consistency is engineering. Show your work.",
                  "One session. That is all the record asks today."],
        .torren: ["You set the mark. Meet it.",
                  "The plan works when you do.",
                  "No shortcuts filed today. Good."],
        .luma:   ["Sleep is training the lab can't see.",
                  "Rested muscle lifts honest numbers.",
                  "Recover hard, then push. That's the protocol."],
        .zyn:    ["…still here. That counts.",
                  "…the quiet work adds up.",
                  "…back again. Good."],
    ]

    // MARK: - CARD V — LAST SCAN (the receipt)

    private func scanCard(deckMidX: CGFloat) -> some View {
        SagaCardShell(tint: SettColor.heroCyan, deckMidX: deckMidX) {
            plainVoid
        } content: {
            if let last = finishedWorkouts.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Eyebrow("V · LAST SCAN", tint: SettColor.heroCyan)
                        Spacer()
                        if let delta = lastScanDelta {
                            StatusChip("\(delta >= 0 ? "+" : "")\(delta.formatted()) ΔPL",
                                       tint: SettColor.deltaInk(delta))
                        }
                    }
                    Text(last.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("\(last.startedAt.formatted(date: .abbreviated, time: .omitted).uppercased()) · \(WorkoutFormat.duration(last.durationSeconds).uppercased())")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                    sagaDivider
                    if let stats = lastScanStats {
                        receiptRow("WORKING SETS", stats.sets.formatted())
                        receiptRow("REPS", stats.reps.formatted())
                        receiptRow("VOLUME", "\(WeightFormat.compactTonnage(grams: stats.tonnageGrams, unit: services.settings.unit)) \(services.settings.unit.symbol.uppercased())")
                    }
                    if let rating = last.ratingHalfStars {
                        HStack {
                            Text("RATED")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .kerning(1)
                                .foregroundStyle(SettColor.ash)
                            Spacer()
                            StarRatingRow(halfStars: rating, starSize: 10)
                        }
                    }
                    Spacer(minLength: 0)
                    sagaDivider
                    HStack(spacing: 6) {
                        Spacer()
                        SettSigil(size: 12, color: SettColor.iron)
                        Eyebrow("SCAN FILED", tint: SettColor.iron)
                        Spacer()
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    SettSigil(size: 26, color: SettColor.ash.opacity(0.7))
                    Eyebrow("NO SCANS YET")
                    Text("The album opens with your first session.")
                        .font(.footnote)
                        .foregroundStyle(SettColor.ash)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The last training day's ΔPL — read from the in-memory trajectory (never
    /// SwiftData), so it's safe in `body`. nil before two points.
    private var lastScanDelta: Int? {
        let history = services.progression.snapshot?.powerLevelHistory ?? []
        guard history.count >= 2 else { return nil }
        return history[history.count - 1].pl - history[history.count - 2].pl
    }

    // MARK: - Shared card furniture

    private var plainVoid: some View {
        Rectangle()
            .fill(TimeChamber.void.opacity(0.82))
            .accessibilityHidden(true)
    }

    /// The receipt's perforation — a dashed iron hairline.
    private var sagaDivider: some View {
        SagaDashedLine()
            .stroke(SettColor.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func receiptRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Derivations (mirroring HomeTabView so the two Homes never disagree)

    private var surgeArmed: Bool {
        services.progression.snapshot?.restedBonusActive == true
    }

    private var todaysRoutine: Routine? {
        Scheduling.nextRoutine(routines, settings: services.settings)
    }

    private var weeklyGoalTarget: Int {
        frequencyGoals.first?.targetValue ?? 3
    }

    /// The week's real ask: the frequency goal, capped by the weekday schedule
    /// (you can't owe five days when only three are scheduled).
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

    /// A weekday-mode rest day: nothing scheduled today, but routines DO exist.
    private var isRestDay: Bool {
        services.settings.scheduleMode == .weekday
            && todaysRoutine == nil
            && !Scheduling.orderedActive(routines).isEmpty
    }

    private var daysSinceLastWorkout: Int? {
        guard let last = finishedWorkouts.first?.startedAt else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: last),
                                  to: cal.startOfDay(for: .now)).day
    }

    /// Today's ΔPL — the jump from the previous training day's landing to now.
    private var todaysPLDelta: Int? {
        let history = services.progression.snapshot?.powerLevelHistory ?? []
        guard history.count >= 2 else { return nil }
        return history[history.count - 1].pl - history[history.count - 2].pl
    }

    /// The next session the schedule points at — for the SEALED face's forward look.
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

    /// The realm behind the TODAY card: the routine's own domain, else a realm
    /// deliberately different from the home sky so the card reads as a place.
    private var launchRealmAsset: String {
        if let raw = todaysRoutine?.domainRaw {
            return ChamberBackground.resolve(raw).assetName
        }
        let home = ChamberBackground.resolve(services.settings.chamberBackground)
        let preferred: [ChamberBackground] = [.nebula, .storm, .aurora, .volcanic, .sanctuary, .white]
        return (preferred.first { $0 != home } ?? .nebula).assetName
    }

    /// Typical wall-clock minutes for this routine from its own finished
    /// sessions (active time — pauses subtracted). nil under two real sessions.
    private func typicalRoutineMinutes(_ routine: Routine) -> Int? {
        let seconds = finishedWorkouts.compactMap { workout -> Int? in
            guard workout.routineID == routine.id, let ended = workout.endedAt else { return nil }
            let active = Int(ended.timeIntervalSince(workout.startedAt)) - workout.pausedSeconds
            return active > 300 ? active : nil
        }
        guard seconds.count >= 2 else { return nil }
        return max(1, Int((Double(seconds.reduce(0, +)) / Double(seconds.count) / 60).rounded()))
    }

    // MARK: - The one relationship walk (task-cached, per the CPU laws)

    /// One pass over the queried workouts fills every cached stat: the SEALED
    /// tonnage, THE WEEK's set/landmark verdict, the LAST SCAN receipt, and the
    /// race sparkline. Runs in `.task(id:)` — never in `body`.
    private func refreshDerived() {
        let calendar = Self.isoCalendar

        // THE WEEK — hard sets per muscle vs the volume landmarks.
        if let week = calendar.dateInterval(of: .weekOfYear, for: .now) {
            var muscleSets: [Muscle: Int] = [:]
            var tonnage = 0
            var reps = 0
            var sessions = 0
            for workout in finishedWorkouts where week.contains(workout.startedAt) {
                sessions += 1
                for exercise in workout.orderedExercises {
                    for set in exercise.orderedSets where !set.isWarmup {
                        muscleSets[exercise.muscle, default: 0] += 1
                        tonnage += set.weightGrams * set.reps
                        reps += set.reps
                    }
                }
            }
            var groupsTotal = 0
            var groupsInZone = 0
            for muscle in Muscle.allCases {
                guard let landmarks = VolumeLandmarks.landmarks(for: muscle) else { continue }
                groupsTotal += 1
                let sets = muscleSets[muscle] ?? 0
                if sets >= landmarks.floor && sets <= landmarks.ceiling { groupsInZone += 1 }
            }
            weekStats = SagaWeekStats(sessions: sessions,
                                      hardSets: muscleSets.values.reduce(0, +),
                                      reps: reps,
                                      tonnageGrams: tonnage,
                                      groupsInZone: groupsInZone,
                                      groupsTotal: groupsTotal)
        }

        // LAST SCAN — the receipt numbers.
        if let last = finishedWorkouts.first {
            var sets = 0
            var reps = 0
            var tonnage = 0
            for exercise in last.orderedExercises {
                for set in exercise.orderedSets where !set.isWarmup {
                    sets += 1
                    reps += set.reps
                    tonnage += set.weightGrams * set.reps
                }
            }
            lastScanStats = SagaScanStats(sets: sets, reps: reps, tonnageGrams: tonnage)
        } else {
            lastScanStats = nil
        }

        // SEALED — today's working tonnage.
        if trainedToday,
           let todays = finishedWorkouts.first(where: { Calendar.current.isDateInToday($0.startedAt) }) {
            sealedTonnageGrams = todays.orderedExercises
                .flatMap { $0.orderedSets.filter { !$0.isWarmup } }
                .reduce(0) { $0 + $1.weightGrams * $1.reps }
        } else {
            sealedTonnageGrams = nil
        }

        // THE RACE — the trailing 8-week sparkline.
        raceLines = services.progression.rivalRaceLines(weeks: 8)
            .map { (you: $0.you, rival: $0.rival) }
    }
}

// MARK: - Card shell (one frame grammar, worn by all five)

/// The oversized 4:5 slab every card wears: void (or realm art) behind a
/// continuous-corner clip, the hudCard groove (tint hairline + corner ticks),
/// and the FOIL chrome keyed to the card's live page offset. The offset is read
/// with a GeometryReader against the deck's global center — gradient, opacity
/// and a ≤3° tilt only, so the effect costs a transform, never a re-render of
/// the content. Reduce Motion pins the offset to 0: flat deck, static sheen.
private struct SagaCardShell<Background: View, Content: View>: View {
    var tint: Color
    var deckMidX: CGFloat
    @ViewBuilder var background: () -> Background
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: sagaCardRadius, style: .continuous)
            let rawT = (geo.frame(in: .global).midX - deckMidX) / max(geo.size.width, 1)
            let t: CGFloat = reduceMotion ? 0 : min(1, max(-1, rawT))
            ZStack(alignment: .topLeading) {
                background()
                content()
                    .padding(18)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(tint.opacity(0.30), lineWidth: 1) }
            .overlay {
                CornerTicksShape(length: 8, inset: 9)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            }
            .overlay { SagaFoil(tint: tint, t: t) }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            .rotation3DEffect(.degrees(Double(t) * -3),
                              axis: (x: 0, y: 1, z: 0),
                              perspective: 0.5)
        }
    }
}

/// The FOIL: an angular chrome band running the rim plus a diagonal glaze on
/// the face, both positioned by the page offset `t`. At rest (t = 0) it holds a
/// faint static sheen; dragging runs the chrome around the border like light
/// over a trading-card foil. Pure gradient + opacity — cheap by construction.
private struct SagaFoil: View {
    let tint: Color
    let t: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: sagaCardRadius, style: .continuous)
        ZStack {
            shape.strokeBorder(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .clear, location: 0.55),
                        .init(color: tint.opacity(0.75), location: 0.72),
                        .init(color: .white.opacity(0.55), location: 0.78),
                        .init(color: tint.opacity(0.5), location: 0.84),
                        .init(color: .clear, location: 1.00),
                    ]),
                    center: .center,
                    angle: .degrees(Double(t) * 160 - 55)
                ),
                lineWidth: 1.5
            )
            .opacity(0.35 + Double(abs(t)) * 0.65)

            LinearGradient(colors: [.clear, .white.opacity(0.06), .clear],
                           startPoint: UnitPoint(x: 0.1 + Double(t) * 0.9, y: 0),
                           endPoint: UnitPoint(x: 0.55 + Double(t) * 0.9, y: 1))
                .clipShape(shape)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single horizontal hairline, strokeable with a dash — the receipt perforation.
private struct SagaDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
