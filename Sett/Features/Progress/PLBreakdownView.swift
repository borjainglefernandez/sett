import SwiftUI
import SettCore

/// The power level, cracked open. Two reads on the one number the app orbits:
///   • "What builds it" — the current PL split into its strength and volume halves
///     (proportional gold bars) plus the standalone PL the streak stacks on top.
///   • "What moved it" — over a chosen window, a signed split across the three levers
///     that sums exactly to the delta, with the biggest mover called out.
/// Gold is the power level's hue by law, so the "builds it" bars are gold; the
/// "moved it" deltas follow the summary receipt's up/down/flat ink. Reduce-Motion
/// safe — the reveal is decorative, nothing depends on it.
struct PLBreakdownView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The trailing window driving the attribution section.
    @State private var window: AttributionWindow = .month
    /// One-time on-appear grow for the bars (skipped under Reduce Motion).
    @State private var revealed = false

    private enum AttributionWindow: Hashable {
        case month, quarter, all
        /// Mapped to the store's `overDays` — "All" is a sentinel past any history.
        var days: Int {
            switch self {
            case .month: return 30
            case .quarter: return 90
            case .all: return 100_000
            }
        }
        var label: String {
            switch self {
            case .month: return "1M"
            case .quarter: return "3M"
            case .all: return "All"
            }
        }
        /// Sentence-case fragment for the helper line.
        var phrase: String {
            switch self {
            case .month: return "this past month"
            case .quarter: return "over the last three months"
            case .all: return "across your whole history"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            buildsSection
            movesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
        .onAppear {
            if reduceMotion { revealed = true }
            else { withAnimation(.snappy) { revealed = true } }
        }
    }

    // MARK: - What builds it

    @ViewBuilder
    private var buildsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("What builds it")
            if let comp = services.progression.powerLevelComposition {
                contributorRow(label: "STRENGTH", pl: comp.strengthPL,
                               share: comp.strengthShare, intensity: 1.0)
                contributorRow(label: "VOLUME", pl: comp.volumePL,
                               share: comp.volumeShare, intensity: 0.55)
                if comp.streakBonusPL > 0 {
                    let cm = comp.consistencyMultiplier.formatted(.number.precision(.fractionLength(2)))
                    Text("Streak ×\(cm) · +\(comp.streakBonusPL.formatted()) PL")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.saiyanGold)
                        .padding(.top, 2)
                }
            } else {
                teaser
            }
        }
    }

    /// One gold proportional bar — strength solid, volume dimmed — labelled with its
    /// PL (gold) and its share of the strength+volume base (ash).
    private func contributorRow(label: String, pl: Int, share: Double,
                                intensity: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
                .frame(width: 68, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettColor.cardNested)
                    Capsule()
                        .fill(SettColor.saiyanGold.opacity(intensity))
                        .frame(width: max(share > 0 ? 4 : 0, geo.size.width * share) * (revealed ? 1 : 0))
                }
            }
            .frame(height: 8)
            HStack(spacing: 4) {
                Text(pl.formatted())
                    .foregroundStyle(SettColor.saiyanGold)
                Text("· \(share.formatted(.percent.precision(.fractionLength(0))))")
                    .foregroundStyle(SettColor.ash)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 92, alignment: .trailing)
        }
        .frame(minHeight: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(pl) power level, "
                            + share.formatted(.percent.precision(.fractionLength(0))))
    }

    // MARK: - What moved it

    @ViewBuilder
    private var movesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("What moved it")
                Spacer(minLength: 12)
                ChamberSegments(
                    selection: $window,
                    options: [(.month, AttributionWindow.month.label),
                              (.quarter, AttributionWindow.quarter.label),
                              (.all, AttributionWindow.all.label)],
                    compact: true
                )
                .frame(maxWidth: 168)
            }
            if let attr = services.progression.powerLevelAttribution(overDays: window.days) {
                attributionBody(attr)
            } else {
                teaser
            }
        }
    }

    private func attributionBody(_ attr: PLAttribution) -> some View {
        // Ordered by the receipt's three levers; the largest magnitude is the story.
        let drivers = [("Strength", attr.strength),
                       ("Volume", attr.volume),
                       ("Consistency", attr.consistency)]
        let maxMag = max(1, drivers.map { abs($0.1) }.max() ?? 1)
        let topIndex = drivers.indices.max { abs(drivers[$0].1) < abs(drivers[$1].1) } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text(signed(attr.deltaPL) + " PL")
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(SettColor.saiyanGold)
            ForEach(Array(drivers.enumerated()), id: \.offset) { index, driver in
                driverRow(label: driver.0, value: driver.1, maxMag: maxMag,
                          isTop: index == topIndex)
            }
            Text(helperCopy(topDriver: drivers[topIndex], deltaPL: attr.deltaPL))
                .font(.caption)
                .foregroundStyle(SettColor.ash)
        }
    }

    /// One signed lever row: up/down/flat ink, a proportional bar keyed to the biggest
    /// mover's magnitude, and a "BIGGEST LEVER" tag + bone label on the dominant one.
    private func driverRow(label: String, value: Int, maxMag: Int, isTop: Bool) -> some View {
        let color: Color = value > 0 ? SettColor.positive
                         : (value < 0 ? SettColor.negative : SettColor.ash)
        let frac = Double(abs(value)) / Double(maxMag)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: isTop ? .heavy : .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(isTop ? SettColor.bone : SettColor.ash)
                if isTop {
                    Eyebrow("BIGGEST LEVER", tint: SettColor.heroCyan)
                }
            }
            .frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SettColor.cardNested)
                    Capsule()
                        .fill(color.opacity(value == 0 ? 0.3 : 0.85))
                        .frame(width: max(value != 0 ? 4 : 0, geo.size.width * frac) * (revealed ? 1 : 0))
                }
            }
            .frame(height: 8)
            Text(signed(value))
                .font(.system(size: 11, weight: isTop ? .bold : .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 52, alignment: .trailing)
        }
        .frame(minHeight: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(signed(value)) power level\(isTop ? ", the biggest lever" : "")")
    }

    // MARK: - Copy helpers

    private var teaser: some View {
        Text("Log a couple more sessions to break down your power.")
            .font(.subheadline)
            .foregroundStyle(SettColor.ash)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Signed integer with the app's minus glyph (matches the PL history footnote).
    private func signed(_ value: Int) -> String {
        (value >= 0 ? "+" : "−") + abs(value).formatted()
    }

    private func helperCopy(topDriver: (String, Int), deltaPL: Int) -> String {
        if deltaPL == 0 || topDriver.1 == 0 {
            return "Your power held flat \(window.phrase)."
        }
        let verb = topDriver.1 > 0 ? "did the most to lift your power"
                                   : "pulled your power down the most"
        return "\(topDriver.0) \(verb) \(window.phrase)."
    }
}
