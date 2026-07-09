import SwiftUI
import SwiftData
import SettCore

// MARK: - Net Glance Strip (Home — net reps/volume at a glance)

/// A slim etched slab under the 7-Slot Burst Row: `NET THIS WEEK` on the left,
/// this ISO week's net reps and net volume (vs last week, whole lb) on the
/// right in mono — green when positive, red when negative, ash at zero. When
/// the previous week had no sets the strip reads `NEW TERRITORY` in cyan
/// instead of two meaningless "+everything" deltas. Samples are extracted once
/// per appearance; numbers roll via numeric-text so tenet 3 holds.
struct NetGlanceStrip: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @State private var net = NetSummary(reps: 0, volumeGrams: 0, isNew: false)

    /// Buckets use ISO weeks (Monday start), matching the engines.
    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    /// Net volume in the user's display unit — kg users saw a 2.2× wrong LB number.
    private var netVolumeDisplay: Int {
        Int((Double(net.volumeGrams) / services.settings.unit.gramsPerUnit).rounded())
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("NET THIS WEEK")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.ash)
            Spacer(minLength: 12)
            if net.isNew {
                Text("NEW TERRITORY")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
            } else {
                HStack(spacing: 12) {
                    stat(net.reps, suffix: "REPS")
                    stat(netVolumeDisplay, suffix: services.settings.unit.symbol.uppercased())
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(slab)
        .task { reload() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: One mono stat — signed, grouped, numeric-text rolls

    private func stat(_ value: Int, suffix: String) -> some View {
        Text("\(signed(value)) \(suffix)")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color(for: value))
            .contentTransition(.numericText(value: Double(value)))
    }

    /// "+1,850" / "-42" / "0" — grouped, explicit plus on positives only.
    private func signed(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).sign(strategy: .always(includingZero: false)))
    }

    private func color(for value: Int) -> Color {
        if value > 0 { return SettColor.positive }
        // On a cut a lighter week is expected — never paint it as a loss (tenet:
        // cutting is framed as retention, not penalized). Neutral ash instead of red.
        if value < 0 { return services.settings.phase == .cutting ? SettColor.ash : SettColor.negative }
        return SettColor.ash
    }

    // MARK: The slim slab — settCard's etched groove without its 16pt padding

    private var slab: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return shape
            .fill(SettColor.card)
            .overlay {
                // Outer groove wall — near-black.
                shape.strokeBorder(SettColor.etch, lineWidth: 1)
            }
            .overlay {
                // Inner groove floor — faint gold catching torchlight.
                RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                    .strokeBorder(SettColor.saiyanGold.opacity(0.2), lineWidth: 1)
                    .padding(1.5)
            }
            .overlay {
                CornerTicksShape(length: 5, inset: 4)
                    .stroke(SettColor.saiyanGold.opacity(0.25), lineWidth: 1)
            }
    }

    // MARK: Data (extracted once per appearance, then engine math off the samples)

    private func reload() {
        let samples = SampleExtractor.setSamples(context: modelContext)
        let summary = ProgressEngine.netSummary(
            samples: samples, exerciseID: nil, period: .week,
            containing: .now, calendar: Self.isoCalendar
        )
        withAnimation(.snappy) { net = summary }
    }

    private var accessibilitySummary: String {
        if net.isNew {
            return "Net this week: new territory"
        }
        return "Net this week: \(signed(net.reps)) reps, \(signed(netVolumeDisplay)) \(services.settings.unit.symbol)"
    }
}
