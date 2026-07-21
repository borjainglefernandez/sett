import SwiftUI
import SettCore

// MARK: - Muscle balance (tonnage share per muscle group, period-driven)

/// Where the selected period's work actually went — tonnage share per muscle group as
/// horizontal phosphor bars. Unlike the Power tab's fixed 28-day radar, this follows
/// the W/M/Y picker, so it answers "was THIS week balanced?". The heaviest group wears
/// amber; groups with zero work are listed dim so a neglected muscle is visible, not
/// just absent. Post legs-split the list stays FOLDED at the coarse axes via
/// `MuscleFold` — the per-muscle lower-body story belongs to VolumeLandmarksCard;
/// this card is about the big shape of the week.
struct MuscleBalanceCard: View {
    let samples: [SetSample]
    let period: Period
    let calendar: Calendar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One-time on-appear grow: bars render at zero width until this flips.
    @State private var revealed = false

    private var interval: DateInterval? {
        let component: Calendar.Component = switch period {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        return calendar.dateInterval(of: component, for: .now)
    }

    private var periodCaption: String {
        switch period {
        case .week: "this week"
        case .month: "this month"
        case .year: "this year"
        }
    }

    /// (coarse axis, tonnage share 0…1) sorted heaviest-first; zero-work axes trail.
    /// Samples arrive fine-grained (glutes/hams/quads/calves) but fold to the coarse
    /// axes here — `Muscle.allCases` would splinter "lower" into five thin rows.
    private var shares: [(muscle: Muscle, share: Double)] {
        guard let interval else { return [] }
        let working = samples.filter { interval.contains($0.completedAt) && !$0.isWarmup }
        var tonnage: [Muscle: Int] = [:]
        for sample in working {
            tonnage[MuscleFold.axis(for: sample.muscle), default: 0] += sample.weightGrams * sample.reps
        }
        let total = tonnage.values.reduce(0, +)
        guard total > 0 else { return [] }
        return MuscleFold.balanceAxes
            .map { (muscle: $0, share: Double(tonnage[$0] ?? 0) / Double(total)) }
            .sorted { $0.share > $1.share }
    }

    var body: some View {
        let shares = shares
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle("Muscle Balance")
                    Eyebrow(periodCaption.uppercased())
                }
                let top = shares.first?.share ?? 1
                ForEach(Array(shares.enumerated()), id: \.element.muscle) { index, entry in
                    bar(entry.muscle, share: entry.share, index: index,
                        isTop: entry.share >= top && entry.share > 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary(shares))
            .onAppear { revealed = true }   // bar .animation drives the stagger; RM = direct
        }
    }

    private func bar(_ muscle: Muscle, share: Double, index: Int, isTop: Bool) -> some View {
        let color: Color = share == 0 ? SettColor.iron
                         : isTop ? TimeChamber.scouterAmber : SettColor.heroCyan
        return HStack(spacing: 10) {
            Text(MuscleFold.label(for: muscle))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettColor.cardNested)
                    Capsule()
                        .fill(color.opacity(share == 0 ? 0.3 : 0.85))
                        .frame(width: max(share > 0 ? 4 : 0, geo.size.width * share) * (revealed ? 1 : 0))
                        .shadow(color: color.opacity(isTop ? 0.4 : 0), radius: 3)
                        // ~40 ms per-row stagger so the card sweeps top-down; RM = no animation.
                        .animation(reduceMotion ? nil : Animation.snappy.delay(Double(index) * 0.04),
                                   value: revealed)
                }
            }
            .frame(height: 8)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.ash)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(minHeight: 16)
    }

    private func accessibilitySummary(_ shares: [(muscle: Muscle, share: Double)]) -> String {
        let parts = shares.filter { $0.share > 0 }.prefix(3).map {
            "\(MuscleFold.spokenName(for: $0.muscle)) \($0.share.formatted(.percent.precision(.fractionLength(0))))"
        }
        return "Muscle balance \(periodCaption): " + parts.joined(separator: ", ")
    }
}

// MARK: - MuscleFold (the ONE coarse-axis fold both balance surfaces read through)

/// After the legs split the store speaks in fine-grained lower-body muscles
/// (glutes / hamstrings / quadriceps / calves, plus the legacy `.legs`), but a
/// 9-axis mini radar has no readable shape and a splintered share list buries the
/// signal — so this card AND the Power tab's radar fold every `Muscle.lowerBody`
/// case into one "LOWER" axis. `.legs` is the fold's key: it's already the
/// legacy lower-body bucket, so pre-migration data lands on the same axis for
/// free. One helper, deliberately in this file (not PowerTabView), so the two
/// surfaces can't drift apart on what "LOWER" contains.
enum MuscleFold {
    /// The coarse axis a sample files under: lower-body folds to `.legs`,
    /// everything else is already coarse.
    static func axis(for muscle: Muscle) -> Muscle {
        Muscle.lowerBody.contains(muscle) ? .legs : muscle
    }

    /// The six primary axes in fixed radar order (top, clockwise) — the shape
    /// the Power radar has always drawn.
    static let radarAxes: [Muscle] = [.chest, .triceps, .biceps, .shoulders, .back, .legs]

    /// Every axis the balance list shows: the radar six plus core and other.
    static let balanceAxes: [Muscle] = radarAxes + [.core, .other]

    /// Mono chip label — on a folded surface `.legs` means "all of lower body",
    /// so it wears LOWER, not the legacy LEGS.
    static func label(for axis: Muscle) -> String {
        axis == .legs ? "LOWER" : axis.rawValue.uppercased()
    }

    /// VoiceOver name for an axis ("lower body", not the raw "legs").
    static func spokenName(for axis: Muscle) -> String {
        axis == .legs ? "lower body" : axis.rawValue
    }
}
