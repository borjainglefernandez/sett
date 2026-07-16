import SwiftUI
import SwiftData
import SettCore

// MARK: - Recent PRs (the gold moments Progress never showed)

/// The last few personal records — each the first time an exercise's e1RM beat
/// everything before it. Derived straight from the sample stream (running best per
/// exercise, chronological), so it needs no new storage. Casual sets count: the model
/// doc is explicit that PRs ignore the off-the-record flag. Hidden entirely until a
/// second data point exists for something (a first-ever session is "NEW", not a PR).
struct PRFeedCard: View {
    @Environment(\.modelContext) private var modelContext
    let samples: [SetSample]
    let exerciseNames: [UUID: String]
    let unit: WeightUnit

    private struct PREvent: Identifiable {
        let id = UUID()
        let exerciseID: UUID
        let workoutID: UUID
        let date: Date
        let e1RMGrams: Int
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
                                         workoutID: sample.workoutID,
                                         date: sample.completedAt,
                                         e1RMGrams: e1RM))
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
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "medal.fill")
                        .font(.subheadline)
                        .foregroundStyle(SettColor.saiyanGold)
                }
                ForEach(events) { event in
                    prRow(event)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settCard()
        }
    }

    /// A PR moment — tap to open the workout it was set in.
    @ViewBuilder
    private func prRow(_ event: PREvent) -> some View {
        NavigationLink {
            if let workout = workout(id: event.workoutID) {
                WorkoutDetailView(workout: workout)
            } else {
                EmptyChamber(title: "Workout unavailable",
                             message: "This session is no longer on record.")
            }
        } label: {
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
                Text("e1RM \(WeightText.formatted(grams: event.e1RMGrams, unit: unit))")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
            }
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the workout this PR was set in")
    }

    /// The finished workout a PR was set in, fetched by its loose id.
    private func workout(id: UUID) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
