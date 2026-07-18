import SwiftUI
import Charts
import SettCore

/// Card 4 — Sleep × Lifts (Oura): scatter of last night's sleep score against
/// each finished workout's session volume (display unit), with an inline
/// least-squares fit line. Teaser copy until ten paired points exist.
struct SleepImpactCard: View {
    let setSamples: [SetSample]
    let workoutSamples: [WorkoutSample]
    let sleepDays: [SleepDay]
    let unit: WeightUnit
    let calendar: Calendar

    private struct PairedPoint: Identifiable {
        let id: UUID          // workout id
        let sleepScore: Int
        let volume: Double
    }

    /// Each finished workout paired with the sleep score of its morning
    /// (`dateKey` of the workout's start day — the night that ended then).
    private var points: [PairedPoint] {
        var volumeByWorkout: [UUID: Int] = [:]
        for sample in setSamples where !sample.isWarmup {
            volumeByWorkout[sample.workoutID, default: 0] += sample.weightGrams * sample.reps
        }
        var scoreByDateKey: [Int: Int] = [:]
        for day in sleepDays {
            if let score = day.sleepScore { scoreByDateKey[day.dateKey] = score }
        }
        return workoutSamples.compactMap { workout in
            guard let score = scoreByDateKey[calendar.dateKey(for: workout.startedAt)],
                  let volumeGrams = volumeByWorkout[workout.id], volumeGrams > 0
            else { return nil }
            return PairedPoint(id: workout.id, sleepScore: score,
                               volume: Double(volumeGrams) / unit.gramsPerUnit)
        }
    }

    /// Least-squares fit y = slope·x + intercept, returned as its two endpoints.
    private func fitLine(for points: [PairedPoint]) -> [(x: Double, y: Double)]? {
        let n = Double(points.count)
        guard n >= 2 else { return nil }
        let xs = points.map { Double($0.sleepScore) }
        let ys = points.map(\.volume)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 0.0001 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n
        guard let minX = xs.min(), let maxX = xs.max(), minX < maxX else { return nil }
        return [(x: minX, y: slope * minX + intercept),
                (x: maxX, y: slope * maxX + intercept)]
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Sleep × Lifts", icon: "bed.double.fill")
            if points.count >= 10 {
                chart(points: points)
                Text("Each dot is a workout: last night's sleep score against session volume.")
                    .font(.caption)
                    .foregroundStyle(SettColor.ash)
            } else {
                teaser(pairedCount: points.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func teaser(pairedCount: Int) -> some View {
        Text(sleepDays.isEmpty
             ? "Connect Oura in Settings to see how sleep moves your lifts."
             : "\(pairedCount) of 10 paired nights logged — the correlation chart unlocks at 10.")
            .font(.subheadline)
            .foregroundStyle(SettColor.ash)
    }

    private func chart(points: [PairedPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                PointMark(x: .value("Sleep score", Double(point.sleepScore)),
                          y: .value("Volume", point.volume))
                    .foregroundStyle(SettColor.heroCyan.opacity(0.65))
                    .symbolSize(46)
            }
            if let fit = fitLine(for: points) {
                ForEach(Array(fit.enumerated()), id: \.offset) { entry in
                    LineMark(x: .value("Sleep score", entry.element.x),
                             y: .value("Volume", entry.element.y))
                        .foregroundStyle(SettColor.ash.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
        }
        .chartXScale(domain: .automatic(includesZero: false))
        .chartXAxisLabel("sleep score")
        .chartYAxisLabel(unit.symbol)
        // Was shipping Charts' stock axis chrome — bring it into the chamber voice.
        .scouterChart(xCount: 4, yCount: 4)
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep versus lifts")
        .accessibilityValue(accessibilitySummary(for: points))
    }

    /// A spoken summary of the scatter so VoiceOver isn't handed an empty chart.
    private func accessibilitySummary(for points: [PairedPoint]) -> String {
        let trend: String
        if let fit = fitLine(for: points) {
            trend = fit[1].y > fit[0].y ? "trending up"
                  : fit[1].y < fit[0].y ? "trending down" : "flat"
        } else {
            trend = "no clear trend"
        }
        return "\(points.count) workouts plotted, \(trend) with sleep score."
    }
}
