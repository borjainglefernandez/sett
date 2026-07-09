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
    /// Committed set whose weight/reps are being fixed in `SetValuesEditSheet`.
    @State private var editingValues: SetEntry?
    /// Exercise whose machine setup is being edited in `MachineSetupSheet`.
    @State private var setupTarget: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            machineSetupRow
            if isExpanded {
                VStack(spacing: 6) {
                    // Logged sets (filled), the active next-set input, then every set
                    // still planned as a dimmed placeholder — the whole plan up front.
                    ForEach(setPairs, id: \.set.id) { pair in
                        setRow(set: pair.set, reference: pair.reference, label: pair.label)
                    }
                    SetEntryRow(workoutExercise: workoutExercise, setNumber: workingLoggedCount + 1)
                    ForEach(pendingSlots, id: \.self) { ordinal in
                        plannedRow(number: ordinal + 1, slot: ordinal)
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackground)
        .onAppear {
            if exercise == nil {
                exercise = session.fetchExercise(id: workoutExercise.exerciseID)
            }
        }
        .sheet(item: $editingSet) { set in
            SetNoteSheet(initialText: set.notes ?? "") { saveNote($0, on: set) }
        }
        .sheet(item: $editingValues) { set in
            SetValuesEditSheet(set: set, unit: services.settings.unit) { weight, reps, warm in
                session.editSet(set, weightGrams: weight, reps: reps, isWarmup: warm)
            }
        }
        .sheet(item: $setupTarget) { target in
            MachineSetupSheet(exercise: target)
        }
    }

    private var phase: TrainingPhase { session.activeWorkout?.phase ?? .maintaining }
    private var unit: WeightUnit { services.settings.unit }

    /// Same-exercise sets from the most recent finished workout (warm-ups already
    /// excluded), paired to THIS session's working sets by working-set ordinal so a
    /// warm-up never shifts a set onto the wrong reference.
    private var referenceSets: [SetEntry] {
        session.previousSets(exerciseID: workoutExercise.exerciseID,
                             excluding: workoutExercise.workout?.id)
    }

    /// Each logged set paired with last week's set at the same working-set ordinal,
    /// plus its badge label — the working-set number, or "W" for a warm-up.
    private var setPairs: [(set: SetEntry, reference: SetEntry?, label: String)] {
        let refs = referenceSets
        var working = 0
        return workoutExercise.orderedSets.map { set in
            if set.isWarmup { return (set, nil, "W") }
            let ref = working < refs.count ? refs[working] : nil
            working += 1
            return (set, ref, "\(working)")
        }
    }

    private var workingLoggedCount: Int { workoutExercise.orderedSets.filter { !$0.isWarmup }.count }
    private var plannedWorking: Int { session.plannedSetCount(for: workoutExercise) }

    /// Working-set ordinals STILL planned after the active next-set input (which covers
    /// ordinal `workingLoggedCount`). Empty for a quick-start (no plan) or once the
    /// plan is met — the whole plan is shown from the start, not revealed one at a time.
    private var pendingSlots: [Int] {
        let start = workingLoggedCount + 1
        guard plannedWorking > start else { return [] }
        return Array(start ..< plannedWorking)
    }

    // MARK: Effective output + per-set scoring (matches the scouter's green→amber→red)

    private func e1RM(_ set: SetEntry) -> Int {
        let eff = LoadMath.effectiveWeightGrams(
            addedGrams: set.weightGrams, equipment: workoutExercise.equipment,
            bodyweightGrams: workoutExercise.workout?.bodyweightGrams)
        return ProgressEngine.e1RMGrams(weightGrams: eff, reps: set.reps)
    }
    private func pwr(_ set: SetEntry) -> Int { Int(Units.pounds(fromGrams: e1RM(set)).rounded()) }

    /// This set's outcome tier vs last week — reusing the real classifier so a row's
    /// colour is the SAME green/amber/red the scouter showed when it was logged.
    private func setTier(_ set: SetEntry, reference: SetEntry?) -> AuraTier {
        if set.isWarmup { return .calm }
        guard let reference else { return .base }
        let e = e1RM(set), r = e1RM(reference)
        let preview = SetReadback(weightDeltaGrams: nil, repsDelta: nil, isBaseline: false,
                                  e1RMGrams: e, referenceE1RMGrams: r,
                                  e1RMDeltaGrams: e - r, isPersonalBest: false)
        return LogOutcome.classify(readback: preview, phase: phase,
                                   isWarmup: false, isCasual: false).auraTier
    }

    /// Rank the tiers so the card rim + top-PWR read the exercise's BEST set.
    private static let tierRank: [AuraTier] = [.fatigued, .calm, .base, .defended, .ascended, .radiant]
    private var topTier: AuraTier {
        setPairs.filter { !$0.set.isWarmup }
            .map { setTier($0.set, reference: $0.reference) }
            .max { (Self.tierRank.firstIndex(of: $0) ?? 0) < (Self.tierRank.firstIndex(of: $1) ?? 0) } ?? .base
    }
    private var topPwr: Int {
        workoutExercise.orderedSets.filter { !$0.isWarmup }.map { pwr($0) }.max() ?? 0
    }

    // MARK: Header — scouter language (equipment icon + mono name + top-PWR)

    private var header: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workoutExercise.equipment.symbolName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(topTier.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workoutExercise.exerciseNameSnapshot.uppercased())
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .kerning(1)
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(statLine)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statLine: String {
        let count = workoutExercise.orderedSets.filter { !$0.isWarmup }.count
        let sets = "\(count) SET\(count == 1 ? "" : "S")"
        return topPwr > 0 ? "\(sets) · TOP \(topPwr) PWR" : sets
    }

    /// Void card with a scouter rim + corner reticle, tinted by the best set's tier.
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            shape.fill(TimeChamber.void.opacity(0.72))
            shape.strokeBorder(topTier.color.opacity(0.32), lineWidth: 1)
                .shadow(color: topTier.color.opacity(0.25), radius: 7)
            CornerTicksShape(length: 6, inset: 7)
                .stroke(topTier.color.opacity(0.4), lineWidth: 1)
        }
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

    // MARK: Set row — a scouter reading per logged set

    /// A committed set rendered in the scouter language: a tier-coloured index badge +
    /// a left accent bar, the lift, its PWR, and the vs-last delta (▲/◇/▼). Tap edits
    /// the note; long-press fixes the values or deletes.
    private func setRow(set: SetEntry, reference: SetEntry?, label: String) -> some View {
        let tier = setTier(set, reference: reference)
        let delta = (set.isWarmup || reference == nil) ? nil : pwr(set) - pwr(reference!)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            editingSet = set
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(set.isWarmup ? SettColor.ash : tier.color)
                    .frame(width: 24, height: 24)
                    .background { Circle().strokeBorder(tier.color.opacity(0.5), lineWidth: 1) }
                Text("\(WeightFormat.compactWithUnit(grams: set.weightGrams, unit: unit)) × \(set.reps)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                if set.notes?.isEmpty == false {
                    Image(systemName: "text.alignleft")
                        .font(.caption2)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer(minLength: 6)
                if set.isWarmup {
                    Text("WARM-UP")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                } else {
                    Text("PWR \(pwr(set))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(tier.color.opacity(0.9))
                    if let delta, delta != 0 {
                        Text(deltaLabel(delta))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(deltaColor(delta))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background {
                shape.fill(TimeChamber.void.opacity(0.5))
                HStack {
                    RoundedRectangle(cornerRadius: 2).fill(tier.color).frame(width: 3)
                    Spacer()
                }
                shape.strokeBorder(tier.color.opacity(0.18), lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(label), \(WeightFormat.compactWithUnit(grams: set.weightGrams, unit: unit)) by \(set.reps)")
        .accessibilityHint("Edits this set's note. Long-press to fix weight and reps or delete.")
        .contextMenu {
            Button {
                editingValues = set
            } label: { Label("Fix weight & reps", systemImage: "pencil") }
            Button {
                editingSet = set
            } label: { Label("Edit note", systemImage: "note.text") }
            Button(role: .destructive) {
                session.deleteSet(set)
            } label: { Label("Delete set", systemImage: "trash") }
        }
    }

    /// A still-to-do planned set: a dashed, dimmed placeholder showing the target (the
    /// ghost autofill) so the whole plan is visible from the start. The active input
    /// row above it is where the next set is actually logged.
    private func plannedRow(number: Int, slot: Int) -> some View {
        let ghost = session.ghostValues(for: workoutExercise, slot: slot)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.iron)
                .frame(width: 24, height: 24)
                .background {
                    Circle().strokeBorder(SettColor.iron.opacity(0.6),
                                          style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                }
            Text("\(WeightFormat.compactWithUnit(grams: ghost.weightGrams, unit: unit)) × \(ghost.reps)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.iron)
            Spacer(minLength: 6)
            Text("PLANNED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.iron)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            shape.strokeBorder(SettColor.cardBorder.opacity(0.7),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planned set \(number), target \(WeightFormat.compactWithUnit(grams: ghost.weightGrams, unit: unit)) by \(ghost.reps)")
    }

    /// vs-last PWR delta: ▲ ahead, ▼ behind (◇ on a cut — a dip is not a failure).
    private func deltaLabel(_ d: Int) -> String {
        if d > 0 { return "▲+\(d)" }
        return phase == .cutting ? "◇\(d)" : "▼\(d)"
    }
    private func deltaColor(_ d: Int) -> Color {
        if d > 0 { return SettColor.positive }
        return phase == .cutting ? TimeChamber.teal : SettColor.negative
    }

    /// Mutation rules: updatedAt + needsPush + save on the SetEntry itself.
    private func saveNote(_ note: String?, on set: SetEntry) {
        set.notes = note
        set.updatedAt = .now
        set.needsPush = true
        try? modelContext.save()
        Haptics.selection()
    }

}

// MARK: - Set values edit sheet (fix a mis-logged weight / reps / warm-up)

/// Compact editor for a committed set's numbers — the escape hatch for a
/// fat-fingered entry. Hands the corrected values back through `onSave`; the store
/// applies them under the sync rules.
struct SetValuesEditSheet: View {
    let set: SetEntry
    let unit: WeightUnit
    let onSave: (_ weightGrams: Int, _ reps: Int, _ isWarmup: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var reps = 0
    @State private var isWarmup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FIX SET")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.bone)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEIGHT (\(unit.symbol))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(SettColor.bone)
                        .padding(10)
                        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("REPS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                    Stepper(value: $reps, in: 0...100) {
                        Text("\(reps)")
                            .font(.system(.title3, design: .monospaced))
                            .foregroundStyle(SettColor.bone)
                            .monospacedDigit()
                    }
                }
            }
            Toggle("Warm-up", isOn: $isWarmup)
                .font(.subheadline)
                .tint(TimeChamber.teal)
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
        .presentationDetents([.height(300)])
        .onAppear {
            weightText = WeightFormat.compact(grams: set.weightGrams, unit: unit)
            reps = set.reps
            isWarmup = set.isWarmup
        }
    }

    private func save() {
        let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        onSave(Units.grams(fromDisplay: max(0, value), unit: unit), max(0, reps), isWarmup)
        Haptics.selection()
        dismiss()
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
