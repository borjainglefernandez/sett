import SwiftUI
import SwiftData
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
    @Environment(\.modelContext) private var modelContext

    @Query private var saiyanStates: [SaiyanState]
    @Query private var badgeAwards: [BadgeAward]

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
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Pinned above the hero, mirroring Home's rotationSealBanner —
                    // acknowledgeAscension clears it on both tabs (single source of truth).
                    if let form = progression.pendingAscension {
                        LevelUpBanner(form: form) { withAnimation(.snappy) { progression.acknowledgeAscension() } }
                    }
                    hero
                    characterSheetCard
                    RivalCard(rivalPL: rivalPL,
                              rivalForm: rivalForm,
                              userPL: progression.snapshotPowerLevel,
                              pace: progression.trailingWeeklyPace,
                              growth: progression.effectiveRivalGrowth,
                              cycle: progression.rivalCycle,
                              rebirthAnnounce: progression.rivalRebirthAnnounce,
                              onAcknowledgeRebirth: { withAnimation(.snappy) { progression.acknowledgeRivalRebirth() } })
                    badgeCasePreview
                    // Sits directly above the roster (not pinned at the top like
                    // the ascension banner) — the beat points at the strip where
                    // the new card just unsealed.
                    if let awakened = progression.pendingPatronAwakening {
                        patronAwakeningSlab(awakened)
                    }
                    rosterCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
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
                // Rank lives in the frame material now, so the idle aura stays
                // ki-cyan at every tier — only Zenith earns its own gradient.
                BreathingAura(gradient: activeTier == .zenith ? Aura.zenith : Aura.cyan)
                    .frame(width: 118, height: 118)
                    .opacity(0.55)   // the gold PL below is the lead; the aura is ambience
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
                // The USER's form on the endless ladder — one title, one next target.
                let form = UserForm.form(forPL: progression.snapshotPowerLevel)
                VStack(spacing: 3) {
                    Text(form.title)
                        .font(.system(.subheadline, design: .monospaced).weight(.heavy).smallCaps())
                        .kerning(2)
                        .foregroundStyle(SettColor.heroCyan)
                    Text("\((form.nextPL - progression.snapshotPowerLevel).formatted()) PL TO NEXT FORM")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                    // Ki Gauge, not a stock bar — its fused n/12 numeral counts cells,
                    // the caption above counts PL, so the two never double-report.
                    // gaugeStart/gaugeTarget are driven by animateHero(); .id(heroRoll)
                    // re-mounts it so the fill replays alongside the number's odometer.
                    AnimatedKiGauge(target: gaugeTarget, from: gaugeStart, accent: SettColor.heroCyan)
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
    /// tracks the earned PR-milestone badge ladder (0–3), not a total PR count.
    private static let prBadgeKeys: Set<String> = ["new_ceiling", "limit_break", "walking_legend"]

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
                statRow("STREAK", "\(progression.snapshot?.streakWeeks ?? 0) WK")
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

    /// Earned medallion slot: rank reads from the frame material — engraved
    /// gold, or prismatic for legendary. The medal itself stays bone.
    private func previewMedallion(_ award: BadgeAward) -> some View {
        let legendary = progression.config?.badge(award.badgeKey)?.rarity == .legendary
        return VStack(spacing: 6) {
            ZStack {
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
    var rebirthAnnounce: Bool = false
    var onAcknowledgeRebirth: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the slow crimson menace pulse on the border (static under RM).
    @State private var menace = false

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
                    Text(cycle > 1 ? "the Crimson Star · Cycle \(cycle)" : "the Crimson Star")
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettColor.villainCrimson.opacity(0.24), lineWidth: 1)
                }
            PowerNumeral(rivalPL, size: .l, color: SettColor.villainCrimson)
            Text(gapLine)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.villainCrimson)
            Text(rebirthAnnounce ? "\u{201C}You thought that was my ceiling? Cute.\u{201D}"
                 : userPL > rivalPL ? "You've forced my hand." : "He hasn't shown his final form.")
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
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                menace = true
            }
        }
        .onChange(of: rebirthAnnounce) { _, announced in
            if announced { Haptics.rigid() }   // one hit as the rebirth banner lands
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Emperor Vexeth, the Crimson Star. Power level \(rivalPL), form \(rivalForm) of 3, \(gapLine).")
    }
}
