import SwiftUI
import Charts
import SettCore

/// Power Level over time — the one number the whole app orbits, finally shown as
/// a trajectory instead of a lone digit. Gold by law (PL is gold's only home),
/// one point per training day, all-time. A dashed line marks the all-time peak
/// when the user is below it (the ground left to reclaim); drag to read the PL
/// on any day.
struct PowerHistoryCard: View {
    let history: [PLPoint]
    let peakPL: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One-time on-appear climb: the line plots flat until this flips.
    @State private var revealed = false
    /// Scrub position (a date on the X axis) — snaps to the nearest day's point.
    @State private var selectedDate: Date?

    var body: some View {
        let points = history
        let scrubbed = nearest(to: selectedDate, in: points)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Power Level")
                Eyebrow("ALL TIME")
                Spacer(minLength: 8)
                if let scrubbed { readout(scrubbed) }
            }
            if points.count >= 2, let current = points.last {
                Text(current.pl.formatted())
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(SettColor.saiyanGold)
                chart(points, current: current, scrubbed: scrubbed)
                if let footnote = footnote(points) {
                    Text(footnote)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.ash)
                }
            } else {
                teaser
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
        .onAppear {
            if reduceMotion { revealed = true }
            else { withAnimation(.snappy) { revealed = true } }
        }
    }

    private func chart(_ points: [PLPoint], current: PLPoint, scrubbed: PLPoint?) -> some View {
        Chart {
            ForEach(points, id: \.date) { point in
                let y = Double(point.pl) * (revealed ? 1 : 0)
                AreaMark(x: .value("Date", point.date),
                         y: .value("Power", y))
                    .foregroundStyle(.linearGradient(
                        colors: [SettColor.saiyanGold.opacity(0.28), SettColor.saiyanGold.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date),
                         y: .value("Power", y))
                    .foregroundStyle(SettColor.saiyanGold)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            // The peak line — only when standing below it, so it reads as "ground
            // to reclaim" and never just underlines the current value.
            if current.pl < peakPL {
                RuleMark(y: .value("Peak", Double(peakPL) * (revealed ? 1 : 0)))
                    .foregroundStyle(SettColor.saiyanGold.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("PEAK \(peakPL.formatted())")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(SettColor.saiyanGold.opacity(0.7))
                    }
            }
            if let scrubbed {
                RuleMark(x: .value("Date", scrubbed.date))
                    .foregroundStyle(SettColor.ash.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Date", scrubbed.date),
                          y: .value("Power", Double(scrubbed.pl) * (revealed ? 1 : 0)))
                    .foregroundStyle(SettColor.saiyanGold)
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: yDomain(points))
        .chartXSelection(value: $selectedDate)
        .frame(height: 150)
        .scouterChart(xCount: 4, yCount: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power level over time")
        .accessibilityValue(accessibilitySummary(points, current: current))
    }

    /// The training day nearest the scrubbed date — snaps the readout + rule to a
    /// real point rather than floating between them. nil when not scrubbing.
    private func nearest(to date: Date?, in points: [PLPoint]) -> PLPoint? {
        guard let date, !points.isEmpty else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    /// The scrubbed day's PL + date, shown beside the title.
    private func readout(_ point: PLPoint) -> some View {
        HStack(spacing: 6) {
            Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                .foregroundStyle(SettColor.ash)
            Text(point.pl.formatted())
                .foregroundStyle(SettColor.saiyanGold)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .transition(.opacity)
    }

    private var teaser: some View {
        Text("Two training days and your power climb charts here.")
            .font(.subheadline)
            .foregroundStyle(SettColor.ash)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }

    private func yDomain(_ points: [PLPoint]) -> ClosedRange<Double> {
        let values = points.map { Double($0.pl) }
        // Include the peak line in the domain so its dashed mark never clips.
        let low = (values.min() ?? 0)
        let high = max(values.max() ?? 1, Double(peakPL))
        let pad = max(50, (high - low) * 0.15)
        return (low - pad)...(high + pad)
    }

    private func footnote(_ points: [PLPoint]) -> String? {
        guard let first = points.first, let last = points.last else { return nil }
        let delta = last.pl - first.pl
        let sign = delta >= 0 ? "+" : "−"
        let since = first.date.formatted(.dateTime.month(.abbreviated).year())
        return "\(sign)\(abs(delta).formatted()) since \(since) · peak \(peakPL.formatted())"
    }

    private func accessibilitySummary(_ points: [PLPoint], current: PLPoint) -> String {
        guard let first = points.first, first.date != current.date else {
            return "\(current.pl) power level"
        }
        let delta = current.pl - first.pl
        let dir = delta > 0 ? "up" : (delta < 0 ? "down" : "flat")
        return "\(current.pl) power level, \(dir) \(abs(delta)) since the first recorded day, peak \(peakPL)."
    }
}
