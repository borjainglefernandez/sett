import SwiftUI
import SwiftData
import Charts
import SettCore
import UIKit

/// Tab 4 — the character sheet (Flow 5, Dark Chamber v3):
/// (1) hero — the active character card (tier-material frame) with the Sacred
///     Number, its ember halo, and Forms-ladder progress on a Ki Gauge,
/// (2) character sheet — monospaced stat rows + a muscle-balance radar,
/// (3) Emperor Vexeth's rival card (the app's ONLY red surface),
/// (4) badge case preview, (5) character roster strip — awakened patrons are
///     selectable, sealed ones knock back with their awakening requirement,
///     and a gold "patron awakened" slab lands above the strip when a badge
///     wakes someone new.
struct PowerTabView: View {
    @Environment(ProgressionStore.self) private var progression
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query private var saiyanStates: [SaiyanState]
    @Query private var badgeAwards: [BadgeAward]
    // Mirrors of Home's streak inputs — the Character Sheet STREAK row must read the
    // SAME number Home shows (StreakEngine.streakState), not the snapshot's 2-day
    // consistency streak. Same predicates HomeTabView uses so the two never disagree.
    @Query private var finishedWorkouts: [Workout]
    @Query private var streakRoutines: [Routine]
    @Query private var frequencyGoals: [Goal]

    /// The section the sub-nav last jumped to — drives the selected chip fill. The
    /// content is one long scroll (all sections always visible), so this reflects the
    /// last tap, not a scroll position.
    @State private var activeSection: PowerSection = .form
    /// A chip tap sets this; the vertical ScrollView's ScrollViewReader watches it and
    /// scrolls (then clears it). Decoupling via state is what makes the jump reliable —
    /// wrapping the reader around the whole VStack bound the proxy to the horizontal
    /// sub-nav ScrollView instead of the content, so scrollTo silently no-op'd.
    @State private var scrollTarget: PowerSection?
    @State private var showingHowPowerWorks = false
    @State private var radarShares = [Double](repeating: 0, count: PowerTabView.radarMuscles.count)
    /// Non-nil after a roster swap — keys a one-shot cyan burst on the new avatar.
    @State private var rosterBurstID: UUID?
    /// The Sacred Number's displayed value: starts at lastViewedPowerLevel, then the
    /// on-appear roll flips it to the live PL. nil = show lastViewedPowerLevel.
    @State private var rolledPL: Int?
    /// The Ki gauge's animated fill: `gaugeStart` seeds it, `gaugeTarget` is what it
    /// fills to. `heroRoll` re-mounts the number + gauge so the odometer/fill replay
    /// on EVERY appearance with a delta (a plain @State can't re-trigger their internal
    /// roll after the first time; TabView also keeps this tab mounted).
    @State private var gaugeStart: Double = 0
    @State private var gaugeTarget: Double = 0
    @State private var heroRoll = 0
    @State private var heroRollTask: Task<Void, Never>?
    /// Requirement copy for the last sealed patron tapped — shown under the
    /// roster strip, self-clearing after ~4s. The clear task is cancelled and
    /// restarted on every knock so the copy never vanishes mid-read.
    @State private var lockedHint: String?
    @State private var lockedHintTask: Task<Void, Never>?

    init() {
        let badgeAwardFilter = #Predicate<BadgeAward> { $0.deletedAt == nil }
        _badgeAwards = Query(filter: badgeAwardFilter, sort: [SortDescriptor(\BadgeAward.earnedAt, order: .reverse)])

        // Same three queries HomeTabView uses to derive the display streak.
        let finishedFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        _finishedWorkouts = Query(filter: finishedFilter,
                                  sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])

        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _streakRoutines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])

        let goalFilter = #Predicate<Goal> { $0.kindRaw == "frequency" && $0.isActive && $0.deletedAt == nil }
        _frequencyGoals = Query(filter: goalFilter)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sticky sub-nav: pinned OUTSIDE the ScrollView so it holds under the
                // nav bar while the sections scroll beneath it. Same chip grammar as
                // ProgressTabView.sectionChips (one pattern, two tabs).
                subNav
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // At most ONE banner rides above the hero: the user's gold
                            // ascension leads (their reward beat), and only once it's
                            // acknowledged does Vexeth's crimson response surface — so a
                            // crimson banner is NEVER stacked beside the gold one (color law).
                            // Both flags are persistent, so deferring the reveal never drops it.
                            if let form = progression.pendingAscension {
                                LevelUpBanner(form: form) { withAnimation(.snappy) { progression.acknowledgeAscension() } }
                            } else if let revealForm = progression.pendingRivalFormReveal {
                                VexethRespondsBanner(form: revealForm) {
                                    withAnimation(.snappy) { progression.acknowledgeRivalFormReveal() }
                                }
                            }
                            hero
                                .id(PowerSection.form)
                            characterSheetCard
                                .id(PowerSection.sheet)
                            badgeCasePreview
                                .id(PowerSection.badges)
                            // Sits directly above the roster (not pinned at the top like
                            // the ascension banner) — the beat points at the strip where
                            // the new card just unsealed.
                            if let awakened = progression.pendingPatronAwakening {
                                patronAwakeningSlab(awakened)
                            }
                            rosterCard
                                .id(PowerSection.lineup)
                            // The crimson rival closes the sheet — last, matching the
                            // FORM/SHEET/BADGES/LINEUP/RIVAL sub-nav order, and no gold
                            // surface sits beside this, the app's only crimson card.
                            RivalCard(rivalPL: rivalPL,
                                      rivalForm: rivalForm,
                                      userPL: progression.snapshotPowerLevel,
                                      pace: progression.trailingWeeklyPace,
                                      growth: progression.effectiveRivalGrowth,
                                      cycle: progression.rivalCycle,
                                      taunt: progression.rivalTaunt,
                                      raceLines: progression.rivalRaceLines(weeks: 10),
                                      revealPending: progression.pendingRivalFormReveal != nil,
                                      rebirthAnnounce: progression.rivalRebirthAnnounce,
                                      onAcknowledgeRebirth: { withAnimation(.snappy) { progression.acknowledgeRivalRebirth() } })
                                .id(PowerSection.rival)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                }
            }
            .dungeonBackground()
            .navigationTitle("Power")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHowPowerWorks = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("How power works")
                }
            }
            .sheet(isPresented: $showingHowPowerWorks) {
                HowPowerWorksView()
            }
            .task {
                withAnimation(.snappy) { progression.recompute(context: modelContext) }
                recomputeRadar()
            }
            // onAppear fires on EVERY tab selection (unlike .task, which runs once while
            // TabView keeps the tab mounted) — so the odometer + gauge replay each time
            // you open Power with an unviewed PL gain (and the debug "arm roll" works).
            .onAppear { animateHero() }
            .onDisappear {
                heroRollTask?.cancel()
                lockedHintTask?.cancel()
                lockedHint = nil   // off-screen: drop silently so a stale hint can't greet the return
            }
        }
    }

    // MARK: (1) Sticky sub-nav — jump to the section anchors

    /// The five destinations on this tab, in scroll order. Each has a matching
    /// `.id(PowerSection.x)` anchor on its section so a chip tap scroll-anchors to it.
    private enum PowerSection: String, CaseIterable, Hashable {
        case form, sheet, badges, lineup, rival

        /// Mono-uppercased chip label.
        var title: String {
            switch self {
            case .form:   return "Form"
            case .sheet:  return "Sheet"
            case .badges: return "Badges"
            case .lineup: return "Lineup"
            case .rival:  return "Rival"
            }
        }
    }

    /// The pinned chip row — reuses ProgressTabView.sectionChips wholesale (heroCyan
    /// fill + etch ink selected, card + ash unselected, Haptics.light, chipEdgeFade),
    /// but instead of switching the visible graph it scroll-anchors the long scroll to
    /// the tapped section. One pattern, two tabs.
    private var subNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PowerSection.allCases, id: \.self) { section in
                    subNavChip(section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8) // breathing room so the capsules aren't clipped
        }
        .chipEdgeFade()
    }

    private func subNavChip(_ section: PowerSection) -> some View {
        let isSelected = activeSection == section
        return Button {
            Haptics.light()
            activeSection = section
            scrollTarget = section   // the content ScrollViewReader watches this and jumps
        } label: {
            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .lineLimit(1)
                // etch is the app's ink-on-heroCyan (see ChamberSegments); ash otherwise.
                .foregroundStyle(isSelected ? SettColor.etch : SettColor.ash)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(isSelected ? SettColor.heroCyan : SettColor.card))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Derived state

    private var activeCharacter: CharacterKey {
        let stored = saiyanStates.first?.characterKey ?? .vego
        // A fresh DB or a stale characterKeyRaw can point at a patron the badge
        // table hasn't awakened — fall back to the starter rather than crowning
        // (and highlighting) a sealed card.
        return progression.unlockedPatrons.contains(stored) ? stored : .vego
    }

    /// Cast collapse: the frame follows the USER's transformation form (pure
    /// function of PL) — characters are patrons, not parallel ladders.
    private var activeTier: TransformationTier {
        progression.userFormTier
    }

    /// The single-colour reading of Aura.forTier — the ki-gauge fill wants a Color,
    /// not a gradient. Cyan holds through ASCENDANT, the sacred gold arrives at RADIANT
    /// (where the PL itself turns gold), a scarce white-cyan caps Zenith. Mirrors the
    /// Aura.forTier ramp so the gauge, halo, and frame material read as one material.
    private var tierAccent: Color {
        switch activeTier {
        case .base, .kindled, .ascendant: SettColor.heroCyan
        case .radiant: SettColor.saiyanGold
        case .zenith: Color(dynamicLight: 0xB8FAFF, dark: 0xB8FAFF)   // the Aura.zenith white-cyan
        }
    }

    // MARK: Display streak (must match Home's number, not the snapshot's)

    /// Streaks use ISO weeks (Monday start), matching the engines and HomeTabView.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    private var weeklyGoalTarget: Int { frequencyGoals.first?.targetValue ?? 3 }

    /// The week's real commitment — mirrors HomeTabView.streakTarget exactly: the
    /// frequency goal, capped by the scheduled-day count in weekday mode.
    private var streakTarget: Int {
        let goal = max(1, weeklyGoalTarget)
        if services.settings.scheduleMode == .weekday {
            let mask = Scheduling.orderedActive(streakRoutines).reduce(0) { $0 | $1.daysOfWeekMask }
            let scheduled = mask.nonzeroBitCount
            if scheduled > 0 { return min(goal, scheduled) }
        }
        return goal
    }

    /// The SAME shielded, target-aware streak Home shows — so the Character Sheet
    /// STREAK row never disagrees with the dashboard.
    private var displayStreakWeeks: Int {
        StreakEngine.streakState(
            workoutDates: finishedWorkouts.map(\.startedAt),
            weeklyTarget: streakTarget,
            calendar: Self.isoCalendar,
            asOf: .now
        ).weeks
    }

    private var peakPL: Int {
        progression.snapshot?.allTimePeakPL ?? 0
    }

    /// Below peak, the caption frames the gap as ground to reclaim rather than a
    /// bare high-water mark — the one backward-looking number gets a forward hook.
    private var peakLine: String {
        let pl = progression.snapshotPowerLevel
        if pl < peakPL {
            return "PEAK \(peakPL.formatted()) · \((peakPL - pl).formatted()) TO RECLAIM"
        }
        return "PEAK \(peakPL.formatted())"
    }

    private var reclaimSpeech: String {
        let pl = progression.snapshotPowerLevel
        return pl < peakPL ? ", \((peakPL - pl).formatted()) to reclaim" : ""
    }

    private var rivalPL: Int {
        if progression.snapshot != nil { return progression.effectiveRival.pl }
        return progression.config?.rival["startPL"] as? Int ?? 0
    }

    private var rivalForm: Int {
        progression.snapshot != nil ? progression.effectiveRival.form : 1
    }

    private var earnedBadgeKeys: Set<String> {
        Set(badgeAwards.map(\.badgeKey))
    }

    private func badgeName(_ key: String) -> String {
        progression.config?.badge(key)?.name ?? key
    }

    // MARK: (1) Hero — the active character card

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                // Form-tinted identity chrome: the idle aura now rides Aura.forTier so an
                // ascending form visibly upgrades the halo material alongside the frame —
                // ki-cyan through ASCENDANT, gold-veined at RADIANT (the tier where the PL
                // itself turns gold), white-cyan at Zenith. Pure atmosphere.
                BreathingAura(gradient: Aura.forTier(activeTier))
                    .frame(width: 118, height: 118)
                    .opacity(0.55)   // the PL below is the lead; the aura is ambience
                CharacterAvatarView(character: activeCharacter, tier: activeTier, size: 132)
                if let rosterBurstID {
                    // Roster swap only — never fires on plain appearance (clear under RM).
                    AuraBurstView(gold: false)
                        .frame(width: 200, height: 200)
                        .id(rosterBurstID)
                }
            }
            .frame(height: 160)
            .id(activeCharacter)   // identity swap → cross-fade under activate()'s withAnimation
            .transition(.opacity)
            Text(activeCharacter.displayName)
                .font(.headline)
                .foregroundStyle(SettColor.bone)
                .contentTransition(.opacity)
            VStack(spacing: 6) {
                // The sacred eyebrow — same mono voice as Home's crest and the receipt.
                Eyebrow("POWER LEVEL")
                // Starts at last-viewed PL; animateHero() (on appear) flips rolledPL to
                // the live PL so the built-in odometer rolls. `.id(heroRoll)` re-mounts it
                // per roll so a repeat visit with a delta replays instead of sitting still.
                SacredNumberView(value: rolledPL ?? progression.lastViewedPowerLevel)
                    .id(heroRoll)
                if progression.snapshotPowerLevel == 0 {
                    Text("Everyone starts somewhere.")
                        .font(.footnote)
                        .foregroundStyle(SettColor.ash)
                } else {
                    Text(peakLine)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.ash)
                }
                // The USER's form on the endless ladder — current title, then the named
                // destination (not a cryptic pip count): where the next rung is and what
                // it's called. The next form is the one whose floor is this form's nextPL.
                let form = UserForm.form(forPL: progression.snapshotPowerLevel)
                let nextForm = UserForm.form(forPL: form.nextPL)
                VStack(spacing: 3) {
                    Text(form.title)
                        .font(.system(.subheadline, design: .monospaced).weight(.heavy).smallCaps())
                        .kerning(2)
                        .foregroundStyle(SettColor.heroCyan)
                    // e.g. "NEXT · RADIANT 9,000" — the destination in Eyebrow voice.
                    Eyebrow("NEXT · \(nextForm.title) \(nextForm.floorPL.formatted())")
                    // Ki Gauge, pure fill viz — form-tinted to match the frame (cyan → gold
                    // at RADIANT → white-cyan at Zenith), so ascending upgrades the gauge too.
                    // gaugeStart/gaugeTarget are driven by animateHero(); .id(heroRoll)
                    // re-mounts it so the fill replays alongside the number's odometer.
                    AnimatedKiGauge(target: gaugeTarget, from: gaugeStart, accent: tierAccent)
                        .frame(width: 180)
                        .id(heroRoll)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SettColor.card))
        .frameMaterial(activeTier.frameMaterial)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("""
            \(activeCharacter.displayName), \(activeTier.displayName). \
            Power level \(progression.snapshotPowerLevel), peak \(peakPL)\(reclaimSpeech).
            """)
    }

    // MARK: (2) Character sheet — mono stat rows + muscle radar

    /// PR-milestone badge keys — the snapshot exposes no raw PR count, so this
    /// tracks the earned milestone ladder (0–3). `walking_legend` was pruned from the
    /// live 10-badge config (3/3 was unreachable); `scanner_breaker` — the 9,000-PL
    /// ceiling-break — is the reachable capstone rung.
    private static let prBadgeKeys: Set<String> = ["new_ceiling", "limit_break", "scanner_breaker"]

    private var prBadgeCount: Int {
        earnedBadgeKeys.intersection(Self.prBadgeKeys).count
    }

    private var characterSheetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Character Sheet")
            VStack(spacing: 10) {
                statRow("STRENGTH SCORE", (progression.snapshot?.strengthScore ?? 0).formatted())
                hairline
                statRow("WEEKLY VOLUME", "\((progression.snapshot?.weeklyVolumeLb ?? 0).formatted()) LB")
                hairline
                // The display streak — same StreakEngine.streakState number Home shows,
                // not the snapshot's 2-day consistency streak (they disagreed before).
                statRow("STREAK", "\(displayStreakWeeks) WK")
                hairline
                statRow("PR MILESTONES", "\(prBadgeCount)/3")
            }
            Eyebrow("MUSCLE BALANCE — 28 DAYS")
                .padding(.top, 4)
            MuscleRadarChart(labels: Self.radarLabels, shares: radarShares)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .kerning(1.5)
                .foregroundStyle(SettColor.ash)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .contentTransition(.numericText())
                .foregroundStyle(SettColor.bone)
        }
        .accessibilityElement(children: .combine)
    }

    private var hairline: some View {
        Rectangle()
            .fill(SettColor.iron.opacity(0.35))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }

    /// The six primary muscle groups, in fixed radar order (top, clockwise).
    private static let radarMuscles: [Muscle] = [.chest, .triceps, .biceps, .shoulders, .back, .legs]
    private static let radarLabels: [String] = radarMuscles.map { $0.rawValue.uppercased() }

    /// Working-set volume (weight × reps, warmups excluded) per primary muscle
    /// over the trailing 28 days, normalized so the biggest muscle is 1.0 —
    /// the closest app-side stand-in for the engine's effective volume.
    private func recomputeRadar() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        var totals: [Muscle: Double] = [:]
        for sample in SampleExtractor.setSamples(context: modelContext)
        where !sample.isWarmup && sample.completedAt >= cutoff {
            totals[sample.muscle, default: 0] += Double(sample.weightGrams) * Double(sample.reps)
        }
        let volumes = Self.radarMuscles.map { totals[$0] ?? 0 }
        guard let peak = volumes.max(), peak > 0 else {
            radarShares = [Double](repeating: 0, count: Self.radarMuscles.count)
            return
        }
        radarShares = volumes.map { $0 / peak }
    }

    /// Roll the Sacred Number + fill the Ki gauge from the last-viewed PL up to the live
    /// PL whenever the tab appears and they differ (a real gain since last look, or the
    /// debug "arm roll"). Bumping `heroRoll` re-mounts both so their internal odometer/
    /// fill physics replay from the start value; `markPowerLevelViewed` then banks the
    /// live PL so it stays quiet until the next gain. Reduce Motion: the kit direct-sets.
    private func animateHero() {
        heroRollTask?.cancel()
        let current = progression.snapshotPowerLevel
        let lastViewed = progression.lastViewedPowerLevel
        let form = UserForm.form(forPL: current)
        let currentFraction = form.progress(current)
        // Crossed INTO this form ⇒ fill from empty, else from where they left off.
        let startFraction = lastViewed <= form.floorPL ? 0 : form.progress(lastViewed)

        guard lastViewed != current else {
            rolledPL = current
            gaugeStart = currentFraction
            gaugeTarget = currentFraction
            return
        }
        // Re-mount the number + gauge showing the START state, then flip to live so the
        // odometer rolls and the gauge fills up to it.
        rolledPL = lastViewed
        gaugeStart = startFraction
        gaugeTarget = startFraction
        heroRoll += 1
        heroRollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            rolledPL = current
            gaugeTarget = currentFraction
            progression.markPowerLevelViewed()
        }
    }

    // MARK: (5) Badge case preview

    private var latestAwards: [BadgeAward] {
        Array(badgeAwards.prefix(4))
    }

    private var badgeCasePreview: some View {
        NavigationLink {
            BadgeCaseView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Badge Case", systemImage: "medal.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SettColor.bone)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SettColor.iron)
                }
                if latestAwards.isEmpty {
                    Text("The case is empty — every badge inside is visible and waiting.")
                        .font(.subheadline)
                        .foregroundStyle(SettColor.ash)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(latestAwards) { award in
                            previewMedallion(award)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settCard()
        }
        .buttonStyle(.plain)
    }

    /// A premiere is still glowing the next day: an award earned within 48h wears the
    /// same slow gold breath the PR crown / badge-detail sheet use, so a fresh badge
    /// reads as new even after the earn moment's one-shot burst has spent itself.
    private func isFresh(_ award: BadgeAward) -> Bool {
        award.earnedAt > Date.now.addingTimeInterval(-48 * 3600)
    }

    /// Earned medallion slot: rank reads from the frame material — engraved
    /// gold, or prismatic for legendary. The medal itself stays bone.
    private func previewMedallion(_ award: BadgeAward) -> some View {
        let legendary = progression.config?.badge(award.badgeKey)?.rarity == .legendary
        return VStack(spacing: 6) {
            ZStack {
                if isFresh(award) {
                    // Gold breath = reward; the case's only animated slot, and only
                    // while the award is fresh (<48h), so idle badges stay still.
                    BreathingAura(gradient: Aura.gold)
                        .frame(width: 60, height: 60)
                }
                Circle()
                    .fill(SettColor.card)
                Image(systemName: "medal.fill")
                    .font(.title3)
                    .foregroundStyle(SettColor.bone)
            }
            .frame(width: 52, height: 52)
            Text(badgeName(award.badgeKey))
                .font(.caption2)
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 60)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SettColor.cardNested))
        .frameMaterial(legendary ? .prismatic : .gold)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badgeName(award.badgeKey)) badge, earned")
    }

    // MARK: (6) Roster strip

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Roster")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(CharacterKey.allCases, id: \.self) { character in
                        rosterEntry(character)
                    }
                }
            }
            if let lockedHint {
                // The knock's answer — story copy in sentence case, never a modal.
                Text(lockedHint)
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash)
                    .transition(.opacity)
            }
            NavigationLink {
                CharacterLineupView(unlockedPatrons: progression.unlockedPatrons,
                                    highestSeenRivalForm: progression.highestSeenRivalForm)
            } label: {
                HStack {
                    Text("VIEW FULL LINEUP")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .kerning(1.4)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(SettColor.heroCyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .nestedSlab(radius: 10)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    /// Patrons awaken through badges now: the whole cast stays visible so every
    /// seal reads as a target, but a sealed patron can't take the active slot —
    /// tapping one knocks (warning haptic) and surfaces the awakening requirement
    /// under the strip instead of swapping identity. Still voices, not ladders.
    private func rosterEntry(_ character: CharacterKey) -> some View {
        let isActive = character == activeCharacter
        let isLocked = !progression.unlockedPatrons.contains(character)
        return Button {
            if isLocked {
                showLockedHint(for: character)
            } else {
                activate(character)
            }
        } label: {
            VStack(spacing: 6) {
                CharacterAvatarView(character: character,
                                    tier: isActive ? activeTier : .base,
                                    locked: isLocked)
                Text(shortName(character))
                    .font(.caption2.weight(isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? SettColor.heroCyan
                                     : isLocked ? SettColor.ash : SettColor.bone)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rosterAccessibilityLabel(character, isActive: isActive, isLocked: isLocked))
    }

    /// The knock on a sealed card: warning haptic + the patron's requirement
    /// line under the strip. Re-tapping (same seal or another) cancels the
    /// pending clear and restarts the ~4s window; onDisappear cancels outright.
    private func showLockedHint(for character: CharacterKey) {
        lockedHintTask?.cancel()
        Haptics.warning()
        withAnimation(.snappy) { lockedHint = PatronUnlocks.requirement(for: character) }
        lockedHintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { lockedHint = nil }
        }
    }

    private func shortName(_ character: CharacterKey) -> String {
        let name = character.displayName
        if let comma = name.firstIndex(of: ",") {
            return String(name[..<comma])
        }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private func activate(_ character: CharacterKey) {
        guard character != activeCharacter else { return }
        let state = modelContext.saiyanState()
        withAnimation(.snappy) {
            state.characterKey = character
            state.transformationTier = progression.userFormTier
            state.updatedAt = .now
            state.needsPush = true
            try? modelContext.save()
        }
        let burstID = UUID()
        rosterBurstID = burstID
        Haptics.medium()
        // A spent AuraBurstView's TimelineView(.animation) keeps ticking invisibly —
        // clear the id once the 0.8s burst finishes so it unmounts (DirectivePanel.claim precedent).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard rosterBurstID == burstID else { return }   // don't clobber a newer swap's burst
            rosterBurstID = nil
        }
    }

    private func rosterAccessibilityLabel(_ character: CharacterKey, isActive: Bool,
                                          isLocked: Bool) -> String {
        if isLocked { return "\(character.displayName), sealed. \(PatronUnlocks.requirement(for: character))" }
        if isActive { return "\(character.displayName), active" }
        return "\(character.displayName), tap to set active"
    }

    // MARK: Patron awakening slab

    /// The "patron awakened" beat — gold, because an awakening is a reward
    /// moment. Mirrors LevelUpBanner's grammar (hudCard + materialize entrance,
    /// tap anywhere to acknowledge) but lands above the roster instead of the
    /// hero: the slab points at the card that just unsealed. `.id(patron)`
    /// re-mounts it when a second awakening is queued behind the first, so each
    /// patron gets their own entrance. The ack persists store-side, so a
    /// dismissal survives relaunch.
    private func patronAwakeningSlab(_ patron: CharacterKey) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { progression.acknowledgePatronAwakening() }
        } label: {
            HStack(spacing: 12) {
                CharacterAvatarView(character: patron, tier: .base, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow("PATRON AWAKENED", tint: SettColor.saiyanGold)
                    Text(patron.displayName)
                        .font(.headline)
                        .foregroundStyle(SettColor.bone)
                    // The requirement line doubles as satisfied flavor — the
                    // deed it names is exactly what just woke them.
                    Text(PatronUnlocks.requirement(for: patron))
                        .font(.footnote)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer(minLength: 8)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.ash)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudCard(tint: SettColor.saiyanGold)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .materialize()
        .id(patron)
        .onAppear { Haptics.success() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Patron awakened: \(patron.displayName). Tap to dismiss.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Haptics: the sealed-card knock

extension Haptics {
    /// Softer than error(): the tap was understood, the patron just isn't awake
    /// yet. Lives at its only call site for now — fold into SettTheme's Haptics
    /// vocabulary the moment a second surface needs to knock.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Muscle radar (Canvas — static, nothing animates, Reduce Motion safe)

/// Six-axis radar of 28-day volume share per primary muscle: iron hairline
/// grid rings + spokes, a ki-cyan polygon (30% fill + stroke), caption2 ash
/// axis labels. Entirely static.
private struct MuscleRadarChart: View {
    let labels: [String]
    let shares: [Double]

    var body: some View {
        Canvas { context, size in
            let count = labels.count
            guard count >= 3, shares.count == count else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 26
            guard radius > 0 else { return }

            func angle(_ axis: Int) -> Double {
                -Double.pi / 2 + Double(axis) / Double(count) * 2 * .pi
            }
            func point(axis: Int, fraction: Double) -> CGPoint {
                CGPoint(x: center.x + CGFloat(cos(angle(axis)) * fraction) * radius,
                        y: center.y + CGFloat(sin(angle(axis)) * fraction) * radius)
            }
            func ring(_ fraction: Double) -> Path {
                var path = Path()
                for axis in 0 ..< count {
                    let p = point(axis: axis, fraction: fraction)
                    if axis == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                return path
            }

            // Grid: three concentric rings + spokes, iron hairlines.
            for step in 1 ... 3 {
                context.stroke(ring(Double(step) / 3),
                               with: .color(SettColor.iron.opacity(0.35)),
                               lineWidth: step == 3 ? 1 : 0.5)
            }
            var spokes = Path()
            for axis in 0 ..< count {
                spokes.move(to: center)
                spokes.addLine(to: point(axis: axis, fraction: 1))
            }
            context.stroke(spokes, with: .color(SettColor.iron.opacity(0.3)), lineWidth: 0.5)

            // The balance polygon — ki cyan, never gold.
            if shares.contains(where: { $0 > 0 }) {
                var polygon = Path()
                for axis in 0 ..< count {
                    let p = point(axis: axis, fraction: min(max(shares[axis], 0), 1))
                    if axis == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) }
                }
                polygon.closeSubpath()
                context.fill(polygon, with: .color(SettColor.heroCyan.opacity(0.3)))
                context.stroke(polygon, with: .color(SettColor.heroCyan), lineWidth: 1.5)
            }

            // Axis labels, pushed outward along each spoke.
            for axis in 0 ..< count {
                let a = angle(axis)
                let position = CGPoint(x: center.x + CGFloat(cos(a)) * (radius + 8),
                                       y: center.y + CGFloat(sin(a)) * (radius + 8))
                let anchor = UnitPoint(x: 0.5 - 0.5 * cos(a), y: 0.5 - 0.5 * sin(a))
                context.draw(
                    context.resolve(Text(labels[axis]).font(.caption2).foregroundStyle(SettColor.ash)),
                    at: position, anchor: anchor
                )
            }
        }
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard shares.contains(where: { $0 > 0 }) else {
            return "Muscle balance, last 28 days: no working sets yet"
        }
        let parts = zip(labels, shares).map {
            "\($0.0.lowercased()) \(Int(($0.1 * 100).rounded())) percent"
        }
        return "Muscle balance, last 28 days: " + parts.joined(separator: ", ")
    }
}

// MARK: - Rival card (Vexeth)

/// EMPEROR VEXETH, the Crimson Star — the scripted rival pacing the user.
/// This card is the ONLY surface in the entire app that uses crimson.
private struct RivalCard: View {
    let rivalPL: Int
    let rivalForm: Int
    let userPL: Int
    let pace: Int
    let growth: Int
    var cycle: Int = 1
    /// The System Voice's line keyed to the current gap state (from the store) —
    /// replaces the old three hard-coded quotes.
    var taunt: String = ""
    /// bone = you, crimson = Vexeth, over the trailing weeks. Empty when < 2 weeks.
    var raceLines: [(weekStart: Date, you: Int, rival: Int)] = []
    /// True while a form reveal is unacknowledged — fires the one-shot portrait burn-in.
    var revealPending: Bool = false
    var rebirthAnnounce: Bool = false
    var onAcknowledgeRebirth: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The current form's epithet — Star / Nova / Singularity — so the subtitle and
    /// the "Form N of 3" pill never disagree (subtitle was previously hard-Star).
    private var formEpithet: String {
        switch rivalForm {
        case 2: return "the Crimson Nova"
        case 3: return "the Crimson Singularity"
        default: return "the Crimson Star"
        }
    }
    /// Drives the slow crimson menace pulse on the border (static under RM).
    @State private var menace = false
    /// One-shot crimson flash over the portrait when a form reveal lands: set hot,
    /// then animated to 0. 0 = spent (nothing drawn).
    @State private var burnIn: Double = 0
    /// Guards the burn-in to once per reveal — the card lives at the bottom of a
    /// non-lazy scroll, so its onAppear fires off-screen; the flash is instead armed
    /// to the moment the portrait actually scrolls into view. Rearmed when the reveal
    /// is acknowledged so the NEXT transformation burns in too.
    @State private var burnedInForReveal = false

    /// The forward hook: how far behind Vexeth stands and, if the user is
    /// out-pacing his growth, how many weeks until the catch — mirrors Home's
    /// Weekly Reading VEXETH row.
    private var gapLine: String {
        let gap = rivalPL - userPL
        if gap > 0 {
            let eta = pace > growth ? " · CATCH IN \(Int((Double(gap) / Double(pace - growth)).rounded(.up))) WK" : ""
            return "\(gap.formatted()) PL AHEAD\(eta)"
        }
        return "\(abs(gap).formatted()) PL BEHIND YOU"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if rebirthAnnounce {
                // The endless race: beating the final form doesn't end the story.
                Button(action: onAcknowledgeRebirth) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.heavy))
                        Text("VEXETH REBORN — CYCLE \(cycle)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .kerning(1.5)
                        Spacer()
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SettColor.ash)
                    }
                    .foregroundStyle(SettColor.villainCrimson)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SettColor.villainCrimson.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .materialize()
                .accessibilityLabel("Vexeth reborn, cycle \(cycle). Dismisses this banner.")
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EMPEROR VEXETH")
                        .font(.headline)
                        .kerning(1.2)
                        .foregroundStyle(SettColor.villainCrimson)
                    Text(cycle > 1 ? "\(formEpithet) · Cycle \(cycle)" : formEpithet)
                        .font(.footnote)
                        .foregroundStyle(SettColor.villainCrimson.opacity(0.8))
                }
                Spacer()
                Text("Form \(rivalForm) of 3")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.villainCrimson)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(SettColor.villainCrimson.opacity(0.15), in: Capsule())
            }
            VexethPortraitView(form: rivalForm)
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .padding(.horizontal, 8)
                .background(SettColor.villainCrimson.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    // One-shot crimson burn-in when a reveal is pending: a hot wash that
                    // fades to nothing, so the transformation reads on the portrait itself.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SettColor.villainCrimson.opacity(burnIn))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettColor.villainCrimson.opacity(0.24), lineWidth: 1)
                }
            PowerNumeral(rivalPL, size: .l, color: SettColor.villainCrimson)
            Text(gapLine)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.villainCrimson)
            raceSparkline
            // The rival's line, keyed to the gap state by the store (closing / stalling /
            // just-passed / transformed / post-rebirth / trailing) — no longer three
            // hard-coded strings.
            Text(taunt)
                .font(.subheadline.italic())
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SettColor.villainVoid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // Crimson-tinted iron hairline, breathing 0.3↔0.5 — the villain never sits still.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettColor.villainCrimson.opacity(reduceMotion ? 0.4 : (menace ? 0.5 : 0.3)),
                              lineWidth: 1)
        }
        // Arm the portrait burn-in to the moment it scrolls into view (onAppear fires
        // off-screen here). Fires at most once per reveal.
        .onScrollVisibilityChange(threshold: 0.35) { visible in
            if visible, revealPending, !burnedInForReveal {
                burnedInForReveal = true
                fireBurnIn()
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                menace = true
            }
        }
        .onChange(of: rebirthAnnounce) { _, announced in
            if announced { Haptics.rigid() }   // one hit as the rebirth banner lands
        }
        .onChange(of: revealPending) { _, pending in
            if !pending { burnedInForReveal = false }   // rearm for the next transformation
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Emperor Vexeth, \(formEpithet). Power level \(rivalPL), form \(rivalForm) of 3, \(gapLine).")
    }

    /// A compact two-line race: bone = you, crimson = Vexeth, converging or diverging
    /// over the trailing weeks. Hidden until there are at least two weekly points.
    @ViewBuilder
    private var raceSparkline: some View {
        if raceLines.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                Chart {
                    ForEach(Array(raceLines.enumerated()), id: \.offset) { item in
                        LineMark(x: .value("Week", item.element.weekStart),
                                 y: .value("PL", item.element.you),
                                 series: .value("Series", "You"))
                            .foregroundStyle(SettColor.bone)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        LineMark(x: .value("Week", item.element.weekStart),
                                 y: .value("PL", item.element.rival),
                                 series: .value("Series", "Vexeth"))
                            .foregroundStyle(SettColor.villainCrimson)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 52)
                // Inline legend — bone you / crimson Vexeth, so the two lines read.
                HStack(spacing: 12) {
                    raceKey(SettColor.bone, "YOU")
                    raceKey(SettColor.villainCrimson, "VEXETH")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(raceAccessibilityLabel)
        }
    }

    private func raceKey(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 2)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
        }
        .accessibilityHidden(true)
    }

    private var raceAccessibilityLabel: String {
        guard let first = raceLines.first, let last = raceLines.last else { return "" }
        let openGap = first.rival - first.you
        let nowGap = last.rival - last.you
        let trend = nowGap < openGap ? "closing" : nowGap > openGap ? "widening" : "holding"
        return "Race over \(raceLines.count) weeks: the gap to Vexeth is \(trend)."
    }

    private func fireBurnIn() {
        guard !reduceMotion else { return }
        burnIn = 0.55
        withAnimation(.easeOut(duration: 0.9)) { burnIn = 0 }
    }
}

// MARK: - (2) Vexeth Responds banner — the crimson mirror of LevelUpBanner

/// "VEXETH RESPONDS — NOVA / — SINGULARITY": the rival's crimson answer to the user's
/// climb, pinned above the hero when a form reveal is unacknowledged. A structural
/// mirror of LevelUpBanner (glowing mark → eyebrow → big title, tap or × to ack,
/// materialize entrance) but crimson-only — never gold. Draws no burst, since
/// AuraBurstView only speaks gold/cyan; the portrait burn-in carries the flash instead.
/// Landing haptic is a single rigid hit (the villain's), not the level-up ramp.
private struct VexethRespondsBanner: View {
    /// 2 (Nova) or 3 (Singularity).
    let form: Int
    let onAcknowledge: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var formName: String { form >= 3 ? "SINGULARITY" : "NOVA" }

    var body: some View {
        Button(action: acknowledge) {
            HStack(spacing: 12) {
                // The sacred sigil in crimson — the rival's dark reflection of your power.
                SettSigil(size: 30, color: SettColor.villainCrimson)
                    .auraGlow(SettColor.villainCrimson, radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text("VEXETH RESPONDS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(SettColor.villainCrimson.opacity(0.9))
                    Text("— \(formName)")
                        .font(.system(.title3, design: .rounded).weight(.heavy).smallCaps())
                        .kerning(1)
                        .foregroundStyle(SettColor.villainCrimson)
                        .shadow(color: SettColor.villainCrimson.opacity(0.5), radius: 6)
                }
                Spacer(minLength: 8)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.ash)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudCard(tint: SettColor.villainCrimson)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .materialize()
        .onAppear { if !reduceMotion { Haptics.rigid() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vexeth responds, \(formName). Tap to dismiss.")
        .accessibilityAddTraits(.isButton)
    }

    private func acknowledge() {
        Haptics.selection()
        onAcknowledge()
    }
}
