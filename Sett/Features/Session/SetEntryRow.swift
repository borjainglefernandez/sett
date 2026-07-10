import SwiftUI
import SettCore

/// The critical control (Flow 1 step 3): a ≥60 pt row `[− weight +] [− reps +] [✓]`.
/// Lives in the overview sheet since v3.1 — the Set Player is the primary logger.
///
/// Ghost autofill: values pre-populate via `WorkoutSessionStore.ghostValues` (the ONE
/// resolution shared with the Set Player) and render tertiary until the user edits.
/// Tapping ✓ commits the ghost values as-is — a repeat set is one tap.
struct SetEntryRow: View {
    let workoutExercise: WorkoutExercise
    /// Optional leading badge — the working-set number this active input represents,
    /// so the overview reads as one numbered checklist alongside the planned rows.
    var setNumber: Int? = nil

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    /// Injected by the presenting view (`.environment(combatText)`); optional so the
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
        HStack(spacing: 0) {
            Text(setNumber.map(String.init) ?? "")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: SetRowGrid.badge, height: SetRowGrid.badge)
                .background { Circle().strokeBorder(SettColor.heroCyan.opacity(0.6), lineWidth: 1) }
                .opacity(setNumber == nil ? 0 : 1)
                .accessibilityHidden(true)
            Spacer().frame(width: SetRowGrid.badgeGap)

            // WEIGHT — shared right-aligned cell, tap → keypad; a hairline ± in the gutter.
            valueButton(text: valueText(weightValueText, unit: services.settings.unit.symbol),
                        width: SetRowGrid.weightCell, align: .trailing) { editingField = .weight }
            compactStepper(dec: { stepWeight(-1) }, inc: { stepWeight(1) })

            Text("×")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.iron)
                .frame(width: SetRowGrid.times)

            // REPS — shared left-aligned cell.
            valueButton(text: "\(reps)", width: SetRowGrid.repsCell, align: .leading) { editingField = .reps }
            compactStepper(dec: { stepReps(-1) }, inc: { stepReps(1) })

            Spacer(minLength: 8)
            noteButton
            commitButton
        }
        .frame(height: SetRowGrid.rowHeight)
        .padding(.horizontal, SetRowGrid.hPad)
        .background(activeBackground)
        .onAppear { autofill() }
        .sheet(item: $editingField) { field in
            numericPad(for: field)
        }
    }

    private func valueText(_ value: String, unit: String) -> String { "\(value)\u{2009}\(unit)" }

    /// The value as the primary editable target — the whole 44 pt-tall cell taps to the
    /// keypad. Ghost pre-fill renders tertiary; an edit flips it to cyan.
    private func valueButton(text: String, width: CGFloat, align: Alignment,
                             tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isGhost ? Color(uiColor: .tertiaryLabel) : SettColor.heroCyan)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: width, height: SetRowGrid.rowHeight, alignment: align)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sleek picker — a borderless hairline vertical ± in the reserved gutter

    private func compactStepper(dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            stepGlyph("plus", action: inc)     // + on top (up = increase)
            Rectangle().fill(SettColor.heroCyan.opacity(0.25)).frame(height: 1)
            stepGlyph("minus", action: dec)    // − on bottom
        }
        .frame(width: SetRowGrid.stepperGutter)
        .background(TimeChamber.void.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1)
        }
        .accessibilityHidden(true)   // the value cell is the accessible keypad edit path
    }

    private func stepGlyph(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: SetRowGrid.stepperGutter, height: 19)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The active row wears the logged rows' void card + a solid cyan accent bar so it
    /// reads as one item in the same list — illuminated and editable, not a control strip.
    private var activeBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            shape.fill(TimeChamber.void.opacity(0.5))
            HStack { RoundedRectangle(cornerRadius: 2).fill(SettColor.heroCyan).frame(width: 3); Spacer() }
            shape.strokeBorder(SettColor.heroCyan.opacity(0.35), lineWidth: 1)
        }
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
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if hasPendingNote {
                        Circle()
                            .fill(SettColor.heroCyan)
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: 8)
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
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
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

    // MARK: Ghost autofill (shared resolution — WorkoutSessionStore.ghostValues)

    private func autofill() {
        let ghost = session.ghostValues(for: workoutExercise,
                                        slot: workoutExercise.orderedSets.count)
        weightGrams = ghost.weightGrams
        reps = ghost.reps
        isGhost = true
    }

    // MARK: Numeric pad sheet

    private var weightValueText: String {
        let value = Units.displayValue(grams: weightGrams, unit: services.settings.unit)
        // Compact: "62.5" / "140", never "62.50" — the stepper column is narrow.
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
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
    var title = "SET NOTE"
    var placeholder = "felt heavy, left side weaker…"
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.bone)
            TextField(placeholder, text: $text)
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

// MARK: - Numeric pad sheet (shared: SetEntryRow taps + Set Player long-press)

struct NumericPadSheet: View {
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
