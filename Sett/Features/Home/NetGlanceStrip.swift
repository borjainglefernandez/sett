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
    @State private var week = WeekTotals()

    /// This ISO week's absolute totals — the "how much" beside the net's "vs last week".
    struct WeekTotals {
        var workouts = 0
        var sets = 0
        var tonnageGrams = 0
    }

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

    private var tonnageDisplay: String {
        WeightFormat.compactTonnage(grams: week.tonnageGrams, unit: services.settings.unit)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Absolute totals — three quiet counters for the week so far.
            HStack(spacing: 0) {
                counter(value: "\(week.workouts)", caption: "SESSIONS")
                counterDivider
                counter(value: "\(week.sets)", caption: "SETS")
                counterDivider
                counter(value: tonnageDisplay, caption: "TONNAGE \(services.settings.unit.symbol.uppercased())")
            }
            .padding(.vertical, 10)

            if week.sets > 0 {
                Rectangle()
                    .fill(SettColor.saiyanGold.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
            }

            // Net vs last week — hidden until the week has work to compare (an all-red
            // "-294 REPS" over three zeros read as punishment for opening the app).
            if week.sets > 0 {
            HStack(spacing: 12) {
                Text("NET VS LAST WEEK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            }
        }
        .frame(maxWidth: .infinity)
        .background(slab)
        .task { reload() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Counters (absolute) & stats (net)

    private func counter(value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
            Text(caption)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity)
    }

    private var counterDivider: some View {
        Rectangle()
            .fill(SettColor.cardBorder.opacity(0.6))
            .frame(width: 1, height: 26)
    }

    private func stat(_ value: Int, suffix: String) -> some View {
        HStack(spacing: 5) {
            if value != 0 {
                Image(systemName: value > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .heavy))
            }
            Text("\(signed(value)) \(suffix)")
        }
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
        // Absolute totals for the current ISO week: working sets only. Casual sessions
        // DO count here (they're real training) — only the net comparison excludes them.
        var totals = WeekTotals()
        if let thisWeek = Self.isoCalendar.dateInterval(of: .weekOfYear, for: .now) {
            let weekSamples = samples.filter { thisWeek.contains($0.completedAt) && !$0.isWarmup }
            totals.workouts = Set(weekSamples.map(\.workoutID)).count
            totals.sets = weekSamples.count
            totals.tonnageGrams = weekSamples.reduce(0) { $0 + $1.weightGrams * $1.reps }
        }
        withAnimation(.snappy) {
            net = summary
            week = totals
        }
    }

    private var accessibilitySummary: String {
        if net.isNew {
            return "Net this week: new territory"
        }
        return "Net this week: \(signed(net.reps)) reps, \(signed(netVolumeDisplay)) \(services.settings.unit.symbol)"
    }
}
