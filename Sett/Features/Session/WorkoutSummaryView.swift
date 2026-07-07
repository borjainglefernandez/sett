import SwiftUI
import SwiftData
import SettCore

/// The Power Scan (Flow 2). One screen, staged reveal:
/// 1. dark scan card — a horizontal cyan scanline sweeps, then the power level rolls
///    up from its previous value (`contentTransition(.numericText)`) with a gold "+N ⚡" chip;
/// 2. net progress vs previous same-exercise sessions;
/// 3. badges earned (gold medallions, only when non-empty);
/// 4. AI commentary + star rating + Done.
/// Tap anywhere skips straight to the final stage. Reduce Motion skips the scanline
/// and snaps numbers.
struct WorkoutSummaryView: View {
    let summary: WorkoutSummaryData

    @Environment(ProgressionStore.self) private var progression
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Stage: Int, Comparable {
        case scanning, power, net, badges, commentary
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @State private var stage: Stage = .scanning
    @State private var displayedPowerLevel = 0
    @State private var ratingHalfStars = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                scanCard
                if stage >= .net {
                    netCard
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
        .background(SettColor.screen)
        .contentShape(Rectangle())
        .onTapGesture { skipToEnd() }
        .task { await runStages() }
    }

    // MARK: Staging

    private var powerDelta: Int { summary.powerLevelAfter - summary.powerLevelBefore }

    private func runStages() async {
        displayedPowerLevel = summary.powerLevelBefore
        loadExistingRating()
        if reduceMotion {
            stage = .commentary
            displayedPowerLevel = summary.powerLevelAfter
            return
        }
        try? await Task.sleep(for: .seconds(1.4))
        guard stage < .power else { return }
        withAnimation(.snappy) { stage = .power }
        withAnimation(.spring(duration: 0.9)) { displayedPowerLevel = summary.powerLevelAfter }

        try? await Task.sleep(for: .seconds(1.0))
        guard stage < .net else { return }
        withAnimation(.snappy) { stage = .net }

        try? await Task.sleep(for: .seconds(0.7))
        guard stage < .badges else { return }
        withAnimation(.snappy) { stage = .badges }
        if !summary.newBadgeKeys.isEmpty { Haptics.prSignature() }

        try? await Task.sleep(for: .seconds(0.7))
        guard stage < .commentary else { return }
        withAnimation(.snappy) { stage = .commentary }
    }

    private func skipToEnd() {
        guard stage < .commentary else { return }
        if reduceMotion {
            stage = .commentary
            displayedPowerLevel = summary.powerLevelAfter
        } else {
            withAnimation(.snappy) { stage = .commentary }
            withAnimation(.spring(duration: 0.5)) { displayedPowerLevel = summary.powerLevelAfter }
        }
    }

    // MARK: Stage 1 — scan card

    private var scanCard: some View {
        VStack(spacing: 12) {
            Text(summary.title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
            Text(durationText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5))
            if stage >= .power {
                VStack(spacing: 8) {
                    Text("POWER LEVEL")
                        .font(.caption2.weight(.semibold))
                        .kerning(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                    PowerNumeral(displayedPowerLevel, size: .xl)
                    if powerDelta != 0 {
                        deltaChip
                    }
                }
            } else {
                Text("Scanning…")
                    .font(.footnote)
                    .foregroundStyle(SettColor.heroCyan)
                    .frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if stage == .scanning && !reduceMotion {
                scanline
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    /// The scouter reference: a horizontal cyan band sweeping down the dark card,
    /// driven by `phaseAnimator` while the scan stage is active.
    private var scanline: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, SettColor.heroCyan.opacity(0.8), .clear],
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
                .foregroundStyle(SettColor.saiyanGold)
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

    // MARK: Stage 4 — commentary + wrap-up

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
        }
    }

    private func starButton(_ star: Int) -> some View {
        Image(systemName: starSymbol(star))
            .font(.title)
            .foregroundStyle(SettColor.saiyanGold)
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
            .accessibilityLabel("Rate \(star) stars")
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
