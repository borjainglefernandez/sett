import SwiftUI
import SwiftData
import Charts
import SettCore

/// Full-screen e1RM chart for one exercise: drag-to-scrub with a `RuleMark`
/// callout (selection haptic per data point) and a gold `PointMark` on the
/// all-time max — the only gold allowed in charts.
struct ChartDetailView: View {
    let exerciseID: UUID
    let name: String

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @State private var samples: [SetSample] = []
    @State private var selectedDate: Date?

    private var unit: WeightUnit { services.settings.unit }

    private var points: [E1RMChartPoint] {
        ProgressEngine.bestE1RMSeries(samples: samples, exerciseID: exerciseID)
            .map { E1RMChartPoint(date: $0.date, value: Units.displayValue(grams: $0.e1RMGrams, unit: unit)) }
    }

    private var maxPoint: E1RMChartPoint? {
        points.max { $0.value < $1.value }
    }

    /// Nearest series point to the scrub location.
    private func scrubbed(in points: [E1RMChartPoint]) -> E1RMChartPoint? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statsHeader
                chartCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(SettColor.screen)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            samples = SampleExtractor.setSamples(context: modelContext)
        }
        .onChange(of: scrubbed(in: points)?.id) { _, newValue in
            if newValue != nil { Haptics.selection() }
        }
    }

    // MARK: Header stats

    private var statsHeader: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 2) {
                Text(maxPoint.map { WeightText.formatted($0.value, unit: unit) } ?? "—")
                    .font(PowerFont.m())
                    .monospacedDigit()
                    .foregroundStyle(SettColor.saiyanGold)
                Text("all-time best e1RM")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                PowerNumeral(points.count, size: .m, color: .primary)
                Text("sessions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .settCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated 1RM per session")
                .font(.headline)
            if points.isEmpty {
                Text("Never trained. First set sets the baseline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var chart: some View {
        let points = points
        let scrubbedPoint = scrubbed(in: points)
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date),
                         y: .value("e1RM", point.value))
                    .foregroundStyle(SettColor.heroCyan)
                    .interpolationMethod(.monotone)
                    .symbol(.circle)
                    .symbolSize(24)
            }
            if let maxPoint {
                PointMark(x: .value("Date", maxPoint.date),
                          y: .value("e1RM", maxPoint.value))
                    .foregroundStyle(SettColor.saiyanGold)
                    .symbolSize(140)
            }
            if let scrubbedPoint {
                RuleMark(x: .value("Date", scrubbedPoint.date))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(scrubbedPoint)
                    }
                PointMark(x: .value("Date", scrubbedPoint.date),
                          y: .value("e1RM", scrubbedPoint.value))
                    .foregroundStyle(SettColor.heroCyan)
                    .symbolSize(90)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 260)
    }

    private func callout(_ point: E1RMChartPoint) -> some View {
        VStack(spacing: 2) {
            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(WeightText.formatted(point.value, unit: unit))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
