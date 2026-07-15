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
    /// The active training phase — on a cut, a negative net is neutral (retention),
    /// never painted red (tenet: cutting is not penalized).
    var phase: TrainingPhase = .maintaining

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
                    .font(.title3.weight(.semibold))
                Spacer()
                Eyebrow(vsLabel.uppercased())
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

    /// Plain heavy mono — PowerNumeral (and its aura glow) is the power level's
    /// sacred treatment; a weekly net delta doesn't get to wear it.
    @ViewBuilder
    private func metric(value: Int, caption: String, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isNew {
                Text("NEW")
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
            } else {
                HStack(spacing: 3) {
                    if value != 0 {
                        Image(systemName: value > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(color(for: value))
                    }
                    Text("\(value > 0 ? "+" : "")\(value.formatted())")
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(color(for: value))
                        .contentTransition(.numericText(value: Double(value)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
    }

    private func color(for value: Int) -> Color {
        if value >= 0 { return SettColor.positive }
        return phase == .cutting ? SettColor.ash : SettColor.negative
    }
}
