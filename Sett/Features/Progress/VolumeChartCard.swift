import SwiftUI
import Charts
import SettCore

/// Card 2 — total volume per bucket, last 8 buckets ending now, cyan bars,
/// y-axis in thousands of the display unit. Empty buckets render as zero bars.
struct VolumeChartCard: View {
    let samples: [SetSample]
    let period: Period
    let unit: WeightUnit
    let calendar: Calendar

    private struct VolumePoint: Identifiable {
        let id: Int          // bucket ordinal — unique within one period kind
        let label: String
        let thousands: Double
    }

    private var points: [VolumePoint] {
        ProgressEngine.volumeSeries(samples: samples, period: period, endingAt: .now,
                                    count: 8, calendar: calendar)
            .map { entry in
                VolumePoint(id: entry.bucket.ordinal,
                            label: label(for: entry.bucket),
                            thousands: Double(entry.volumeGrams) / unit.gramsPerUnit / 1000.0)
            }
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Volume")
                    .font(.headline)
                Spacer()
                Text("last 8 \(period.rawValue)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart(points) { point in
                BarMark(x: .value("Period", point.label),
                        y: .value("Volume", point.thousands))
                    .foregroundStyle(SettColor.heroCyan)
                    .cornerRadius(4)
            }
            .chartXScale(domain: points.map(\.label))
            .chartYAxisLabel("×1,000 \(unit.symbol)")
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func label(for bucket: BucketKey) -> String {
        switch bucket.period {
        case .week:
            return "W\(bucket.ordinal % 100)"
        case .month:
            let index = bucket.ordinal % 100 - 1
            let symbols = calendar.shortMonthSymbols
            return symbols.indices.contains(index) ? symbols[index] : "\(bucket.ordinal % 100)"
        case .year:
            return "\(bucket.ordinal)"
        }
    }
}
