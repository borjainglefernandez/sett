import SwiftUI
import SettCore

// MARK: - Weekly volume vs. the hypertrophy landmarks (the prescriptive lens)

/// This ISO week's hard-set count per muscle group, laid against the evidence-based
/// weekly landmarks from SettCore's `VolumeLandmarks` (floor = least volume that
/// grows, sweet spot = best return per set, ceiling = the recovery line). It leads
/// the Volume section because it answers the question the descriptive tonnage
/// charts can't: "is this enough — and is it too much?".
///
/// Zone ink is deliberately non-toxic: under the floor is quiet ash (a light week
/// is never shamed), the sweet spot is the only green, and PAST the ceiling stays
/// bone with a small ash "recovery" eyebrow — guidance, never alarm. No red
/// appears anywhere on this card.
struct VolumeLandmarksCard: View {
    let samples: [SetSample]
    let calendar: Calendar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One-time on-appear grow: bars render at zero width until this flips.
    @State private var revealed = false
    @State private var showingExplainer = false

    // MARK: Rows

    private struct GroupRow: Identifiable {
        let muscle: Muscle
        let sets: Int
        let landmarks: VolumeLandmarks?
        var id: Muscle { muscle }
    }

    /// Where a week's count sits relative to the landmarks. Naming follows the
    /// non-toxic read: nothing below the floor is a "failure" state.
    private enum Zone {
        case rest        // zero sets — row stays visible but dimmed, a quiet gap
        case belowFloor  // some work, under the growth floor — ash, never shamed
        case building    // floor…sweet spot: a growing dose
        case sweet       // the growth zone — the card's only green
        case tapering    // sweet spot…ceiling: fine, returns thinning
        case pastCeiling // beyond the recovery ceiling — bone + ash eyebrow, no red
        case unmapped    // no landmarks (.other, legacy .legs strays)
    }

    /// The ten landmark groups in `volumeGroups` order (fixed, prescriptive — this
    /// card never re-sorts by count), plus any landmark-less stray that actually
    /// holds sets this week (.other, un-migrated legacy .legs): hiding logged work
    /// would undercut the card's honesty, but at zero sets those rows just vanish.
    private var rows: [GroupRow] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        var counts: [Muscle: Int] = [:]
        for sample in samples where !sample.isWarmup && week.contains(sample.completedAt) {
            counts[sample.muscle, default: 0] += 1
        }
        var rows = Muscle.volumeGroups.map {
            GroupRow(muscle: $0, sets: counts[$0] ?? 0,
                     landmarks: VolumeLandmarks.landmarks(for: $0))
        }
        for muscle in Muscle.allCases where VolumeLandmarks.landmarks(for: muscle) == nil {
            if let sets = counts[muscle], sets > 0 {
                rows.append(GroupRow(muscle: muscle, sets: sets, landmarks: nil))
            }
        }
        return rows
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Weekly volume")
                HStack(spacing: 5) {
                    Eyebrow("HARD SETS · WK")
                    // (i) → the landmarks manual, discoverable right where the
                    // bands raise the question.
                    Button { showingExplainer = true } label: {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(SettColor.ash)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What the volume landmarks mean")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    groupRow(row, index: index)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(rows))
            Text(footerText(rows))
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
        .onAppear { revealed = true }   // bar .animation drives the stagger; RM = direct
        .sheet(isPresented: $showingExplainer) {
            VolumeLandmarksExplainer()
        }
    }

    // MARK: One group row — mono chip · banded track · mono count

    private func groupRow(_ row: GroupRow, index: Int) -> some View {
        let zone = zone(for: row)
        return VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 10) {
                Text(row.muscle.shortLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
                    .frame(width: 76, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                track(row, index: index)
                    .frame(height: 10)
                Text("\(row.sets)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(countInk(zone))
                    .frame(width: 26, alignment: .trailing)
            }
            if zone == .pastCeiling {
                // Recovery guidance in the quiet register — ash eyebrow, no alarm.
                Text("PAST RECOVERY CEILING")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
            }
        }
        // Zero-set groups the user has landmarks for stay on the card at reduced
        // opacity: the gap is visible, but quiet — never a red flag.
        .opacity(zone == .rest ? 0.45 : 1)
        .frame(minHeight: 16)
    }

    /// The banded track: cardNested base, an iron floor→ceiling band (structure,
    /// not signal), the sweet spot as the only green — a FILL, so green never
    /// claims the user's number unless the count itself lands inside — and the
    /// week's bar in ki cyan riding thinner over the bands.
    private func track(_ row: GroupRow, index: Int) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let domain = domainMax(row)
            ZStack(alignment: .leading) {
                Capsule().fill(SettColor.cardNested)
                if let marks = row.landmarks {
                    band(from: marks.floor, to: marks.ceiling, domain: domain,
                         width: width, color: SettColor.iron.opacity(0.22))
                    band(from: marks.sweetLow, to: marks.sweetHigh, domain: domain,
                         width: width, color: SettColor.positive.opacity(0.18))
                }
                Capsule()
                    .fill(SettColor.heroCyan.opacity(0.9))
                    .frame(width: max(row.sets > 0 ? 3 : 0,
                                      width * CGFloat(Double(row.sets) / domain))
                                * (revealed ? 1 : 0),
                           height: 4)
                    // ~40 ms per-row stagger so the card sweeps top-down; RM = no animation.
                    .animation(reduceMotion ? nil : Animation.snappy.delay(Double(index) * 0.04),
                               value: revealed)
            }
        }
    }

    private func band(from lo: Int, to hi: Int, domain: Double,
                      width: CGFloat, color: Color) -> some View {
        let x0 = width * CGFloat(Double(lo) / domain)
        let x1 = width * CGFloat(Double(hi) / domain)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: max(x1 - x0, 2))
            .offset(x: x0)
    }

    /// Track domain: 12% headroom past the ceiling so an over-ceiling bar visibly
    /// ESCAPES the band instead of clamping flush at the edge; an extreme week
    /// stretches the domain (the band compresses, the story stays legible).
    /// Landmark-less strays get a nominal 20-set domain for proportionality.
    private func domainMax(_ row: GroupRow) -> Double {
        let anchor = row.landmarks.map { max($0.ceiling, row.sets) } ?? max(row.sets, 20)
        return Double(anchor) * 1.12
    }

    // MARK: Zone semantics (law-safe, non-toxic)

    private func zone(for row: GroupRow) -> Zone {
        guard let marks = row.landmarks else { return .unmapped }
        if row.sets == 0 { return .rest }
        if row.sets < marks.floor { return .belowFloor }
        if row.sets < marks.sweetLow { return .building }
        if row.sets <= marks.sweetHigh { return .sweet }
        if row.sets <= marks.ceiling { return .tapering }
        return .pastCeiling
    }

    private func countInk(_ zone: Zone) -> Color {
        switch zone {
        case .rest, .belowFloor: SettColor.ash        // quiet — under-volume is never shamed
        case .sweet: SettColor.positive               // the growth zone earns the green
        case .building, .tapering: SettColor.bone
        case .pastCeiling: SettColor.bone             // bone + the ash eyebrow; NO red
        case .unmapped: SettColor.bone
        }
    }

    // MARK: Footer + VoiceOver

    /// "6 of 10 groups in the growth zone" — the denominator is every landmark
    /// group, not just the trained ones, so the summary carries the gaps too.
    private func footerText(_ rows: [GroupRow]) -> String {
        let inZone = rows.filter { zone(for: $0) == .sweet }.count
        return "\(inZone) of \(Muscle.volumeGroups.count) groups in the growth zone"
    }

    /// Spoken summary — the banded bars expose nothing to VoiceOver on their own.
    private func accessibilitySummary(_ rows: [GroupRow]) -> String {
        let active = rows.filter { $0.sets > 0 }
        guard !active.isEmpty else {
            return "Weekly hard sets: none logged yet this week"
        }
        let parts = active.map { row in
            "\(row.muscle.displayName) \(row.sets)\(zonePhrase(zone(for: row)))"
        }
        return "Weekly hard sets: " + parts.joined(separator: ", ")
            + ". \(footerText(rows))."
    }

    private func zonePhrase(_ zone: Zone) -> String {
        switch zone {
        case .sweet: ", in the growth zone"
        case .belowFloor: ", under the growth floor"
        case .pastCeiling: ", past the recovery ceiling"
        default: ""
        }
    }
}

// MARK: - The landmarks manual (info sheet)

/// Floor / sweet spot / ceiling in sentence-case chamber voice. The whole-week
/// numbers read from SettCore's `VolumeLandmarks` constants so the prose can't
/// drift from the bands it explains (the HowPowerWorks rule).
private struct VolumeLandmarksExplainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Reading the bands", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                        .foregroundStyle(SettColor.bone)
                    bullet("""
                        A hard set is any working set — warmups don't count. \
                        The week runs Monday to Sunday.
                        """)
                    bullet("""
                        The floor is the least weekly volume that reliably grows \
                        a muscle. Under it isn't failure — holding what you've \
                        built costs surprisingly little.
                        """)
                    bullet("""
                        The green band is the sweet spot — the range where most \
                        lifters get the best return per set.
                        """)
                    bullet("""
                        The ceiling is the recovery line. Past it, extra sets \
                        mostly add fatigue, not growth — pulling back is the \
                        productive move.
                        """)
                    bullet("""
                        Across all groups, most lifters land between \
                        \(VolumeLandmarks.weeklyTotalRange.lowerBound) and \
                        \(VolumeLandmarks.weeklyTotalRange.upperBound) total hard \
                        sets a week, and about \(VolumeLandmarks.perSessionMax) per \
                        muscle in a single session is the useful max.
                        """)
                    footnote("""
                        Ranges from the hypertrophy literature — Schoenfeld, \
                        Baz-Valle, RP landmarks.
                        """)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settCard()
                .padding(16)
            }
            .dungeonBackground()
            .navigationTitle("Volume landmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·")
                .font(.headline)
                .foregroundStyle(SettColor.heroCyan)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SettColor.bone)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(SettColor.ash)
    }
}
