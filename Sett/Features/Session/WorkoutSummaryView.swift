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
/// 5. AI commentary + star rating + Done.
/// Tap anywhere skips straight to the final stage. Reduce Motion direct-sets the
/// final state: no scanline, no scramble, no roll, no cracks.
struct WorkoutSummaryView: View {
    let summary: WorkoutSummaryData

    @Environment(ProgressionStore.self) private var progression
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage: Int, Comparable {
        case scanning, power, ceiling, net, badges, commentary
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Badge keys that count as breaking a ceiling even without a tier change.
    private static let ceilingBadgeKeys: Set<String> = [
        "new_ceiling", "limit_break", "walking_legend", "scanner_breaker",
    ]

    @State private var stage: Stage = .scanning
    @State private var displayedPowerLevel = 0
    @State private var ratingHalfStars = 0
    /// Rendered dark-chamber share card (the social pillar's zero-backend v0).
    @State private var shareImage: Image?
    /// The Scouter Manual, reachable from the receipt so PL never reads as a black box.
    @State private var isShowingHowPowerWorks = false
    /// Post-session note staged/persisted from the wrap-up row.
    @State private var sessionNotes: String?
    @State private var isEditingSessionNotes = false

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
                if stage >= .badges && !summary.completedGoalTitles.isEmpty {
                    goalCompleteCard
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if stage >= .badges && !summary.newBadgeKeys.isEmpty {
                    badgesCard
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
        // SIMULTANEOUS, not .onTapGesture: a plain tap gesture on the ScrollView
        // competed with the Done button (and rating stars / notes) and could swallow
        // their taps — the "Done doesn't work" bug. Simultaneous lets tap-to-skip and
        // the child controls both recognize; skipToEnd() is a no-op once at commentary.
        .simultaneousGesture(TapGesture().onEnded { skipToEnd() })
        // The ritual owns the screen from frame one: full-height sheet, no grabber,
        // chamber-dark background (configured here, inside the presented content —
        // these propagate up to the enclosing sheet in RootView).
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(TimeChamber.void)
        .sheet(isPresented: $isShowingHowPowerWorks) {
            HowPowerWorksView()
        }
        .sheet(isPresented: $isEditingSessionNotes) {
            SetNoteSheet(initialText: sessionNotes ?? "",
                         title: "Session Notes",
                         placeholder: "great pump, rushed the last superset…") { note in
                sessionNotes = note
                if let workout = fetchWorkout() { session.setWorkoutNotes(note, for: workout) }
            }
        }
        .task { await runStages() }
        .task { renderShareCard() }
    }

    @MainActor private func renderShareCard() {
        let card = SummaryShareCard(
            title: summary.title,
            powerLevel: summary.powerLevelAfter,
            netReps: summary.netReps,
            netVolumeGrams: summary.netVolumeGrams,
            netIsNew: summary.netIsNew,
            durationSeconds: summary.durationSeconds,
            unit: services.settings.unit,
            isCasual: summary.isCasual
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage.map(Image.init(uiImage:))
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

        try? await Task.sleep(for: .seconds(1.4))
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
                    // (i) → the Scouter Manual — HowPowerWorks, discoverable at the
                    // exact moment the number lands.
                    HStack(spacing: 5) {
                        Eyebrow("POWER LEVEL")
                        Button { isShowingHowPowerWorks = true } label: {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(SettColor.ash)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("How Power Level works")
                    }
                    powerReadout
                    if powerDelta != 0 {
                        deltaChip
                    }
                    receiptRows
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
        .hudCard(tint: summaryTier.color, heavy: true, radius: 18, padding: nil)
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

    /// The receipt: WHERE the delta came from (all three levers) and where the
    /// climb goes next (the endless Forms ladder). PL stops being a black box.
    @ViewBuilder
    private var receiptRows: some View {
        let ssDelta = summary.strengthScoreAfter - summary.strengthScoreBefore
        let wvlDelta = summary.weeklyVolumeLbAfter - summary.weeklyVolumeLbBefore
        let streakMoved = summary.consistencyAfter != summary.consistencyBefore
        let form = UserForm.form(forPL: summary.powerLevelAfter)
        let formBefore = UserForm.form(forPL: summary.powerLevelBefore)
        VStack(spacing: 5) {
            if ssDelta != 0 || wvlDelta != 0 || streakMoved {
                HStack(spacing: 14) {
                    receiptLever("STRENGTH", delta: ssDelta)
                    receiptLever("VOLUME", delta: wvlDelta)
                    if streakMoved { streakLever }
                }
            }
            if summary.surgeActive {
                // Gold-free by design: the surge is banked rest (action), not a reward.
                Text("REST BANKED — VOLUME ×1.25 THIS SCAN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.heroCyan)
            }
            if !summary.didQualify {
                // The POWER LEVEL header already carries the (i) → Scouter Manual; a
                // second info icon on this line just doubled it. Copy is self-explaining.
                Text("NOT A QUALIFYING SCAN — NEEDS 3+ EFFECTIVE SETS · 10+ MIN")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
                    .multilineTextAlignment(.center)
            }
            if form.index > formBefore.index {
                Text("FORM ASCENDED — \(form.title)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.saiyanGold)
                    .shadow(color: SettColor.saiyanGold.opacity(0.5), radius: 5)
            } else {
                Text("\(form.title) · \((form.nextPL - summary.powerLevelAfter).formatted()) PL TO NEXT FORM")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
            }
        }
        .padding(.top, 2)
    }

    private func receiptLever(_ label: String, delta: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
            Text(delta == 0 ? "—" : "\(delta > 0 ? "+" : "")\(delta.formatted())")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(delta > 0 ? SettColor.positive
                                 : delta < 0 ? SettColor.ash : SettColor.iron)
        }
    }

    /// The third lever: the consistency multiplier's move this scan, shown as the
    /// full ×before → ×after so the streak's compounding is legible, not implied.
    private var streakLever: some View {
        HStack(spacing: 4) {
            Text("STREAK")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
            Text("\(multiplierText(summary.consistencyBefore)) → \(multiplierText(summary.consistencyAfter))")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(summary.consistencyAfter > summary.consistencyBefore
                                 ? SettColor.positive : SettColor.ash)
        }
    }

    private func multiplierText(_ value: Double) -> String {
        "×" + value.formatted(.number.precision(.fractionLength(2)))
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
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60) min" }
        return "\(minutes) min"
    }

    // MARK: Stage 2 — net progress

    private var netCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Eyebrow("NET PROGRESS", tint: SettColor.bone)
            } icon: {
                Image(systemName: summary.netVolumeGrams >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(SettColor.heroCyan)
            }
            if summary.netIsNew {
                Text("NEW TERRITORY")
                    .font(.headline)
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
                Text("First time logging this work — baseline set.")
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash)
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
        // A negative net while CUTTING is the expected trade, not an alarm — ash,
        // not red. Bulk/maintain keep the red so a real slide still reads as one.
        let negative = summary.phase == .cutting ? SettColor.ash : SettColor.negative
        return VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(PowerFont.m())
                .monospacedDigit()
                .foregroundStyle(positive ? SettColor.positive : negative)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
    }

    private var netWeightText: String {
        let unit = services.settings.unit
        let value = Int((Double(summary.netVolumeGrams) / unit.gramsPerUnit).rounded())
        return "\(value >= 0 ? "+" : "")\(value) \(unit.symbol)"
    }

    private var netRepsText: String {
        "\(summary.netReps >= 0 ? "+" : "")\(summary.netReps)"
    }

    // MARK: Stage 3 — badges earned

    private var badgesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Eyebrow("BADGES EARNED", tint: SettColor.bone)
            } icon: {
                Image(systemName: "medal.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(SettColor.saiyanGold)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(summary.newBadgeKeys.enumerated()), id: \.element) { index, key in
                        BadgePremiereMedallion(name: badgeName(key), index: index)
                    }
                }
            }
            // Bursts spill past the ScrollView's bounds — don't clip the premiere.
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func badgeName(_ key: String) -> String {
        progression.config?.badge(key)?.name ?? key
    }

    /// A goal crossed its finish line during this scan — a gold beat in the ceremony,
    /// revealed alongside the badges stage.
    private var goalCompleteCard: some View {
        SystemMessageView(title: "GOAL COMPLETE",
                          body: summary.completedGoalTitles.joined(separator: "\n"))
            .overlay { AuraBurstView(gold: true) }
    }


    // MARK: Stage 5 — commentary + wrap-up

    private var commentaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Eyebrow("SCANNER REPORT", tint: SettColor.bone)
            } icon: {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(SettColor.heroCyan)
            }
            Text(summary.commentary)
                .font(.body)
                .foregroundStyle(SettColor.bone)
            Text(summary.commentarySource == .onDevice ? "Generated on device" : "sett scanner")
                .font(.footnote)
                .foregroundStyle(SettColor.iron)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var wrapUp: some View {
        VStack(spacing: 16) {
            starRating
            sessionNotesRow
            if let shareImage, !summary.isCasual {
                ShareLink(item: shareImage,
                          preview: SharePreview("\(summary.title) — POWER LEVEL \(summary.powerLevelAfter)",
                                                image: shareImage)) {
                    Label("Share Power Scan", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SettColor.heroCyan)
                }
            }
            // Dismiss THIS sheet only; the cover it rode up over closes in the sheet's
            // onDismiss (ActiveWorkoutView). Doing both at once — tearing down the cover
            // that hosts this sheet in the same transaction — left the tap dead.
            ChamberCTAButton("Done") { dismiss() }
        }
    }

    /// Optional post-session note, written before Done — the one moment "how did that
    /// feel" is still fresh. Persists straight onto the workout via the store.
    private var sessionNotesRow: some View {
        Button { isEditingSessionNotes = true } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "text.alignleft")
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("SESSION NOTES")
                    if let sessionNotes, !sessionNotes.isEmpty {
                        Text(sessionNotes)
                            .font(.subheadline)
                            .foregroundStyle(SettColor.bone)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("How did this session feel?")
                            .font(.subheadline)
                            .foregroundStyle(SettColor.ash)
                    }
                }
                Spacer(minLength: 4)
                // Was square.and.pencil — its glyph sits high in a tall box, which
                // pulled the whole row up and left a gap at the slab's bottom. The
                // chevron matches the app's other tappable rows and centers cleanly.
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
                    .frame(width: 18)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nestedSlab()
        .accessibilityLabel(sessionNotes?.isEmpty == false
                            ? "Session notes: \(sessionNotes!)" : "Add session notes")
    }

    // MARK: Star rating (0…10 half stars on 5 tappable stars)

    private var starRating: some View {
        VStack(spacing: 8) {
            Text("Rate this workout")
                .font(.subheadline)
                .foregroundStyle(SettColor.ash)
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
        let workout = fetchWorkout()
        ratingHalfStars = workout?.ratingHalfStars ?? 0
        sessionNotes = workout?.notes
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

// MARK: - Badge premiere medallion (Stage 3)

/// One earned medallion, premiered: a spring scale-in (0.6 → 1) plus a one-shot
/// gold AuraBurstView, staggered ~150 ms per index so a multi-badge haul reads as
/// a volley, not a clump. Reduce Motion: direct-set scale, no burst (AuraBurstView
/// is RM-clear anyway).
private struct BadgePremiereMedallion: View {
    let name: String
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.6
    @State private var showBurst = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "medal.fill")
                .font(.title2)
                .foregroundStyle(SettColor.etch)
                .frame(width: 64, height: 64)
                .background(Aura.gold, in: Circle())
                .scaleEffect(scale)
                .overlay {
                    if showBurst {
                        AuraBurstView(gold: true)
                            .frame(width: 130, height: 130)
                    }
                }
            Text(name)
                .font(.caption2)
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(width: 84, height: 28, alignment: .top)
        }
        .task {
            guard !reduceMotion else {
                scale = 1
                return
            }
            try? await Task.sleep(for: .milliseconds(150 * index))
            showBurst = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { scale = 1 }
        }
    }
}

// MARK: - Share card (the social pillar's zero-backend v0)

/// A self-contained dark-chamber card rendered by `ImageRenderer` for ShareLink —
/// the group iMessage thread becomes the interim leaderboard for ~zero cost. The
/// POWER LEVEL stays gold (the sacred number); no @Environment so it renders clean.
struct SummaryShareCard: View {
    let title: String
    let powerLevel: Int
    let netReps: Int
    let netVolumeGrams: Int
    let netIsNew: Bool
    let durationSeconds: Int
    let unit: WeightUnit
    let isCasual: Bool

    private var netVolume: Int { Int((Double(netVolumeGrams) / unit.gramsPerUnit).rounded()) }
    private func signed(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }
    private var durationText: String {
        let m = max(1, durationSeconds / 60)   // floor at 1m, matching the summary card
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SettSigil(size: 20, color: SettColor.saiyanGold)
                Text("SETT")
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .kerning(6)
                    .foregroundStyle(SettColor.bone)
            }
            .padding(.top, 40)

            Spacer()

            Text(title.uppercased())
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(SettColor.ash)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 24)

            Text("POWER LEVEL")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.ash)
                .padding(.top, 26)

            Text("\(powerLevel)")
                .font(.system(size: 92, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.saiyanGold)
                .shadow(color: SettColor.saiyanGold.opacity(0.5), radius: 22)

            Spacer()

            VStack(spacing: 14) {
                if netIsNew {
                    Text("NEW TERRITORY")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(SettColor.heroCyan)
                } else {
                    HStack(spacing: 30) {
                        stat(signed(netReps), "NET REPS")
                        stat(signed(netVolume), "NET \(unit.symbol.uppercased())")
                    }
                }
                stat(durationText, "TIME")
            }
            .padding(.bottom, 40)
        }
        .frame(width: 440, height: 560)
        .background(SettColor.screen)
        .overlay {
            Rectangle().strokeBorder(SettColor.saiyanGold.opacity(0.18), lineWidth: 1)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
        }
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
