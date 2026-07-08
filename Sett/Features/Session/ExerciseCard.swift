import SwiftUI
import SwiftData
import SettCore

/// One collapsible card per exercise in the active workout: header (muscle icon, name,
/// sets logged), the machine-setup line (visible WHILE training — that's the point),
/// compact confirmed chips for every logged set with a net-vs-reference delta, then a
/// single editable next-set row (`SetEntryRow`).
struct ExerciseCard: View {
    let workoutExercise: WorkoutExercise

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = true
    /// Exercise row behind the loose `exerciseID` — carries the machine setup.
    @State private var exercise: Exercise?
    /// Committed set whose note is being edited in the shared `SetNoteSheet`.
    @State private var editingSet: SetEntry?
    /// Exercise whose machine setup is being edited in `MachineSetupSheet`.
    @State private var setupTarget: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            machineSetupRow
            if isExpanded {
                let logged = workoutExercise.orderedSets
                let references = referenceSets
                if !logged.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(logged.enumerated()), id: \.element.id) { index, set in
                            confirmedChip(set: set,
                                          reference: index < references.count ? references[index] : nil,
                                          number: index + 1)
                        }
                    }
                }
                SetEntryRow(workoutExercise: workoutExercise)
            }
        }
        .settCard()
        .onAppear {
            if exercise == nil {
                exercise = session.fetchExercise(id: workoutExercise.exerciseID)
            }
        }
        .sheet(item: $editingSet) { set in
            SetNoteSheet(initialText: set.notes ?? "") { saveNote($0, on: set) }
        }
        .sheet(item: $setupTarget) { target in
            MachineSetupSheet(exercise: target)
        }
    }

    /// Same-exercise sets from the most recent finished workout, paired by index.
    private var referenceSets: [SetEntry] {
        session.previousSets(exerciseID: workoutExercise.exerciseID,
                             excluding: workoutExercise.workout?.id)
    }

    // MARK: Header

    private var header: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workoutExercise.muscle.sessionSymbolName)
                    .font(.title3)
                    .foregroundStyle(SettColor.heroCyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutExercise.exerciseNameSnapshot)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(setsLoggedLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var setsLoggedLabel: String {
        let count = workoutExercise.orderedSets.count
        return count == 1 ? "1 set logged" : "\(count) sets logged"
    }

    // MARK: Machine setup (Exercise.instructions — what do I set the machine to)

    /// Ash mono caption under the name while a setup exists; a quiet ghost
    /// "Add setup" for machines/cables when empty; hidden for free weights.
    @ViewBuilder
    private var machineSetupRow: some View {
        if let exercise {
            if let setup = exercise.instructions, !setup.isEmpty {
                Button {
                    setupTarget = exercise
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.caption2)
                        Text(setup)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(SettColor.ash)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Machine setup: \(setup)")
                .accessibilityHint("Edits the machine setup")
            } else if exercise.equipment == .machine || exercise.equipment == .cable {
                Button {
                    setupTarget = exercise
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.caption2)
                        Text("Add setup")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(SettColor.iron)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add machine setup")
            }
        }
    }

    // MARK: Confirmed set chips

    /// Tapping a committed chip opens the shared note sheet on that set.
    private func confirmedChip(set: SetEntry, reference: SetEntry?, number: Int) -> some View {
        Button {
            editingSet = set
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SettColor.heroCyan)
                Text("\(number)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("\(services.settings.displayWeight(set.weightGrams)) × \(set.reps)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(chipNumeralColor(set: set, reference: reference))
                if set.notes?.isEmpty == false {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer()
                if let chip = netChip(set: set, reference: reference) {
                    Text(chip.text)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(chip.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits this set's note")
    }

    /// Mutation rules: updatedAt + needsPush + save on the SetEntry itself.
    private func saveNote(_ note: String?, on set: SetEntry) {
        set.notes = note
        set.updatedAt = .now
        set.needsPush = true
        try? modelContext.save()
        Haptics.selection()
    }

    /// Numeral color as data (the FighterZ combo-counter rule): bone on pace,
    /// GOLD when this set beat its reference set's weight (a reward pulse —
    /// one of the few sanctioned gold uses), dim blue for warmups. No extra chips.
    private func chipNumeralColor(set: SetEntry, reference: SetEntry?) -> Color {
        if set.isWarmup { return SettColor.heroCyan.opacity(0.6) }
        if let reference, set.weightGrams > reference.weightGrams {
            return SettColor.saiyanGold
        }
        return SettColor.bone
    }

    private struct NetChip {
        let text: String
        let color: Color
    }

    /// Weight delta first ("+5 lb"); same weight → reps delta ("+2 reps"); identical → no chip.
    /// No reference at this index (fresh territory) → no chip.
    private func netChip(set: SetEntry, reference: SetEntry?) -> NetChip? {
        guard let reference else { return nil }
        let unit = services.settings.unit
        let weightDelta = set.weightGrams - reference.weightGrams
        if weightDelta != 0 {
            let value = Units.displayValue(grams: abs(weightDelta), unit: unit)
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(format: "%.2f", value)
            let sign = weightDelta > 0 ? "+" : "−"
            return NetChip(text: "\(sign)\(formatted) \(unit.symbol)",
                           color: weightDelta > 0 ? SettColor.positive : SettColor.negative)
        }
        let repsDelta = set.reps - reference.reps
        if repsDelta != 0 {
            let sign = repsDelta > 0 ? "+" : "−"
            return NetChip(text: "\(sign)\(abs(repsDelta)) reps",
                           color: repsDelta > 0 ? SettColor.positive : SettColor.negative)
        }
        return nil
    }
}

// MARK: - Machine setup sheet (THE one editor — Session card + Train detail)

/// Compact editor for the machine setup. `Exercise.instructions` IS the
/// machine-setup field app-wide (no schema change); saving mutates it under the
/// standard sync rules (updatedAt + needsPush + save). Save trims whitespace and
/// stores nil for empty text.
struct MachineSetupSheet: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MACHINE SETUP")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.bone)
            TextField("seat 4 · back 3 · pin 8", text: $text)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(SettColor.bone)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(12)
                .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button(action: save) {
                Text("Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Aura.cyan, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(220)])
        .onAppear {
            text = exercise.instructions ?? ""
            isFocused = true
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.instructions = trimmed.isEmpty ? nil : trimmed
        exercise.updatedAt = .now
        exercise.needsPush = true
        try? modelContext.save()
        Haptics.selection()
        dismiss()
    }
}

// MARK: - Muscle icon mapping (Session feature)

extension Muscle {
    var sessionSymbolName: String {
        switch self {
        case .chest: "figure.arms.open"
        case .triceps: "figure.strengthtraining.traditional"
        case .biceps: "figure.strengthtraining.functional"
        case .shoulders: "figure.wave"
        case .back: "figure.rower"
        case .legs: "figure.run"
        case .core: "figure.core.training"
        case .other: "dumbbell.fill"
        }
    }
}
