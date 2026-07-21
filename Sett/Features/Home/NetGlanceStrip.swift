import SwiftUI
import SwiftData
import SettCore

// MARK: - Net Glance Strip (the week card's lower half — net reps/volume)

/// The lower half of the merged THIS WEEK card: three quiet counters
/// (SESSIONS / SETS / TONNAGE) then, below a divider, this ISO week's net reps
/// and net volume vs last week in mono — green when positive, red when negative,
/// ash at zero. When the previous week had no sets it reads `NEW TERRITORY` in
/// cyan instead of two meaningless "+everything" deltas.
///
/// The whole block self-suppresses on a ZERO week (`week.sets == 0`): a slab of
/// `0 SESSIONS / 0 SETS / 0 TONNAGE` under seven empty rings is dead weight, so
/// the counters vanish alongside the net row that already hid. It carries its own
/// leading divider so it reads as one seam under the day slots. No card of its
/// own — the SevenSlotBurstRow wraps both halves in a single settCard. Samples
/// are extracted once per appearance; numbers roll via numeric-text so tenet 3 holds.
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

    /// The count-up target: this week's tonnage as a whole number of display units.
    private var tonnageDisplayValue: Int {
        Int((Double(week.tonnageGrams) / services.settings.unit.gramsPerUnit).rounded())
    }

    /// Mirrors `WeightFormat.compactTonnage` on the display-unit integer the roll
    /// counts through (compactTonnage takes grams — the count-up counts display
    /// units): exact until 10k, then "12.4k".
    private func compactTonnage(_ display: Int) -> String {
        display >= 10_000
            ? "\((Double(display) / 1000).formatted(.number.precision(.fractionLength(1))))k"
            : display.formatted()
    }

    var body: some View {
        // The whole net block hangs on `week.sets > 0`. On a zero week nothing
        // renders — no counters, no net, no divider — so the merged card ends on
        // seven empty rings instead of a slab of zeros. The counters still count
        // UP: when the block first mounts (post-reload) they appear at 0 and
        // CountUpNumber's onAppear rolls each to its total.
        Group {
            if week.sets > 0 {
                VStack(spacing: 0) {
                    // The seam under the day slots — this block is the same card's lower half.
                    Rectangle()
                        .fill(SettColor.cardBorder.opacity(0.6))
                        .frame(height: 1)
                        .padding(.bottom, 2)

                    // Absolute totals — three quiet counters for the week so far.
                    HStack(spacing: 0) {
                        counter(value: week.workouts, caption: "SESSIONS")
                        counterDivider
                        counter(value: week.sets, caption: "SETS")
                        counterDivider
                        counter(value: tonnageDisplayValue, format: compactTonnage,
                                caption: "TONNAGE \(services.settings.unit.symbol.uppercased())")
                    }
                    .padding(.vertical, 10)

                    Rectangle()
                        .fill(SettColor.cardBorder.opacity(0.6))
                        .frame(height: 1)
                        .padding(.horizontal, 12)

                    // Net vs last week — an all-red "-294 REPS" over three zeros read as
                    // punishment for opening the app, so it only shows with work to compare.
                    HStack(spacing: 12) {
                        Eyebrow("NET VS LAST WEEK")
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
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
            }
        }
        .task { reload() }
    }

    // MARK: Counters (absolute) & stats (net)

    /// Each stat COUNTS UP from 0 on appear via the shared idiom: `week` lands as
    /// zero, then reload() fills it, so CountUpNumber's onChange rolls 0→total. RM
    /// is handled inside CountUpNumber (it direct-sets the final value).
    private func counter(value: Int, format: @escaping (Int) -> String = { $0.formatted() },
                         caption: String) -> some View {
        VStack(spacing: 2) {
            CountUpNumber(value: value, from: 0,
                          font: .system(size: 17, weight: .heavy, design: .monospaced),
                          color: SettColor.bone,
                          format: format)
            Text(caption)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(0.5)
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

    // MARK: Data (extracted once per appearance, then engine math off the samples)

    private func reload() {
        let samples = SampleExtractor.setSamples(context: modelContext)
        // Like-for-like proration, NOT strict ProgressEngine.netSummary: a partial
        // current week compared against a full prior week reads structurally red
        // mid-week and punishes the lifter for opening the app after three sessions.
        let summary = ProgressEngine.netToDate(samples: samples, exerciseID: nil,
                                               period: .week, asOf: .now,
                                               calendar: Self.isoCalendar)
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
        let unit = services.settings.unit.symbol
        let totals = "\(week.workouts) sessions, \(week.sets) sets, \(tonnageDisplay) \(unit) this week"
        guard week.sets > 0 else { return totals }
        if net.isNew {
            return "\(totals). Net vs last week: new territory"
        }
        return "\(totals). Net vs last week: \(signed(net.reps)) reps, \(signed(netVolumeDisplay)) \(unit)"
    }
}
