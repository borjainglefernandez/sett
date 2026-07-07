import SwiftUI
import Charts
import SettCore

/// Bodyweight card — last 90 days of standalone entries as a monotone cyan line,
/// latest value as the headline, min/max in the footnote.
struct BodyweightCard: View {
    let entries: [BodyweightEntry]
    let unit: WeightUnit

    /// Last 90 days, oldest first (chart order).
    private var recent: [BodyweightEntry] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) else { return [] }
        return entries
            .filter { $0.deletedAt == nil && $0.loggedAt >= cutoff }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    var body: some View {
        let recent = recent
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bodyweight")
                    .font(.headline)
                Spacer()
                Text("last 90 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let latest = recent.last {
                Text(BodyweightFormat.valueWithUnit(grams: latest.weightGrams, unit: unit))
                    .font(.title2.bold())
                    .monospacedDigit()
                Chart(recent) { entry in
                    LineMark(x: .value("Date", entry.loggedAt),
                             y: .value("Weight", displayValue(entry.weightGrams)))
                        .foregroundStyle(SettColor.heroCyan)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: yDomain(recent))
                .frame(height: 140)
                if let footnote = minMaxFootnote(recent) {
                    Text(footnote)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Log your bodyweight from Home")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func displayValue(_ grams: Int) -> Double {
        Double(grams) / unit.gramsPerUnit
    }

    private func yDomain(_ entries: [BodyweightEntry]) -> ClosedRange<Double> {
        let values = entries.map { displayValue($0.weightGrams) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(0.5, (high - low) * 0.15)
        return (low - pad)...(high + pad)
    }

    private func minMaxFootnote(_ entries: [BodyweightEntry]) -> String? {
        let values = entries.map(\.weightGrams)
        guard let low = values.min(), let high = values.max() else { return nil }
        let lowText = BodyweightFormat.value(grams: low, unit: unit)
        let highText = BodyweightFormat.value(grams: high, unit: unit)
        return "min \(lowText) · max \(highText) \(unit.symbol)"
    }
}
