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

    @State private var weightGrams = 0
    @State private var reps = 0
    @State private var isGhost = true
    @State private var editingField: NumericField?

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
        session.logSet(on: workoutExercise, weightGrams: weightGrams, reps: reps)
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
