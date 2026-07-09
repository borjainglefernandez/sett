import SwiftUI
import SwiftData
import SettCore

/// The Scan Ritual v3 (Flow 2). One screen, staged reveal:
/// 1. dark scan card — a horizontal cyan scanline sweeps; then `READING COMPLETE`
///    materializes, a 500 ms seeded digit-scramble prelude runs where the numeral
///    will land, and the SacredNumberView swaps in and odometer-rolls
///    powerLevelBefore → powerLevelAfter (hit-stop, ember burst). On completion:
///    scale punch + a 3-oscillation 2 pt horizontal shake + `Haptics.levelUp`;
/// 2. CEILING BREAK — only when the active character's tier rose (or a
///    ceiling-class badge landed): full-screen CrackOverlay reveals 0 → 1 over
///    0.8 s with `CEILING BROKEN` beneath the scan card;
/// 3. net progress vs previous same-exercise sessions;
/// 4. badges earned (gold medallions, only when non-empty);
/// 5. XP earned per character (only when non-empty), with a "How XP works" link;
/// 6. AI commentary + star rating + Done.
/// Tap anywhere skips straight to the final stage. Reduce Motion direct-sets the
/// final state: no scanline, no scramble, no roll, no cracks.
struct WorkoutSummaryView: View {
    let summary: WorkoutSummaryData

    @Environment(ProgressionStore.self) private var progression
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage: Int, Comparable {
        case scanning, power, ceiling, net, badges, xp, commentary
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Badge keys that count as breaking a ceiling even without a tier change.
    private static let ceilingBadgeKeys: Set<String> = [
        "new_ceiling", "limit_break", "walking_legend", "scanner_breaker",
    ]

    @State private var stage: Stage = .scanning
    @State private var displayedPowerLevel = 0
    @State private var ratingHalfStars = 0
    @State private var showingHowXPWorks = false

    // Scan Ritual v3 choreography.
    @State private var scrambling = false
    @State private var ceremonyPunch: CGFloat = 1
    @State private var shakeX: CGFloat = 0
    @State private var showCrack = false
    @State private var crackProgress: Double = 0
    @State private var crackOpacity: Double = 1

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if stage >= .power {
                    SystemMessageView(title: "READING COMPLETE")
                        .transition(.opacity)
                }
                scanCard
                if stage >= .ceiling && ceilingBroken {
                    SystemMessageView(title: "CEILING BROKEN")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if stage >= .net {
                    if summary.isCasual {
                        SystemMessageView(title: "OFF THE RECORD",
                                          body: "This session won't count toward net progress. Everything else still counts.")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        netCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                if stage >= .badges && !summary.newBadgeKeys.isEmpty {
                    badgesCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if stage >= .xp && !summary.xpEarned.isEmpty {
                    xpCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if stage >= .commentary {
                    commentaryCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    wrapUp
                        .transition(.opacity)
                }
            }
            .padding(16)
        }
        .background(
            TimeChamberBackground(tier: summaryTier, assetName: bgAsset).ignoresSafeArea()
        )
        .overlay {
            // The ceiling break: UI fractures over the whole screen, gold light
            // leaking through. Non-interactive (CrackOverlay ignores hits), so
            // tap-to-skip keeps working underneath.
            if showCrack {
                CrackOverlay(progress: crackProgress, color: summaryTier.color)
                    .opacity(crackOpacity)
                    .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { skipToEnd() }
        // The ritual owns the screen from frame one: full-height sheet, no grabber,
        // chamber-dark background (configured here, inside the presented content —
        // these propagate up to the enclosing sheet in RootView).
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(TimeChamber.void)
        .task { await runStages() }
        .sheet(isPresented: $showingHowXPWorks) {
            HowPowerWorksView()
        }
    }

    // MARK: Staging

    private var powerDelta: Int { summary.powerLevelAfter - summary.powerLevelBefore }

    /// Tier of the active character rose, or a ceiling-class badge landed.
    private var ceilingBroken: Bool {
        summary.tierAfter > summary.tierBefore
            || summary.newBadgeKeys.contains(where: Self.ceilingBadgeKeys.contains)
    }

    /// The scouter aura the whole scan wears: red on a ceiling break, amber when
    /// power rose, green otherwise — matching the session's transformation ramp.
    private var summaryTier: AuraTier {
        if ceilingBroken { return .radiant }
        if powerDelta > 0 { return .ascended }
        return .base
    }

    /// The realm this workout ran in (routine's domain snapshot), else the app
    /// default — the summary rides the same backdrop as the session.
    private var bgAsset: String {
        ChamberBackground.resolve(
            summary.domainRaw ?? UserDefaults.standard.string(forKey: "sett.chamberBackground") ?? "nebula"
        ).assetName
    }

    private func runStages() async {
        displayedPowerLevel = summary.powerLevelBefore
        loadExistingRating()
        if reduceMotion {
            // Direct-set: final values, all cards, no choreography.
            displayedPowerLevel = summary.powerLevelAfter
            stage = .commentary
            return
        }
        try? await Task.sleep(for: .seconds(1.2))
        guard stage < .power else { return }
        withAnimation(.snappy) { stage = .power }

        // (c) 500 ms digit-scramble prelude where the numeral will land.
        scrambling = true
        try? await Task.sleep(for: .milliseconds(500))
        guard stage == .power else { return }
        scrambling = false

        // (b) the real SacredNumberView is now showing powerLevelBefore; after a
        // beat, flip the value and let its odometer (slot roll, hit-stop at every
        // crossed hundred, ember burst) do the count-up.
        try? await Task.sleep(for: .milliseconds(250))
        guard stage == .power else { return }
        displayedPowerLevel = summary.powerLevelAfter
        try? await Task.sleep(for: .seconds(1.1))
        guard stage == .power else { return }

        // (d) completion ceremony: scale punch + 3-oscillation 2 pt shake.
        if powerDelta != 0 {
            Haptics.levelUp()
            ceremonyPunch = 1.06
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { ceremonyPunch = 1 }
            for oscillation in 0 ..< 6 { // 6 half-cycles = 3 oscillations
                withAnimation(.linear(duration: 0.05)) {
                    shakeX = oscillation.isMultiple(of: 2) ? 2 : -2
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            withAnimation(.linear(duration: 0.05)) { shakeX = 0 }
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard stage < .ceiling else { return }

        // (e) CEILING BREAK — staged before net/badges/XP.
        if ceilingBroken {
            withAnimation(.snappy) { stage = .ceiling }
            showCrack = true
            crackProgress = 0
            // Timer-driven reveal (CrackOverlay's progress is not animatable):
            // 16 steps × 50 ms = 0.8 s; landing exactly on 1 fires its flash.
            let steps = 16
            for step in 1 ... steps {
                try? await Task.sleep(for: .milliseconds(50))
                guard showCrack else { break }
                crackProgress = Double(step) / Double(steps)
            }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.4)) { crackOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(400))
            showCrack = false
            crackOpacity = 1
        }

        guard stage < .net else { return }
        withAnimation(.snappy) { stage = .net }

        try? await Task.sleep(for: .seconds(0.7))
        guard stage < .badges else { return }
        withAnimation(.snappy) { stage = .badges }
        if !summary.newBadgeKeys.isEmpty { Haptics.prSignature() }

        try? await Task.sleep(for: .seconds(0.7))
        guard stage < .xp else { return }
        withAnimation(.snappy) { stage = .xp }

        try? await Task.sleep(for: .seconds(0.7))
        guard stage < .commentary else { return }
        withAnimation(.snappy) { stage = .commentary }
    }

    private func skipToEnd() {
        guard stage < .commentary else { return }
        // Land everything: the running task's stage guards all fail after this.
        scrambling = false
        showCrack = false
        crackOpacity = 1
        shakeX = 0
        ceremonyPunch = 1
        displayedPowerLevel = summary.powerLevelAfter
        if reduceMotion {
            stage = .commentary
        } else {
            withAnimation(.snappy) { stage = .commentary }
        }
    }

    // MARK: Stage 1 — scan card

    private var scanCard: some View {
        VStack(spacing: 12) {
            Text(summary.title)
                .font(.headline)
                .foregroundStyle(SettColor.bone)
            Text(durationText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(SettColor.ash)
            if stage >= .power {
                VStack(spacing: 8) {
                    Text("POWER LEVEL")
                        .font(.caption2.weight(.semibold))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.ash)
                    powerReadout
                    if powerDelta != 0 {
                        deltaChip
                    }
                }
            } else {
                Text("SCANNING…")
                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                    .kerning(2)
                    .foregroundStyle(summaryTier.color)
                    .frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape.fill(TimeChamber.void.opacity(0.82))
            shape.strokeBorder(summaryTier.color.opacity(0.5), lineWidth: 1.5)
                .shadow(color: summaryTier.color.opacity(0.4), radius: 9)
            CornerTicksShape(length: 7, inset: 7)
                .stroke(summaryTier.color.opacity(0.55), lineWidth: 1)
        }
        .overlay {
            // Clip only the scanline, so the numeral's ember halo can spill.
            if stage == .scanning && !reduceMotion {
                scanline
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .scaleEffect(ceremonyPunch)
        .offset(x: shakeX)
    }

    /// (b) + (c): during the 500 ms prelude a seeded digit-scramble runs where
    /// the numeral will land — cyan, because the reading is still ki, not yet
    /// the sacred number. Then the real SacredNumberView swaps in showing
    /// `powerLevelBefore`; `runStages` flips `displayedPowerLevel` a beat later
    /// and the view's own odometer physics carry the count-up.
    @ViewBuilder
    private var powerReadout: some View {
        if scrambling {
            HStack(spacing: 10) {
                SettSigil(size: 34, color: summaryTier.color)
                ScrambleNumeral(
                    digitCount: String(max(summary.powerLevelAfter, 1)).count,
                    seed: UInt64(bitPattern: Int64(summary.powerLevelAfter))
                        &* 0x9E37_79B9_7F4A_7C15
                        &+ UInt64(bitPattern: Int64(summary.powerLevelBefore)),
                    color: summaryTier.color
                )
            }
            .frame(height: 68)
        } else {
            SacredNumberView(value: displayedPowerLevel, size: .xl)
                .frame(height: 68)
        }
    }

    private var deltaChip: some View {
        Text("\(powerDelta > 0 ? "+" : "")\(powerDelta) ⚡")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(SettColor.saiyanGold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(SettColor.saiyanGold.opacity(0.15), in: Capsule())
    }

    /// The scouter scan: a horizontal band in the scan's aura hue sweeping down the
    /// dark card, driven by `phaseAnimator` while the scan stage is active.
    private var scanline: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, summaryTier.color.opacity(0.8), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 28)
                .phaseAnimator([0.0, 1.0]) { view, phase in
                    view.offset(y: phase * (proxy.size.height + 28) - 28)
                } animation: { phase in
                    phase == 1.0 ? .linear(duration: 1.2) : .linear(duration: 0.01)
                }
        }
        .allowsHitTesting(false)
    }

    private var durationText: String {
        let minutes = max(1, summary.durationSeconds / 60)
        return "\(minutes) min"
    }

    // MARK: Stage 2 — net progress

    private var netCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Net Progress",
                  systemImage: summary.netVolumeGrams >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.title3.weight(.semibold))
            if summary.netIsNew {
                Text("NEW TERRITORY")
                    .font(.headline)
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
                Text("First time logging this work — baseline set.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 24) {
                    netStat(value: netWeightText, caption: "net weight",
                            positive: summary.netVolumeGrams >= 0)
                    netStat(value: netRepsText, caption: "net reps",
                            positive: summary.netReps >= 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func netStat(value: String, caption: String, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(PowerFont.m())
                .monospacedDigit()
                .foregroundStyle(positive ? SettColor.positive : SettColor.negative)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var netWeightText: String {
        let pounds = Int(Units.pounds(fromGrams: summary.netVolumeGrams).rounded())
        return "\(pounds >= 0 ? "+" : "")\(pounds) lb"
    }

    private var netRepsText: String {
        "\(summary.netReps >= 0 ? "+" : "")\(summary.netReps)"
    }

    // MARK: Stage 3 — badges earned

    private var badgesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Badges Earned", systemImage: "medal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SettColor.bone)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(summary.newBadgeKeys, id: \.self) { key in
                        badgeMedallion(key)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func badgeMedallion(_ key: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "medal.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Aura.gold, in: Circle())
            Text(badgeName(key))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .frame(width: 84)
        }
    }

    private func badgeName(_ key: String) -> String {
        progression.config?.badge(key)?.name ?? key
    }

    // MARK: Stage 4 — XP earned

    /// Characters that gained XP this workout, in roster order (Vego first).
    private var xpEntries: [(character: CharacterKey, xp: Int)] {
        CharacterKey.allCases.compactMap { character in
            summary.xpEarned[character].map { (character, $0) }
        }
    }

    private var xpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("XP Earned", systemImage: "bolt.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SettColor.bone)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(xpEntries, id: \.character) { entry in
                    xpRow(entry)
                }
            }
            Button {
                showingHowXPWorks = true
            } label: {
                Text("How XP works")
                    .font(.footnote)
                    .underline()
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens an explainer of how XP and Power Level are earned")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func xpRow(_ entry: (character: CharacterKey, xp: Int)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("⚡ +\(entry.xp) XP")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(SettColor.saiyanGold)
            Text("— \(entry.character.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.character.displayName) earned \(entry.xp) XP")
    }

    // MARK: Stage 5 — commentary + wrap-up

    private var commentaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scanner Report", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            Text(summary.commentary)
                .font(.body)
            Text(summary.commentarySource == .onDevice ? "Generated on device" : "sett scanner")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var wrapUp: some View {
        VStack(spacing: 16) {
            starRating
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    // MARK: Star rating (0…10 half stars on 5 tappable stars)

    private var starRating: some View {
        VStack(spacing: 8) {
            Text("Rate this workout")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    starButton(star)
                }
            }
            // One adjustable VoiceOver control (swipe up/down = ±½ star) instead of
            // five onTapGesture halves VoiceOver can't reach.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Workout rating")
            .accessibilityValue(ratingValueText)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setRating(halfStars: min(10, ratingHalfStars + 1))
                case .decrement: setRating(halfStars: max(0, ratingHalfStars - 1))
                @unknown default: break
                }
            }
        }
    }

    private func starButton(_ star: Int) -> some View {
        // Cyan, not gold: rating is an input control (ki/action), not a reward.
        Image(systemName: starSymbol(star))
            .font(.title)
            .foregroundStyle(SettColor.heroCyan)
            .frame(width: 44, height: 44)
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { setRating(halfStars: star * 2 - 1) }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { setRating(halfStars: star * 2) }
                }
            }
            .accessibilityHidden(true)   // the parent row is the adjustable a11y element
    }

    private var ratingValueText: String {
        ratingHalfStars == 0 ? "Not rated"
            : "\(String(format: "%.1f", Double(ratingHalfStars) / 2)) stars"
    }

    private func starSymbol(_ star: Int) -> String {
        if ratingHalfStars >= star * 2 {
            "star.fill"
        } else if ratingHalfStars == star * 2 - 1 {
            "star.leadinghalf.filled"
        } else {
            "star"
        }
    }

    private func setRating(halfStars: Int) {
        // Tapping the current value again clears the rating.
        ratingHalfStars = ratingHalfStars == halfStars ? 0 : halfStars
        Haptics.selection()
        persistRating()
    }

    private func loadExistingRating() {
        ratingHalfStars = fetchWorkout()?.ratingHalfStars ?? 0
    }

    private func persistRating() {
        guard let workout = fetchWorkout() else { return }
        workout.ratingHalfStars = ratingHalfStars == 0 ? nil : ratingHalfStars
        workout.updatedAt = .now
        workout.needsPush = true
        try? modelContext.save()
    }

    private func fetchWorkout() -> Workout? {
        let workoutID = summary.id
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutID })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}

// MARK: - Digit-scramble prelude (Scan Ritual v3, step c)

/// Mono digits cycling seeded pseudo-random values, one per numeral position:
/// ~9 frames over ~500 ms (55 ms cadence), each frame a PURE function of
/// (seed, frame, position) through an LCG — deterministic chrome, never
/// SystemRandom, never Date. The parent swaps this out for the real
/// SacredNumberView when the prelude ends; this view never appears under
/// Reduce Motion (the ritual direct-sets instead).
private struct ScrambleNumeral: View {
    let digitCount: Int
    let seed: UInt64
    var color: Color = SettColor.heroCyan

    @State private var frame = 0

    var body: some View {
        Text(scrambledText)
            .font(.system(size: 56, weight: .heavy, design: .monospaced).italic())
            .foregroundStyle(color.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityHidden(true)
            .task {
                for step in 1 ..< 9 {
                    try? await Task.sleep(for: .milliseconds(55))
                    frame = step
                }
            }
    }

    private var scrambledText: String {
        // Knuth MMIX LCG, re-seeded per frame so every position cycles.
        var state = seed &+ UInt64(frame + 1) &* 0x9E37_79B9_7F4A_7C15
        var digits = ""
        for _ in 0 ..< max(digitCount, 1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            digits += String((state >> 33) % 10)
        }
        return digits
    }
}
