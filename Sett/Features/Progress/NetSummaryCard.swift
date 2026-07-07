import SwiftUI
import SettCore

/// Card 1 — strict previous-calendar-bucket net (Flow 3): two `PowerNumeral(.m)`
/// deltas (net reps, net volume in the display unit), green when positive, red
/// when negative, cyan "NEW" when the previous bucket was empty.
struct NetSummaryCard: View {
    let samples: [SetSample]
    let period: Period
    let unit: WeightUnit
    let calendar: Calendar

    private var net: NetSummary {
        ProgressEngine.netSummary(samples: samples, exerciseID: nil, period: period,
                                  containing: .now, calendar: calendar)
    }

    private var vsLabel: String {
        switch period {
        case .week: "vs last week"
        case .month: "vs last month"
        case .year: "vs last year"
        }
    }

    var body: some View {
        let net = net
        let netVolumeDisplay = Int((Double(net.volumeGrams) / unit.gramsPerUnit).rounded())
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Net Progress")
                    .font(.headline)
                Spacer()
                Text(vsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                metric(value: net.reps, caption: "net reps", isNew: net.isNew)
                metric(value: netVolumeDisplay, caption: "net volume (\(unit.symbol))", isNew: net.isNew)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func metric(value: Int, caption: String, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isNew {
                Text("NEW")
                    .font(PowerFont.m())
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
            } else {
                HStack(spacing: 1) {
                    if value > 0 {
                        Text("+")
                            .font(PowerFont.m())
                            .foregroundStyle(color(for: value))
                    }
                    PowerNumeral(value, size: .m, color: color(for: value))
                }
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for value: Int) -> Color {
        value >= 0 ? SettColor.positive : SettColor.negative
    }
}
