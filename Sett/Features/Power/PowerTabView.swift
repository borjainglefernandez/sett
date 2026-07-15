import SwiftUI
import SwiftData
import SettCore

/// Tab 4 — the character sheet (Flow 5, Dark Chamber v3):
/// (1) hero — the active character card (tier-material frame) with the Sacred
///     Number and its ember halo,
/// (2) character sheet — monospaced stat rows + a muscle-balance radar,
/// (3) tier progress toward the next transformation on a Ki Gauge,
/// (4) Emperor Vexeth's rival card (the app's ONLY red surface),
/// (5) badge case preview, (6) character roster strip.
struct PowerTabView: View {
    @Environment(ProgressionStore.self) private var progression
    @Environment(\.modelContext) private var modelContext

    @Query private var saiyanStates: [SaiyanState]
    @Query private var badgeAwards: [BadgeAward]

    @State private var showingHowPowerWorks = false
    @State private var radarShares = [Double](repeating: 0, count: PowerTabView.radarMuscles.count)

    init() {
        let badgeAwardFilter = #Predicate<BadgeAward> { $0.deletedAt == nil }
        _badgeAwards = Query(filter: badgeAwardFilter, sort: [SortDescriptor(\BadgeAward.earnedAt, order: .reverse)])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    characterSheetCard
                    RivalCard(rivalPL: rivalPL,
                              rivalForm: rivalForm,
                              userPL: progression.snapshotPowerLevel,
                              cycle: progression.rivalCycle,
                              rebirthAnnounce: progression.rivalRebirthAnnounce,
                              onAcknowledgeRebirth: { progression.acknowledgeRivalRebirth() })
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
            .task {
                progression.recompute(context: modelContext)
                recomputeRadar()
            }
        }
    }

    // MARK: Derived state

    private var activeCharacter: CharacterKey {
        saiyanStates.first?.characterKey ?? .vego
    }

    /// Cast collapse: the frame follows the USER's transformation form (pure
    /// function of PL) — characters are patrons, not parallel ladders.
    private var activeTier: TransformationTier {
        progression.userFormTier
    }

    private var peakPL: Int {
        progression.snapshot?.allTimePeakPL ?? 0
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
                CharacterAvatarView(character: activeCharacter, tier: activeTier)
            }
            .frame(height: 160)
            Text(activeCharacter.displayName)
                .font(.headline)
                .foregroundStyle(SettColor.bone)
            VStack(spacing: 6) {
                Text("POWER LEVEL")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.ash)
                SacredNumberView(value: progression.snapshotPowerLevel)
                if progression.snapshotPowerLevel == 0 {
                    Text("Everyone starts somewhere.")
                        .font(.footnote)
                        .foregroundStyle(SettColor.ash)
                } else {
                    Text("PEAK \(peakPL.formatted())")
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
                    ProgressView(value: form.progress(progression.snapshotPowerLevel))
                        .tint(SettColor.heroCyan)
                        .frame(width: 180)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .settCard()
        .frameMaterial(activeTier.frameMaterial)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("""
            \(activeCharacter.displayName), \(activeTier.displayName). \
            Power level \(progression.snapshotPowerLevel), peak \(peakPL).
            """)
    }

    // MARK: (2) Character sheet — mono stat rows + muscle radar

    /// PR-milestone badge keys — the snapshot exposes no raw PR count, so the
    /// PRS stat counts the earned PR badge ladder (0–3).
    private static let prBadgeKeys: Set<String> = ["new_ceiling", "limit_break", "walking_legend"]

    private var prBadgeCount: Int {
        earnedBadgeKeys.intersection(Self.prBadgeKeys).count
    }

    private var characterSheetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Character Sheet")
                .font(.title3.weight(.semibold))
            VStack(spacing: 10) {
                statRow("STRENGTH SCORE", (progression.snapshot?.strengthScore ?? 0).formatted())
                hairline
                statRow("WEEKLY VOLUME", "\((progression.snapshot?.weeklyVolumeLb ?? 0).formatted()) LB")
                hairline
                statRow("STREAK", "\(progression.snapshot?.streakWeeks ?? 0) WK")
                hairline
                statRow("PRS", "\(prBadgeCount)")
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
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.ash)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
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
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
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

    /// Cast collapse: every patron is available from day one — they are voices and
    /// badge domains now, not locked ladders. The avatar is a cosmetic identity.
    private func rosterEntry(_ character: CharacterKey) -> some View {
        let isActive = character == activeCharacter
        return Button {
            activate(character)
        } label: {
            VStack(spacing: 6) {
                CharacterAvatarView(character: character,
                                    tier: isActive ? activeTier : .base)
                Text(shortName(character))
                    .font(.caption2.weight(isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? SettColor.heroCyan : SettColor.bone)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rosterAccessibilityLabel(character, isActive: isActive))
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
        state.transformationTier = progression.userFormTier
        state.updatedAt = .now
        state.needsPush = true
        try? modelContext.save()
        Haptics.medium()
    }

    private func rosterAccessibilityLabel(_ character: CharacterKey, isActive: Bool) -> String {
        if isActive { return "\(character.displayName), active" }
        return "\(character.displayName), tap to set active"
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
    var cycle: Int = 1
    var rebirthAnnounce: Bool = false
    var onAcknowledgeRebirth: () -> Void = {}

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
            PowerNumeral(rivalPL, size: .l, color: SettColor.villainCrimson)
            Text(rebirthAnnounce ? "\u{201C}You thought that was my ceiling? Cute.\u{201D}"
                 : userPL > rivalPL ? "You've forced my hand." : "He hasn't shown his final form.")
                .font(.subheadline.italic())
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SettColor.villainVoid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // Crimson-tinted iron: the matte rank hairline, tinted to the villain.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettColor.villainCrimson.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Emperor Vexeth, the Crimson Star. Power level \(rivalPL), form \(rivalForm) of 3.")
    }
}
