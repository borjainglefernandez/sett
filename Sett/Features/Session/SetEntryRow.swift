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

    /// The values are edited INLINE as text (no modal pad) — the strings are the source
    /// of truth while the row is active; grams/reps are parsed from them.
    @State private var weightText = "0"
    @State private var repsText = "0"
    @State private var isGhost = true
    @FocusState private var focused: NumericField?
    /// Note staged for the NEXT commit — travels into `logSet` with the checkmark.
    @State private var pendingNote: String?
    @State private var isEditingNote = false

    private var weightGrams: Int {
        Units.grams(fromDisplay: Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0,
                    unit: services.settings.unit)
    }
    private var repsValue: Int { max(0, Int(repsText) ?? 0) }
    private func weightString(grams: Int) -> String {
        WeightFormat.compact(grams: grams, unit: services.settings.unit)
    }

    var body: some View {
        HStack(spacing: 0) {
            SetIndexBadge(label: setNumber.map(String.init) ?? "", charge: .active)
                .opacity(setNumber == nil ? 0 : 1)
                .accessibilityHidden(true)
            Spacer().frame(width: SetRowGrid.badgeGap)

            // WEIGHT — a hairline − left of the value, the inline editable field + unit
            // caption right-aligned in the shared cell, a hairline + right of it.
            stepButton("minus", label: "Decrease weight") { stepWeight(-1) }
            HStack(spacing: 3) {
                editField(text: $weightText, field: .weight, align: .trailing, label: "Weight")
                Text(services.settings.unit.symbol)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(SettColor.iron)
            }
            .padding(.trailing, SetRowGrid.valueInset)
            .frame(width: SetRowGrid.weightCell, height: SetRowGrid.rowHeight, alignment: .trailing)
            stepButton("plus", label: "Increase weight") { stepWeight(1) }

            Text("×")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.iron)
                .frame(width: SetRowGrid.times)

            // REPS — a hairline − left, the inline field, a hairline + right.
            stepButton("minus", label: "Decrease reps") { stepReps(-1) }
            editField(text: $repsText, field: .reps, align: .leading, label: "Reps")
                .padding(.leading, SetRowGrid.valueInset)
                .frame(width: SetRowGrid.repsCell, height: SetRowGrid.rowHeight, alignment: .leading)
            stepButton("plus", label: "Increase reps") { stepReps(1) }

            Spacer(minLength: 8)
            noteButton
            commitButton
        }
        .frame(height: SetRowGrid.rowHeight)
        .padding(.horizontal, SetRowGrid.hPad)
        .background(activeBackground)
        .onAppear { autofill() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .font(.headline)
                    .foregroundStyle(SettColor.heroCyan)
            }
        }
    }

    /// The value as an INLINE editable text box — tap to focus, type on the numeric
    /// keypad (decimal for weight, whole for reps), updating the number in place with no
    /// modal pad. `.fixedSize` sizes the field to its content so the cyan underline hugs
    /// the actual number (not the whole cell) and the weight/reps underlines stay
    /// consistent. Ghost pre-fill renders tertiary; focusing flips it to cyan.
    private func editField(text: Binding<String>, field: NumericField,
                           align: TextAlignment, label: String) -> some View {
        TextField("", text: text)
            .keyboardType(field == .weight ? .decimalPad : .numberPad)
            .focused($focused, equals: field)
            .multilineTextAlignment(align)
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(isGhost ? Color(uiColor: .tertiaryLabel) : SettColor.heroCyan)
            .fixedSize()
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused == field ? SettColor.heroCyan : SettColor.heroCyan.opacity(0.45))
                    .frame(height: focused == field ? 1.5 : 1)
                    .offset(y: 5)
            }
            .onChange(of: focused) { _, now in if now == field { isGhost = false } }
            .accessibilityLabel(label)
    }

    // MARK: Stepper — a borderless hairline − / + flanking each value (no chunky box)

    /// One flanking step glyph: a bare cyan − or + (no fill, no border — that chrome was
    /// the "clunk"), floating next to the value like the unit caption. The 14pt layout
    /// column keeps the value cells on their shared x; the 44pt height gives a full-row
    /// hit target. A plain Button (not a drag) so it never competes with the ScrollView
    /// pan; big jumps are one tap on the value to type them.
    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettColor.heroCyan.opacity(0.9))
                .frame(width: SetRowGrid.stepFlank, height: SetRowGrid.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
        let grams = max(0, weightGrams + direction * services.settings.incrementGrams)
        weightText = weightString(grams: grams)
        isGhost = false
        Haptics.selection()
    }

    private func stepReps(_ direction: Int) {
        repsText = "\(max(0, repsValue + direction))"
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
            focused = nil
            commit()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(SettColor.heroCyan, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(repsValue <= 0)
        .accessibilityLabel(setNumber.map { "Log set \($0)" } ?? "Log set")
    }

    /// The reference index for THIS set: the count of non-warmup sets already logged.
    /// previousSets / ghostValues are indexed by WORKING-set ordinal (warm-ups
    /// excluded), so the raw queue count (which counts warm-ups) shifts every working
    /// set onto the wrong reference — wrong ghost autofill + wrong crit. Mirrors
    /// SetPlayerView.workingSlot.
    private var workingSlot: Int {
        workoutExercise.orderedSets.filter { !$0.isWarmup }.count
    }

    private func commit() {
        let grams = weightGrams
        let reps = repsValue
        // Crit when this set's weight beats the reference (ghost) set at the same
        // working-set ordinal — resolved BEFORE logging so the index still points here.
        let index = workingSlot
        let references = session.previousSets(exerciseID: workoutExercise.exerciseID,
                                              excluding: workoutExercise.workout?.id)
        let beatReference = index < references.count && grams > references[index].weightGrams

        session.logSet(on: workoutExercise, weightGrams: grams, reps: reps,
                       notes: pendingNote)
        pendingNote = nil

        // Floating combat text: +N PWR, N = this set's volume load in whole pounds.
        // grams * reps is gram-reps volume; pounds(fromGrams:) converts it to
        // pound-reps. Celebration plays AFTER the write — latency is sacred.
        let volumeLb = Int(Units.pounds(fromGrams: grams * reps).rounded())
        combatText?.emit("+\(volumeLb.formatted()) PWR", crit: beatReference)
        if beatReference { Haptics.prSignature() } // crit haptic is the caller's job

        autofill()
    }

    // MARK: Ghost autofill (shared resolution — WorkoutSessionStore.ghostValues)

    private func autofill() {
        let ghost = session.ghostValues(for: workoutExercise, slot: workingSlot)
        weightText = weightString(grams: ghost.weightGrams)
        repsText = "\(ghost.reps)"
        isGhost = true
    }
}

// MARK: - Set note sheet (shared: pending next-set note + committed-chip edits)

/// Compact note editor. `SetEntryRow` stages the result as the pending note for
/// the next commit; `ExerciseCard` reuses it to edit a committed `SetEntry.notes`
/// directly. Save trims whitespace and passes nil for empty text; Clear is an
/// explicit nil save.
struct SetNoteSheet: View {
    let initialText: String
    var title = "Set Note"
    var placeholder = "felt heavy, left side weaker…"
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    // ONE commit path — the nav-bar Save. It sits above the keyboard so there is no
    // need for a keyboard "Done" (a multi-line editor's Return inserts newlines).
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $text)
                    .font(.subheadline)
                    .foregroundStyle(SettColor.bone)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 150)
                    .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.subheadline)
                                .foregroundStyle(SettColor.ash)
                                .padding(.horizontal, 13)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(role: .destructive) { text = "" } label: {
                        Label("Clear note", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundStyle(SettColor.ash)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                text = initialText
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
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

// MARK: - Numeric pad sheet (Set Player long-press keypad)

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
