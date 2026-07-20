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
        Chart(weeks, id: \.weekStart) { week in
            BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Change", week.deltaPL * (revealed ? 1 : 0)))
                .foregroundStyle(barColor(week.deltaPL))
                .cornerRadius(3)
        }
        .chartYAxisLabel("Δ PL")
        .frame(height: 150)
        .scouterChart(xCount: 4, yCount: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power level change per week")
        .accessibilityValue(accessibilitySummary)
    }

    /// Up-weeks positive ink, down-weeks negative, a flat rest week faint iron.
    private func barColor(_ delta: Int) -> Color {
        delta > 0 ? SettColor.positive : (delta < 0 ? SettColor.negative : SettColor.iron)
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
        return "\(weeks.count) weeks, \(up) up. Cadence \(signed(cadence)) power level per week."
    }
}
