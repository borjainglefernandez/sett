import SwiftUI
import SwiftData
import SettCore

/// Review one finished workout (design-ux §2): stats header, every set as
/// logged, notes, and "Repeat workout" — a fresh session with the same
/// exercises, presented by the root fullScreenCover.
struct WorkoutDetailView: View {
    let workout: Workout

    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    /// Committed set being corrected in the shared value editor.
    @State private var editingSet: SetEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                ForEach(workout.orderedExercises) { workoutExercise in
                    exerciseCard(workoutExercise)
                }
                if let notes = workout.notes, !notes.isEmpty {
                    notesCard(notes)
                }
                if !editing { repeatButton }
            }
            .padding(16)
        }
        .dungeonBackground()
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                    .fontWeight(editing ? .semibold : .regular)
            }
        }
        .sheet(item: $editingSet) { set in
            SetValuesEditSheet(set: set, unit: services.settings.unit) { weight, reps, warm in
                session.editSet(set, weightGrams: weight, reps: reps, isWarmup: warm)
                recomputeAfterCorrection()
            }
        }
    }

    /// A finished-workout correction should move the power level now, not on some later
    /// recompute — a mis-logged set poisoned PWR, so fixing it must un-poison it.
    private func recomputeAfterCorrection() {
        services.progression.recompute(context: modelContext)
    }

    // MARK: Header (duration / rating / bodyweight / gym)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(workout.startedAt.formatted(date: .complete, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                stat(WorkoutFormat.duration(workout.durationSeconds), caption: "duration")
                if let rating = workout.ratingHalfStars, rating > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ratingStars(halfStars: rating)
                        Text("rating")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let bodyweight = workout.bodyweightGrams {
                    stat(WeightFormat.compactWithUnit(grams: bodyweight,
                                                      unit: services.settings.unit),
                         caption: "bodyweight")
                }
            }
            if let gym = workout.gymNameSnapshot {
                Label(gym, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private func stat(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Cyan, not gold: the rating is user-entered metadata (an input), matching
    /// the summary screen's cyan star control — gold stays reserved for rewards.
    private func ratingStars(halfStars: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: starSymbol(halfStars: halfStars, star: star))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(SettColor.heroCyan)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", Double(halfStars) / 2)) stars")
    }

    private func starSymbol(halfStars: Int, star: Int) -> String {
        if halfStars >= star * 2 {
            "star.fill"
        } else if halfStars == star * 2 - 1 {
            "star.leadinghalf.filled"
        } else {
            "star"
        }
    }

    // MARK: Exercises

    private func exerciseCard(_ workoutExercise: WorkoutExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workoutExercise.exerciseNameSnapshot)
                .font(.headline)
            ForEach(Array(workoutExercise.orderedSets.enumerated()), id: \.element.id) { index, set in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, alignment: .leading)
                        if editing {
                            // Tap the values to fix a mis-log; trash to delete the set.
                            Button { editingSet = set } label: {
                                HStack(spacing: 8) {
                                    Text("\(WeightFormat.compactWithUnit(grams: set.weightGrams, unit: services.settings.unit)) × \(set.reps)")
                                        .font(.subheadline).monospacedDigit()
                                        .foregroundStyle(SettColor.heroCyan)
                                    Image(systemName: "pencil")
                                        .font(.caption2).foregroundStyle(SettColor.ash)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit set \(index + 1)")
                        } else {
                            Text("\(WeightFormat.compactWithUnit(grams: set.weightGrams, unit: services.settings.unit)) × \(set.reps)")
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        if set.isWarmup {
                            Text("warm-up")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SettColor.cardNested, in: Capsule())
                        }
                        Spacer()
                        if editing {
                            Button(role: .destructive) {
                                session.deleteSet(set)
                                recomputeAfterCorrection()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.footnote)
                                    .foregroundStyle(SettColor.negative)
                                    .frame(width: 44, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete set \(index + 1)")
                        }
                    }
                    // Per-set note, indented to the weight × reps column.
                    if let setNotes = set.notes, !setNotes.isEmpty {
                        Text(setNotes)
                            .font(.caption)
                            .foregroundStyle(SettColor.ash)
                            .padding(.leading, 32)
                    }
                }
            }
            if workoutExercise.orderedSets.isEmpty {
                Text("No sets logged")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            if let notes = workoutExercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: Notes

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            Text(notes)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: Repeat

    private var repeatButton: some View {
        Button {
            repeatWorkout()
        } label: {
            Label("Repeat workout", systemImage: "repeat")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Aura.cyan, in: Capsule())
        }
        .padding(.top, 4)
    }

    private func repeatWorkout() {
        session.quickStart(title: workout.title)
        for exerciseID in distinctExerciseIDs {
            guard let exercise = fetchExercise(id: exerciseID) else { continue }
            session.addExercise(exercise)
        }
        dismiss()
    }

    /// Exercise IDs in workout order, deduplicated.
    private var distinctExerciseIDs: [UUID] {
        var seen = Set<UUID>()
        return workout.orderedExercises.compactMap {
            seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil
        }
    }

    private func fetchExercise(id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let exercise = (try? modelContext.fetch(descriptor))?.first,
              exercise.deletedAt == nil else { return nil }
        return exercise
    }
}
