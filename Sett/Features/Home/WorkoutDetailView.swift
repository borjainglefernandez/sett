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
    @State private var isPickingGym = false

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
        .sheet(isPresented: $isPickingGym) {
            GymPickerSheet(currentID: workout.gymID) { gym in
                session.setGym(gym, for: workout)
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
                        StarRatingRow(halfStars: rating, starSize: 13)
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
            locationRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    /// Location — always shown once set; in edit mode it's a live control (and offers
    /// "Add location" when empty). Mirrors the active session's overview row.
    @ViewBuilder
    private var locationRow: some View {
        if editing {
            Button { isPickingGym = true } label: {
                HStack(spacing: 6) {
                    Label(workout.gymNameSnapshot ?? "Add location",
                          systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(SettColor.heroCyan)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SettColor.iron)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location: \(workout.gymNameSnapshot ?? "not set")")
            .accessibilityHint("Changes this workout's gym")
        } else if let gym = workout.gymNameSnapshot {
            Label(gym, systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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


    // MARK: Exercises — the active session's scouter card, in read-back form.
    // Same icon medallion, mono header, stat line, badge + value grid; the top set
    // wears amber, the rest green, warm-ups ash — history reads like the session did.

    private func exerciseCard(_ workoutExercise: WorkoutExercise) -> some View {
        let topID = topSetID(workoutExercise)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ExerciseIcon(name: workoutExercise.exerciseNameSnapshot,
                             equipment: workoutExercise.equipment,
                             muscle: workoutExercise.muscle,
                             size: 44,
                             color: topID == nil ? SettColor.heroCyan : TimeChamber.scouterAmber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workoutExercise.exerciseNameSnapshot.uppercased())
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(statLine(workoutExercise))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer(minLength: 0)
            }
            ForEach(workoutExercise.orderedSets, id: \.id) { set in
                setRow(set, in: workoutExercise, isTop: set.id == topID)
            }
            if workoutExercise.orderedSets.isEmpty {
                Text("No sets logged")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            if let notes = workoutExercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudCard(tint: topID == nil ? SettColor.heroCyan : TimeChamber.scouterAmber)
    }

    private func setRow(_ set: SetEntry, in workoutExercise: WorkoutExercise,
                        isTop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                SetIndexBadge(label: badgeLabel(set, in: workoutExercise),
                              charge: set.isWarmup ? .warmup : .earned(isTop ? .ascended : .base))
                Spacer().frame(width: SetRowGrid.badgeGap)
                setValueColumns(
                    weightText: WeightFormat.compactWithUnit(grams: set.weightGrams,
                                                             unit: services.settings.unit),
                    repsText: "\(set.reps)",
                    valueColor: editing ? SettColor.heroCyan : SettColor.bone,
                    weight: .semibold)
                Spacer(minLength: 0)
                if !set.isWarmup {
                    Text("PWR \(pwr(set, in: workoutExercise))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(isTop ? TimeChamber.scouterAmber : TimeChamber.scouterGreen)
                }
                if editing {
                    Button(role: .destructive) {
                        session.deleteSet(set)
                        recomputeAfterCorrection()
                    } label: {
                        Image(systemName: "trash")
                            .font(.footnote)
                            .foregroundStyle(SettColor.negative)
                            .frame(width: 40, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete set")
                }
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
            .onTapGesture {
                guard editing else { return }
                editingSet = set
            }
            .accessibilityAddTraits(editing ? [.isButton] : [])
            .accessibilityHint(editing ? "Edits this set's values" : "")
            // Per-set note, indented to the value columns.
            if let setNotes = set.notes, !setNotes.isEmpty {
                Text(setNotes)
                    .font(.caption)
                    .foregroundStyle(SettColor.ash)
                    .padding(.leading, SetRowGrid.badge + SetRowGrid.badgeGap)
            }
        }
        .background {
            if set.isWarmup {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettColor.iron.opacity(0.08))
            }
        }
    }

    // MARK: Per-set scoring (same effective-load PWR the session showed)

    private func pwr(_ set: SetEntry, in workoutExercise: WorkoutExercise) -> Int {
        let eff = LoadMath.effectiveWeightGrams(
            addedGrams: set.weightGrams, equipment: workoutExercise.equipment,
            bodyweightGrams: workout.bodyweightGrams)
        return Int(Units.pounds(fromGrams: ProgressEngine.e1RMGrams(weightGrams: eff,
                                                                    reps: set.reps)).rounded())
    }

    /// The set with the session's best e1RM — wears the amber crown.
    private func topSetID(_ workoutExercise: WorkoutExercise) -> UUID? {
        workoutExercise.orderedSets.filter { !$0.isWarmup }
            .max { pwr($0, in: workoutExercise) < pwr($1, in: workoutExercise) }?.id
    }

    private func statLine(_ workoutExercise: WorkoutExercise) -> String {
        let working = workoutExercise.orderedSets.filter { !$0.isWarmup }
        var parts = ["\(working.count) SET\(working.count == 1 ? "" : "S")"]
        if let top = working.map({ pwr($0, in: workoutExercise) }).max(), top > 0 {
            parts.append("TOP \(top) PWR")
        }
        let volGrams = working.reduce(0) { $0 + $1.weightGrams * $1.reps }
        if volGrams > 0 {
            let vol = Int((Double(volGrams) / services.settings.unit.gramsPerUnit).rounded())
            parts.append("\(vol.formatted()) \(services.settings.unit.symbol.uppercased())")
        }
        return parts.joined(separator: " · ")
    }

    /// Working-set ordinal, "W" for warm-ups — the overview's badge language.
    private func badgeLabel(_ set: SetEntry, in workoutExercise: WorkoutExercise) -> String {
        if set.isWarmup { return "W" }
        var n = 0
        for sibling in workoutExercise.orderedSets where !sibling.isWarmup {
            n += 1
            if sibling.id == set.id { return "\(n)" }
        }
        return "\(n)"
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
                .foregroundStyle(SettColor.etch)
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
