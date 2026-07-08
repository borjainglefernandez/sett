import SwiftUI
import SwiftData
import SettCore

/// The critical control (Flow 1 step 3): a ≥60 pt row `[− weight +] [− reps +] [✓]`.
///
/// Ghost autofill: values pre-populate from the reference set at the next index
/// (most recent finished workout with this exercise), else the last set logged this
/// session, else the routine's planned target, and render tertiary until the user
/// edits. Tapping ✓ commits the ghost values as-is — a repeat set is one tap.
struct SetEntryRow: View {
    let workoutExercise: WorkoutExercise

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    /// Injected by ActiveWorkoutView (`.environment(combatText)`); optional so the
    /// row still works if presented outside an active-session context.
    @Environment(CombatTextEmitter.self) private var combatText: CombatTextEmitter?

    @State private var weightGrams = 0
    @State private var reps = 0
    @State private var isGhost = true
    @State private var editingField: NumericField?
    /// Note staged for the NEXT commit — travels into `logSet` with the checkmark.
    @State private var pendingNote: String?
    @State private var isEditingNote = false

    var body: some View {
        HStack(spacing: 8) {
            stepperCluster(valueText: weightValueText,
                           caption: services.settings.unit.symbol,
                           decrement: { stepWeight(-1) },
                           increment: { stepWeight(1) },
                           tapValue: { editingField = .weight })
            stepperCluster(valueText: "\(reps)",
                           caption: "reps",
                           decrement: { stepReps(-1) },
                           increment: { stepReps(1) },
                           tapValue: { editingField = .reps })
            noteButton
            commitButton
        }
        .frame(minHeight: 60)
        .onAppear { autofill() }
        .sheet(item: $editingField) { field in
            numericPad(for: field)
        }
    }

    // MARK: Stepper clusters

    private func stepperCluster(valueText: String, caption: String,
                                decrement: @escaping () -> Void,
                                increment: @escaping () -> Void,
                                tapValue: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", action: decrement)
            Button(action: tapValue) {
                VStack(spacing: 0) {
                    Text(valueText)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isGhost ? Color(uiColor: .tertiaryLabel) : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            stepButton("plus", action: increment)
        }
        .frame(maxWidth: .infinity)
        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func stepWeight(_ direction: Int) {
        weightGrams = max(0, weightGrams + direction * services.settings.incrementGrams)
        isGhost = false
        Haptics.selection()
    }

    private func stepReps(_ direction: Int) {
        reps = max(0, reps + direction)
        isGhost = false
        Haptics.selection()
    }

    // MARK: Note (quiet — a whisper next to the checkmark)

    private var hasPendingNote: Bool {
        pendingNote?.isEmpty == false
    }

    private var noteButton: some View {
        Button {
            isEditingNote = true
        } label: {
            Image(systemName: "note.text")
                .font(.body.weight(.semibold))
                .foregroundStyle(hasPendingNote ? SettColor.heroCyan : SettColor.ash)
                .frame(width: 36, height: 52)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if hasPendingNote {
                        Circle()
                            .fill(SettColor.heroCyan)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasPendingNote ? "Edit set note" : "Add set note")
        .sheet(isPresented: $isEditingNote) {
            SetNoteSheet(initialText: pendingNote ?? "") { pendingNote = $0 }
        }
    }

    // MARK: Commit (tenet: one tap of the checkmark)

    private var commitButton: some View {
        Button {
            commit()
        } label: {
            Image(systemName: "checkmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(SettColor.heroCyan, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(reps <= 0)
        .accessibilityLabel("Log set")
    }

    private func commit() {
        // Crit when this set's weight beats the reference (ghost) set at the same
        // index — resolved BEFORE logging so the index still points at this set.
        let index = workoutExercise.orderedSets.count
        let references = session.previousSets(exerciseID: workoutExercise.exerciseID,
                                              excluding: workoutExercise.workout?.id)
        let beatReference = index < references.count && weightGrams > references[index].weightGrams

        session.logSet(on: workoutExercise, weightGrams: weightGrams, reps: reps,
                       notes: pendingNote)
        pendingNote = nil

        // Floating combat text: +N PWR, N = this set's volume load in whole pounds.
        // weightGrams * reps is gram-reps volume; pounds(fromGrams:) converts it
        // to pound-reps. Celebration plays AFTER the write — latency is sacred.
        let volumeLb = Int(Units.pounds(fromGrams: weightGrams * reps).rounded())
        combatText?.emit("+\(volumeLb.formatted()) PWR", crit: beatReference)
        if beatReference { Haptics.prSignature() } // crit haptic is the caller's job

        autofill()
    }

    // MARK: Ghost autofill

    private func autofill() {
        let nextIndex = workoutExercise.orderedSets.count
        let references = session.previousSets(exerciseID: workoutExercise.exerciseID,
                                              excluding: workoutExercise.workout?.id)
        if nextIndex < references.count {
            weightGrams = references[nextIndex].weightGrams
            reps = references[nextIndex].reps
        } else if let last = workoutExercise.orderedSets.last {
            weightGrams = last.weightGrams
            reps = last.reps
        } else if let reference = references.last {
            weightGrams = reference.weightGrams
            reps = reference.reps
        } else if let planned = plannedTarget(at: nextIndex) {
            weightGrams = planned.weightGrams
            reps = planned.reps
        } else {
            weightGrams = 0
            reps = 10
        }
        isGhost = true
    }

    /// When the workout came from a routine and there is no history, fall back to the
    /// routine's PlannedSet target: fetch the Routine by `workout.routineID`, match the
    /// RoutineExercise by exerciseID (orderIndex as fallback), take the planned set at
    /// this index (or its last one).
    private func plannedTarget(at index: Int) -> (weightGrams: Int, reps: Int)? {
        guard let workout = workoutExercise.workout,
              let routineID = workout.routineID else { return nil }
        var descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == routineID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        guard let routine = (try? modelContext.fetch(descriptor))?.first else { return nil }

        let exerciseID = workoutExercise.exerciseID
        let orderIndex = workoutExercise.orderIndex
        let routineExercise = routine.orderedExercises.first { $0.exerciseID == exerciseID }
            ?? routine.orderedExercises.first { $0.orderIndex == orderIndex }
        guard let routineExercise else { return nil }

        let planned = routineExercise.orderedPlannedSets
        guard !planned.isEmpty else { return nil }
        let target = index < planned.count ? planned[index] : planned[planned.count - 1]
        return (target.targetWeightGrams ?? 0, target.targetReps)
    }

    // MARK: Numeric pad sheet

    private var weightValueText: String {
        let value = Units.displayValue(grams: weightGrams, unit: services.settings.unit)
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }

    private func numericPad(for field: NumericField) -> some View {
        let unit = services.settings.unit
        switch field {
        case .weight:
            return NumericPadSheet(
                title: "Weight (\(unit.symbol))",
                initialText: weightValueText,
                keyboard: .decimalPad
            ) { text in
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                      value >= 0 else { return }
                weightGrams = Units.grams(fromDisplay: value, unit: unit)
                isGhost = false
            }
        case .reps:
            return NumericPadSheet(
                title: "Reps",
                initialText: "\(reps)",
                keyboard: .numberPad
            ) { text in
                guard let value = Int(text), value >= 0 else { return }
                reps = value
                isGhost = false
            }
        }
    }
}

// MARK: - Set note sheet (shared: pending next-set note + committed-chip edits)

/// Compact note editor. `SetEntryRow` stages the result as the pending note for
/// the next commit; `ExerciseCard` reuses it to edit a committed `SetEntry.notes`
/// directly. Save trims whitespace and passes nil for empty text; Clear is an
/// explicit nil save.
struct SetNoteSheet: View {
    let initialText: String
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SET NOTE")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.bone)
            TextField("felt heavy, left side weaker…", text: $text)
                .font(.subheadline)
                .foregroundStyle(SettColor.bone)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(12)
                .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 12) {
                Button {
                    onSave(nil)
                    dismiss()
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SettColor.ash)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(SettColor.cardNested, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: save) {
                    Text("Save")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Aura.cyan, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(220)])
        .onAppear {
            text = initialText
            isFocused = true
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}

// MARK: - Numeric field being edited

enum NumericField: String, Identifiable {
    case weight, reps
    var id: String { rawValue }
}

// MARK: - Numeric pad sheet

private struct NumericPadSheet: View {
    let title: String
    let initialText: String
    let keyboard: UIKeyboardType
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextField(title, text: $text)
                .keyboardType(keyboard)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .padding(16)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onCommit(text)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onAppear {
                    text = initialText
                    isFocused = true
                }
        }
        .presentationDetents([.height(220)])
    }
}
