import SwiftUI
import Charts
import SettCore

/// A chart point for e1RM series, shared by the sparkline tiles and the
/// full-size detail chart. Value is already converted to the display unit.
struct E1RMChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Card 3 — horizontal scroll of per-exercise e1RM sparklines for the six
/// most-trained exercises; each tile pushes the full interactive chart.
struct E1RMTrendsCard: View {
    let samples: [SetSample]
    let exerciseNames: [UUID: String]
    let unit: WeightUnit

    private struct Trend: Identifiable {
        let id: UUID
        let name: String
        let points: [E1RMChartPoint]
    }

    private var trends: [Trend] {
        let working = samples.filter { !$0.isWarmup }
        let counts = Dictionary(grouping: working, by: \.exerciseID).mapValues(\.count)
        let top = counts.sorted {
            $0.value == $1.value ? $0.key.uuidString < $1.key.uuidString : $0.value > $1.value
        }.prefix(6)
        return top.map { entry in
            let series = ProgressEngine.bestE1RMSeries(samples: samples, exerciseID: entry.key)
            return Trend(
                id: entry.key,
                name: exerciseNames[entry.key] ?? "Exercise",
                points: series.map {
                    E1RMChartPoint(date: $0.date, value: Units.displayValue(grams: $0.e1RMGrams, unit: unit))
                }
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("e1RM Trends")
                .font(.title3.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(trends) { trend in
                        NavigationLink {
                            ChartDetailView(exerciseID: trend.id, name: trend.name, samples: samples)
                        } label: {
                            sparklineTile(trend)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func sparklineTile(_ trend: Trend) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trend.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)   // "Bulgarian Split Squat" fits the 156pt tile
            Chart(trend.points) { point in
                LineMark(x: .value("Date", point.date),
                         y: .value("e1RM", point.value))
                    .foregroundStyle(SettColor.heroCyan)
                    .interpolationMethod(.monotone)
                    .symbol(.circle)
                    .symbolSize(16)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 48)
            .allowsHitTesting(false)
            if let latest = trend.points.last {
                Text(WeightText.formatted(latest.value, unit: unit))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 156, alignment: .leading)
        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tileAccessibilityLabel(trend))
    }

    private func tileAccessibilityLabel(_ trend: Trend) -> String {
        guard let latest = trend.points.last else { return trend.name }
        return "\(trend.name), latest e1RM \(WeightText.formatted(latest.value, unit: unit))"
    }
}

/// Shared display-unit weight formatting for the Progress tab.
enum WeightText {
    static func formatted(_ value: Double, unit: WeightUnit) -> String {
        let text = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(text) \(unit.symbol)"
    }

    static func formatted(grams: Int, unit: WeightUnit) -> String {
        formatted(Units.displayValue(grams: grams, unit: unit), unit: unit)
    }
}
