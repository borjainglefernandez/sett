import SwiftUI
import SwiftData
import SettCore

/// Tab 4 — the reward center (Flow 5). Fully themed:
/// (1) hero — active character with breathing aura + power level,
/// (2) tier progress toward the next transformation,
/// (3) Emperor Vexeth's rival card (the app's ONLY red surface),
/// (4) badge case preview, (5) character roster strip.
struct PowerTabView: View {
    @Environment(ProgressionStore.self) private var progression
    @Environment(\.modelContext) private var modelContext

    @Query private var saiyanStates: [SaiyanState]
    @Query private var badgeAwards: [BadgeAward]

    @State private var showingHowPowerWorks = false

    init() {
        let badgeAwardFilter = #Predicate<BadgeAward> { $0.deletedAt == nil }
        _badgeAwards = Query(filter: badgeAwardFilter, sort: [SortDescriptor(\BadgeAward.earnedAt, order: .reverse)])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    tierProgressCard
                    RivalCard(rivalPL: rivalPL,
                              rivalForm: rivalForm,
                              userPL: progression.snapshotPowerLevel)
                    badgeCasePreview
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
            .task { progression.recompute(context: modelContext) }
        }
    }

    // MARK: Derived state

    private var activeCharacter: CharacterKey {
        saiyanStates.first?.characterKey ?? .vego
    }

    private var activeTier: TransformationTier {
        progression.tier(for: activeCharacter)
    }

    private var currentXP: Int {
        progression.xp(for: activeCharacter)
    }

    private var currentLevel: Int {
        progression.level(for: activeCharacter)
    }

    private var peakPL: Int {
        progression.snapshot?.allTimePeakPL ?? 0
    }

    private var rivalPL: Int {
        if let snapshot = progression.snapshot { return snapshot.rivalPL }
        return progression.config?.rival["startPL"] as? Int ?? 0
    }

    private var rivalForm: Int {
        progression.snapshot?.rivalForm ?? 1
    }

    private var earnedBadgeKeys: Set<String> {
        Set(badgeAwards.map(\.badgeKey))
    }

    private func badgeName(_ key: String) -> String {
        progression.config?.badge(key)?.name ?? key
    }

    // MARK: (1) Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                BreathingAura(gradient: Aura.forTier(activeTier.rawValue))
                    .frame(width: 150, height: 150)
                CharacterAvatarView(character: activeCharacter, tier: activeTier)
            }
            .frame(height: 160)
            Text(activeCharacter.displayName)
                .font(.headline)
            VStack(spacing: 4) {
                Text("POWER LEVEL")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.5)
                    .foregroundStyle(.secondary)
                PowerNumeral(progression.snapshotPowerLevel, size: .xl)
                if progression.snapshotPowerLevel == 0 {
                    Text("Everyone starts somewhere.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Peak \(peakPL.formatted())")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text("\(activeTier.displayName) — \(activeTier.dilation)× dilation")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettColor.heroCyan)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("""
            \(activeCharacter.displayName), \(activeTier.displayName). \
            Power level \(progression.snapshotPowerLevel), peak \(peakPL).
            """)
    }

    // MARK: (2) Tier progress

    private struct TierGate {
        let tier: TransformationTier
        let level: Int
        let keystone: String?
        let domainBadgeCount: Int?
    }

    /// Parses the raw `tiers` dict from progression_config.json for the active
    /// character: keys kindled/ascendant/radiant/zenith, each `{level, keystone? | domainBadgeCount?}`.
    private var nextGate: TierGate? {
        guard let config = progression.config,
              let characterTiers = config.tiers[activeCharacter.rawValue] as? [String: Any],
              let next = TransformationTier(rawValue: activeTier.rawValue + 1),
              let gate = characterTiers[next.displayName.lowercased()] as? [String: Any],
              let level = gate["level"] as? Int
        else { return nil }
        return TierGate(tier: next,
                        level: level,
                        keystone: gate["keystone"] as? String,
                        domainBadgeCount: gate["domainBadgeCount"] as? Int)
    }

    /// Cumulative XP for a level on the 100 × L^1.8 curve.
    private func xpNeeded(forLevel level: Int) -> Int {
        Int((100.0 * pow(Double(level), 1.8)).rounded())
    }

    private func xpFraction(for gate: TierGate) -> Double {
        let needed = xpNeeded(forLevel: gate.level)
        guard needed > 0 else { return 1 }
        return min(1, Double(currentXP) / Double(needed))
    }

    private var tierProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Transformation")
                .font(.title3.weight(.semibold))
            if let gate = nextGate {
                Text("\(gate.tier.displayName) — \(gate.tier.dilation)× dilation")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettColor.heroCyan)
                xpBar(fraction: xpFraction(for: gate))
                Text("\(currentXP.formatted()) / \(xpNeeded(forLevel: gate.level).formatted()) XP")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                gateRow(met: currentLevel >= gate.level, text: "Reach level \(gate.level)")
                keystoneRow(gate)
            } else {
                Label("Zenith — \(TransformationTier.zenith.dilation)× dilation. The summit.",
                      systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettColor.saiyanGold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func xpBar(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SettColor.cardNested)
                Capsule()
                    .fill(Aura.cyan)
                    .frame(width: max(10, proxy.size.width * fraction))
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("XP progress \(Int((fraction * 100).rounded())) percent")
    }

    private func gateRow(met: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(met ? SettColor.saiyanGold : Color.secondary)
            Text(text)
                .font(.footnote)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func keystoneRow(_ gate: TierGate) -> some View {
        if let keystone = gate.keystone {
            gateRow(met: earnedBadgeKeys.contains(keystone),
                    text: "Keystone: \(badgeName(keystone))")
        } else if let required = gate.domainBadgeCount {
            let earned = domainBadgeEarnedCount(for: activeCharacter)
            gateRow(met: earned >= required,
                    text: "Keystone: \(earned) of \(required) \(shortName(activeCharacter)) badges")
        }
    }

    private func domainBadgeEarnedCount(for character: CharacterKey) -> Int {
        guard let config = progression.config else { return 0 }
        return earnedBadgeKeys.filter { config.badge($0)?.character == character }.count
    }

    // MARK: (4) Badge case preview

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
                        .foregroundStyle(latestAwards.isEmpty ? Color.primary : SettColor.saiyanGold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if latestAwards.isEmpty {
                    Text("The case is empty — every badge inside is visible and waiting.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 16) {
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

    private func previewMedallion(_ award: BadgeAward) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Aura.gold)
                Image(systemName: "medal.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            Text(badgeName(award.badgeKey))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 64)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badgeName(award.badgeKey)) badge, earned")
    }

    // MARK: (5) Roster strip

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Roster")
                .font(.title3.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(CharacterKey.allCases, id: \.self) { character in
                        rosterEntry(character)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    /// Unlocked once the character has transformed at least once; Vego is always yours.
    private func isUnlocked(_ character: CharacterKey) -> Bool {
        character == .vego || progression.tier(for: character) > .base
    }

    private func rosterEntry(_ character: CharacterKey) -> some View {
        let unlocked = isUnlocked(character)
        let isActive = character == activeCharacter
        return Button {
            activate(character)
        } label: {
            VStack(spacing: 6) {
                if unlocked {
                    CharacterAvatarView(character: character, tier: progression.tier(for: character))
                } else {
                    lockedSilhouette
                }
                Text(shortName(character))
                    .font(.caption2.weight(isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? SettColor.heroCyan : (unlocked ? Color.primary : Color.secondary))
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(rosterAccessibilityLabel(character, unlocked: unlocked, isActive: isActive))
    }

    private var lockedSilhouette: some View {
        ZStack {
            Circle()
                .fill(SettColor.cardNested)
            Image(systemName: "person.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.gray.opacity(0.55))
        }
        .frame(width: 88, height: 88)
        .overlay {
            Circle()
                .strokeBorder(Color.gray.opacity(0.35), lineWidth: 4)
        }
        .grayscale(1)
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
        state.characterKey = character
        state.transformationTier = progression.tier(for: character)
        state.updatedAt = .now
        state.needsPush = true
        try? modelContext.save()
        Haptics.medium()
    }

    private func rosterAccessibilityLabel(_ character: CharacterKey, unlocked: Bool, isActive: Bool) -> String {
        if !unlocked { return "\(shortName(character)), locked" }
        if isActive { return "\(character.displayName), active" }
        return "\(character.displayName), tap to set active"
    }
}

// MARK: - Rival card (Vexeth)

/// EMPEROR VEXETH, the Crimson Star — the scripted rival pacing the user.
/// This card is the ONLY surface in the entire app that uses crimson.
private struct RivalCard: View {
    let rivalPL: Int
    let rivalForm: Int
    let userPL: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EMPEROR VEXETH")
                        .font(.headline)
                        .kerning(1.2)
                        .foregroundStyle(SettColor.villainCrimson)
                    Text("the Crimson Star")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
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
            PowerNumeral(rivalPL, size: .l, color: SettColor.villainCrimson)
            Text(userPL > rivalPL ? "You've forced my hand." : "He hasn't shown his final form.")
                .font(.subheadline.italic())
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SettColor.villainVoid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Emperor Vexeth, the Crimson Star. Power level \(rivalPL), form \(rivalForm) of 3.")
    }
}
