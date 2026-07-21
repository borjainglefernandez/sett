import SwiftUI
import Charts
import SettCore

/// Power Level, week by week — a bar per ISO week of how much PL you built (or
/// gave back), with your current cadence (the trailing 4-week average) called out.
/// The all-time line answers "where am I"; this answers "how fast am I moving now".
/// Gains read positive, down-weeks negative (the receipt-lever palette); the cadence
/// number is gold, the power level's hue.
struct WeeklyPowerCard: View {
    let weeks: [WeeklyPLChange]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One-time on-appear grow: bars plot flat until this flips.
    @State private var revealed = false

    /// Trailing 4-week average ΔPL — "the cadence we have right now", signed so a
    /// stall or a cut reads honestly rather than flooring at zero.
    private var cadence: Int {
        let recent = weeks.suffix(4).map(\.deltaPL)
        guard !recent.isEmpty else { return 0 }
        return Int((Double(recent.reduce(0, +)) / Double(recent.count)).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Weekly change")
                Spacer(minLength: 8)
                if weeks.count >= 2 {
                    Text("\(signed(cadence)) /wk avg")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(SettColor.saiyanGold)
                }
            }
            if weeks.count >= 2 {
                chart
                if let footnote { Text(footnote).font(.caption).monospacedDigit()
                    .foregroundStyle(SettColor.ash) }
            } else {
                Text("A few weeks in and your week-by-week pace shows here.")
                    .font(.subheadline)
                    .foregroundStyle(SettColor.ash)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
        .onAppear {
            if reduceMotion { revealed = true }
            else { withAnimation(.snappy) { revealed = true } }
        }
    }

    private var chart: some View {
        let half = yHalfRange
        return Chart(weeks, id: \.weekStart) { week in
            // Draw only up to the clamped edge — a lone −4,000 deload would otherwise own
            // the whole scale and flatten every ±200 week into a nub. The true depth rides
            // in the break caret, so nothing is lost, just re-anchored to the everyday range.
            let drawn = max(-half, min(half, week.deltaPL))
            BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Change", drawn * (revealed ? 1 : 0)))
                .foregroundStyle(barColor(week.deltaPL))
                .cornerRadius(3)
                .annotation(position: week.deltaPL >= 0 ? .top : .bottom,
                            spacing: 1,
                            overflowResolution: .init(x: .fit, y: .fit)) {
                    // Only weeks that overrun the clamp wear a caret + their real value.
                    if abs(week.deltaPL) > half { breakGlyph(week.deltaPL) }
                }
        }
        .chartYScale(domain: -half...half)
        .chartYAxisLabel("Δ PL")
        .frame(height: 150)
        .scouterChart(xCount: 4, yCount: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power level change per week")
        .accessibilityValue(accessibilitySummary)
    }

    /// Up-weeks positive ink, true down-weeks the negative hue. A flat 0 is this data's
    /// rest week (the trajectory carries the last close across an untrained week), so it
    /// takes heroCyan — rest is banked, not a failure — never the alarm red of a decline.
    private func barColor(_ delta: Int) -> Color {
        delta > 0 ? SettColor.positive : (delta < 0 ? SettColor.negative : SettColor.heroCyan)
    }

    /// Half-height of the clamped y-domain. Weekly deltas run from tiny ±150 build-weeks
    /// to a lone −4,000 deload; auto-scaling to that outlier flattens every normal week.
    /// Anchor the frame to ~1.5× the median absolute week so the everyday cadence fills it,
    /// floored at 300 so a calm stretch of tiny weeks still reads (outliers break past it).
    private var yHalfRange: Int {
        let magnitudes = weeks.map { abs($0.deltaPL) }.sorted()
        guard !magnitudes.isEmpty else { return 300 }
        let mid = magnitudes.count / 2
        let median = magnitudes.count.isMultiple(of: 2)
            ? Double(magnitudes[mid - 1] + magnitudes[mid]) / 2
            : Double(magnitudes[mid])
        return max(300, Int((median * 1.5).rounded()))
    }

    /// The break marker a clamped bar wears at the axis edge: a caret pointing off-scale
    /// plus the week's real ΔPL, so a deep deload the frame can't hold still reads its true
    /// depth. Colour tracks the bar, so a broken decline stays in the negative hue, not gold.
    private func breakGlyph(_ delta: Int) -> some View {
        VStack(spacing: 0) {
            Text("‸")
                .font(.system(size: 10, weight: .black))
                .rotationEffect(.degrees(delta < 0 ? 180 : 0))
            Text(signed(delta))
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(barColor(delta))
        .fixedSize()
    }

    private func signed(_ value: Int) -> String {
        (value >= 0 ? "+" : "−") + abs(value).formatted()
    }

    private var footnote: String? {
        guard let best = weeks.map(\.deltaPL).max() else { return nil }
        return "\(weeks.count) weeks · best +\(best.formatted()) PL"
    }

    private var accessibilitySummary: String {
        let up = weeks.filter { $0.deltaPL > 0 }.count
        var summary = "\(weeks.count) weeks, \(up) up. Cadence \(signed(cadence)) power level per week."
        // The chart clamps outliers to keep the everyday range legible, so name the extremes
        // here — otherwise a VoiceOver read would lose the true depth of a clamped deload.
        if let peak = weeks.map(\.deltaPL).max(), let trough = weeks.map(\.deltaPL).min(),
           max(abs(peak), abs(trough)) > yHalfRange {
            summary += " Range \(signed(trough)) to \(signed(peak))."
        }
        return summary
    }
}
