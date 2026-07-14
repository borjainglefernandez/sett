import SwiftUI
import SettCore

// MARK: - Recent PRs (the gold moments Progress never showed)

/// The last few personal records — each the first time an exercise's e1RM beat
/// everything before it. Derived straight from the sample stream (running best per
/// exercise, chronological), so it needs no new storage. Casual sets count: the model
/// doc is explicit that PRs ignore the off-the-record flag. Hidden entirely until a
/// second data point exists for something (a first-ever session is "NEW", not a PR).
struct PRFeedCard: View {
    let samples: [SetSample]
    let exerciseNames: [UUID: String]
    let unit: WeightUnit

    private struct PREvent: Identifiable {
        let id = UUID()
        let exerciseID: UUID
        let date: Date
        let pwr: Int
    }

    /// Newest-first PR moments, capped at 5. A PR = strictly beating the exercise's
    /// prior best e1RM; the very first sample of an exercise sets the baseline and is
    /// NOT an event (everything would be a "PR" on day one otherwise).
    private var events: [PREvent] {
        var best: [UUID: Int] = [:]
        var found: [PREvent] = []
        for sample in samples.filter({ !$0.isWarmup }).sorted(by: { $0.completedAt < $1.completedAt }) {
            let e1RM = ProgressEngine.e1RMGrams(weightGrams: sample.weightGrams, reps: sample.reps)
            if let prior = best[sample.exerciseID] {
                if e1RM > prior {
                    best[sample.exerciseID] = e1RM
                    found.append(PREvent(exerciseID: sample.exerciseID,
                                         date: sample.completedAt,
                                         pwr: Int(Units.pounds(fromGrams: e1RM).rounded())))
                }
            } else {
                best[sample.exerciseID] = e1RM
            }
        }
        return Array(found.suffix(5).reversed())
    }

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent PRs")
                        .font(.title3.bold())
                    Spacer()
                    Image(systemName: "medal.fill")
                        .font(.subheadline)
                        .foregroundStyle(SettColor.saiyanGold)
                }
                ForEach(events) { event in
                    HStack(spacing: 10) {
                        Image(systemName: "medal.fill")
                            .font(.caption)
                            .foregroundStyle(SettColor.saiyanGold)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exerciseNames[event.exerciseID] ?? "Unknown exercise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SettColor.bone)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(SettColor.ash)
                        }
                        Spacer(minLength: 8)
                        Text("PWR \(event.pwr)")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.saiyanGold)
                    }
                    .frame(minHeight: 34)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settCard()
            .accessibilityElement(children: .combine)
        }
    }
}
