import SwiftUI
import SwiftData
import SettCore

// MARK: - Local drafts (value types; nothing touches the store until Save)

private struct RoutineDraftExercise: Identifiable {
    let id = UUID()
    /// Set when this draft mirrors a persisted RoutineExercise (editing).
    var existing: RoutineExercise? = nil
    /// Set when the exercise was picked from the library in this session.
    var pickedExercise: Exercise? = nil
    let exerciseID: UUID
    let name: String
    var restSeconds: Int? = nil
    var sets: [RoutineDraftSet] = []
}

private struct RoutineDraftSet: Identifiable {
    let id = UUID()
    /// Set when this draft mirrors a persisted PlannedSet (editing).
    var existing: PlannedSet? = nil
    var targetReps: Int
    /// nil ⇒ "auto" — use last time's weight (PlannedSet.targetWeightGrams == nil).
    var targetWeightGrams: Int?
}

// MARK: - Editor

/// Build or edit a routine template. All edits accumulate in local draft values;
/// the Routine and its children are created and inserted ONLY when Save is tapped —
/// never on init (the v1 flaw). Editing an existing routine reconciles in place and
/// bumps `updatedAt`/`needsPush` on every touched row.
struct RoutineEditorView: View {
    let routine: Routine?

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var daysOfWeekMask = 0
    @State private var drafts: [RoutineDraftExercise] = []
    @State private var isShowingExercisePicker = false
    @State private var hasLoadedDraft = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                nameField
                daysSection
                exercisesSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .dungeonBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(routine == nil ? "New Routine" : "Edit Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .sheet(isPresented: $isShowingExercisePicker) {
            RoutineExercisePickerSheet { exercise in
                addExercise(exercise)
            }
        }
        .onAppear(perform: loadDraftIfNeeded)
    }

    // MARK: Name

    private var nameField: some View {
        TextField("", text: $name, prompt: Text("Routine name").foregroundStyle(SettColor.iron))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(SettColor.bone)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .settCard()
    }

    // MARK: Scheduled days

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SCHEDULED DAYS")
            dayChips
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .kerning(2)
            .foregroundStyle(SettColor.ash)
    }

    // MARK: Day chips (bit 0 = Monday … bit 6 = Sunday)

    private var dayChips: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { day in
                let isOn = TrainDays.isSet(daysOfWeekMask, day: day)
                Button {
                    daysOfWeekMask ^= (1 << day)
                    Haptics.selection()
                } label: {
                    Text(TrainDays.letters[day])
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? SettColor.heroCyan : SettColor.cardNested,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if !isOn {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(SettColor.cardBorder, lineWidth: 1)
                            }
                        }
                        .foregroundStyle(isOn ? Color.black : SettColor.ash)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TrainDays.names[day])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    // MARK: Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("EXERCISES")
            if drafts.isEmpty {
                Text("Add your first exercise.")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(SettColor.iron)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }
            ForEach($drafts) { $draft in
                let idx = drafts.firstIndex { $0.id == draft.id } ?? 0
                DraftExerciseEditor(
                    draft: $draft,
                    canMoveUp: idx > 0,
                    canMoveDown: idx < drafts.count - 1,
                    onMoveUp: { move(from: idx, to: idx - 1) },
                    onMoveDown: { move(from: idx, to: idx + 1) },
                    onDelete: { drafts.removeAll { $0.id == draft.id }; Haptics.light() }
                )
            }
            Button {
                isShowingExercisePicker = true
            } label: {
                Label("Add Exercise", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(SettColor.heroCyan)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(SettColor.heroCyan.opacity(0.4),
                                          style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func move(from: Int, to: Int) {
        guard to >= 0, to < drafts.count else { return }
        drafts.swapAt(from, to)
        Haptics.selection()
    }

    // MARK: Draft lifecycle

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        guard let routine else { return }
        name = routine.name
        daysOfWeekMask = routine.daysOfWeekMask
        drafts = routine.orderedExercises.map { routineExercise in
            RoutineDraftExercise(
                existing: routineExercise,
                exerciseID: routineExercise.exerciseID,
                name: routineExercise.exerciseNameSnapshot,
                restSeconds: routineExercise.restSeconds,
                sets: routineExercise.orderedPlannedSets.map { plannedSet in
                    RoutineDraftSet(existing: plannedSet,
                                    targetReps: plannedSet.targetReps,
                                    targetWeightGrams: plannedSet.targetWeightGrams)
                }
            )
        }
    }

    private func addExercise(_ exercise: Exercise) {
        drafts.append(RoutineDraftExercise(
            pickedExercise: exercise,
            exerciseID: exercise.id,
            name: exercise.name,
            sets: [RoutineDraftSet(targetReps: 10, targetWeightGrams: nil),
                   RoutineDraftSet(targetReps: 10, targetWeightGrams: nil),
                   RoutineDraftSet(targetReps: 10, targetWeightGrams: nil)]
        ))
        Haptics.light()
    }

    // MARK: Save (the ONLY place the store is written)

    private func save() {
        let now = Date.now
        if let routine {
            routine.name = trimmedName
            routine.daysOfWeekMask = daysOfWeekMask
            reconcileExercises(into: routine, now: now)
            routine.updatedAt = now
            routine.needsPush = true
        } else {
            let created = Routine(name: trimmedName, daysOfWeekMask: daysOfWeekMask,
                                  orderIndex: nextOrderIndex(), now: now)
            modelContext.insert(created)
            for (index, draft) in drafts.enumerated() {
                guard let exercise = resolveExercise(for: draft) else { continue }
                insertRoutineExercise(from: draft, at: index, into: created,
                                      exercise: exercise, now: now)
            }
        }
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    /// Reconcile the drafts against the persisted rows: mutate kept rows in place
    /// (bumping updatedAt/needsPush only when something changed), insert new ones,
    /// soft-delete removed ones.
    private func reconcileExercises(into routine: Routine, now: Date) {
        let keptIDs = Set(drafts.compactMap { $0.existing?.id })
        for routineExercise in routine.orderedExercises where !keptIDs.contains(routineExercise.id) {
            routineExercise.deletedAt = now
            routineExercise.updatedAt = now
            routineExercise.needsPush = true
            for plannedSet in routineExercise.plannedSets where plannedSet.deletedAt == nil {
                plannedSet.deletedAt = now
                plannedSet.updatedAt = now
                plannedSet.needsPush = true
            }
        }
        for (index, draft) in drafts.enumerated() {
            if let existing = draft.existing {
                var changed = false
                if existing.orderIndex != index {
                    existing.orderIndex = index
                    changed = true
                }
                if existing.restSeconds != draft.restSeconds {
                    existing.restSeconds = draft.restSeconds
                    changed = true
                }
                reconcileSets(draft.sets, into: existing, now: now)
                if changed {
                    existing.updatedAt = now
                    existing.needsPush = true
                }
            } else if let exercise = resolveExercise(for: draft) {
                insertRoutineExercise(from: draft, at: index, into: routine,
                                      exercise: exercise, now: now)
            }
        }
    }

    private func reconcileSets(_ draftSets: [RoutineDraftSet],
                               into routineExercise: RoutineExercise, now: Date) {
        let keptIDs = Set(draftSets.compactMap { $0.existing?.id })
        for plannedSet in routineExercise.orderedPlannedSets where !keptIDs.contains(plannedSet.id) {
            plannedSet.deletedAt = now
            plannedSet.updatedAt = now
            plannedSet.needsPush = true
        }
        for (index, draft) in draftSets.enumerated() {
            if let existing = draft.existing {
                var changed = false
                if existing.orderIndex != index {
                    existing.orderIndex = index
                    changed = true
                }
                if existing.targetReps != draft.targetReps {
                    existing.targetReps = draft.targetReps
                    changed = true
                }
                if existing.targetWeightGrams != draft.targetWeightGrams {
                    existing.targetWeightGrams = draft.targetWeightGrams
                    changed = true
                }
                if changed {
                    existing.updatedAt = now
                    existing.needsPush = true
                }
            } else {
                let planned = PlannedSet(orderIndex: index, targetReps: draft.targetReps,
                                         targetWeightGrams: draft.targetWeightGrams, now: now)
                planned.routineExercise = routineExercise
                modelContext.insert(planned)
            }
        }
    }

    private func insertRoutineExercise(from draft: RoutineDraftExercise, at index: Int,
                                       into routine: Routine, exercise: Exercise, now: Date) {
        let routineExercise = RoutineExercise(orderIndex: index, exercise: exercise, now: now)
        routineExercise.restSeconds = draft.restSeconds
        routineExercise.routine = routine
        modelContext.insert(routineExercise)
        for (setIndex, draftSet) in draft.sets.enumerated() {
            let planned = PlannedSet(orderIndex: setIndex, targetReps: draftSet.targetReps,
                                     targetWeightGrams: draftSet.targetWeightGrams, now: now)
            planned.routineExercise = routineExercise
            modelContext.insert(planned)
        }
    }

    private func resolveExercise(for draft: RoutineDraftExercise) -> Exercise? {
        if let picked = draft.pickedExercise { return picked }
        let id = draft.exerciseID
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func nextOrderIndex() -> Int {
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate { $0.deletedAt == nil })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        return (existing.map(\.orderIndex).max() ?? -1) + 1
    }
}

// MARK: - Per-exercise editor (name, rest stepper, planned sets)

private struct DraftExerciseEditor: View {
    @Binding var draft: RoutineDraftExercise
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            restRow
            // Compact set table: one tight row per set.
            VStack(spacing: 6) {
                columnHeader
                ForEach($draft.sets) { $set in
                    PlannedSetEditorRow(set: $set,
                                        number: number(of: set),
                                        suggestedWeightGrams: suggestedWeight(for: set),
                                        canRemove: draft.sets.count > 1,
                                        onRemove: { remove(set) })
                }
            }
            HStack(spacing: 16) {
                Button(action: addSet) {
                    Label("Add Set", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.heroCyan)
                }
                .buttonStyle(.plain)
                if draft.sets.count > 1 {
                    Button(action: applyFirstToAll) {
                        Label("Match all", systemImage: "equal")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SettColor.ash)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Set every set to the first set's reps and weight")
                }
            }
            .padding(.top, 2)
        }
        .settCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(draft.name)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(SettColor.bone)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button { onMoveUp() } label: { Label("Move up", systemImage: "arrow.up") }
                    .disabled(!canMoveUp)
                Button { onMoveDown() } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(!canMoveDown)
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Remove exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SettColor.ash)
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Exercise options")
        }
    }

    // MARK: Rest (nil = per-user default) — compact −/+ capsule

    private var restRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer").foregroundStyle(SettColor.heroCyan).font(.footnote)
            Text(restText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(SettColor.ash)
                .monospacedDigit()
            Spacer(minLength: 8)
            stepButton("minus") {
                if let current = draft.restSeconds, current > 15 {
                    draft.restSeconds = current - 15
                } else { draft.restSeconds = nil }
                Haptics.selection()
            }
            stepButton("plus") {
                if let current = draft.restSeconds {
                    draft.restSeconds = min(600, current + 15)
                } else { draft.restSeconds = services.settings.defaultRestSeconds }
                Haptics.selection()
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 34, height: 30)
                .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var restText: String {
        draft.restSeconds.map { "\($0)s rest" }
            ?? "Default rest · \(services.settings.defaultRestSeconds)s"
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("SET").frame(width: 40, alignment: .leading)
            Text("REPS").frame(maxWidth: .infinity, alignment: .center)
            Text("WEIGHT").frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: 28) // remove-button gutter
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .kerning(1)
        .foregroundStyle(SettColor.iron)
        .padding(.horizontal, 4)
    }

    // MARK: Sets

    private func number(of set: RoutineDraftSet) -> Int {
        (draft.sets.firstIndex { $0.id == set.id } ?? 0) + 1
    }

    private func remove(_ set: RoutineDraftSet) {
        guard draft.sets.count > 1 else { return }
        draft.sets.removeAll { $0.id == set.id }
        Haptics.light()
    }

    private func addSet() {
        let last = draft.sets.last
        draft.sets.append(RoutineDraftSet(targetReps: last?.targetReps ?? 10,
                                          targetWeightGrams: last?.targetWeightGrams))
        Haptics.light()
    }

    /// Copy the first set's reps + weight (incl. auto) onto every set — the common
    /// case where all working sets share one scheme.
    private func applyFirstToAll() {
        guard let first = draft.sets.first else { return }
        for index in draft.sets.indices {
            draft.sets[index].targetReps = first.targetReps
            draft.sets[index].targetWeightGrams = first.targetWeightGrams
        }
        Haptics.success()
    }

    /// When "auto" is switched off, seed with the nearest explicit weight in this
    /// exercise so the user isn't typing up from zero.
    private func suggestedWeight(for set: RoutineDraftSet) -> Int {
        guard let index = draft.sets.firstIndex(where: { $0.id == set.id }) else { return 0 }
        for candidate in draft.sets[..<index].reversed() {
            if let grams = candidate.targetWeightGrams { return grams }
        }
        for candidate in draft.sets[index...] {
            if let grams = candidate.targetWeightGrams { return grams }
        }
        return 0
    }
}

// MARK: - One planned set: a single tight row — SET n · [reps] × [weight/AUTO]

private struct PlannedSetEditorRow: View {
    @Binding var set: RoutineDraftSet
    let number: Int
    let suggestedWeightGrams: Int
    let canRemove: Bool
    let onRemove: () -> Void

    @Environment(AppServices.self) private var services

    @State private var editing: EditField?
    /// Weight held before "auto" was switched on, so toggling round-trips.
    @State private var lastExplicitWeightGrams: Int?

    private enum EditField: String, Identifiable { case reps, weight; var id: String { rawValue } }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(SettColor.iron)
                .frame(width: 40, alignment: .leading)

            // Reps — tap to type
            Button { editing = .reps } label: {
                Text("\(set.targetReps)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Weight — tap to type, or AUTO chip
            Button { toggleAutoOrEdit() } label: {
                Group {
                    if let grams = set.targetWeightGrams {
                        Text(WeightFormat.compact(grams: grams, unit: services.settings.unit))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.bone)
                    } else {
                        Text("AUTO")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(SettColor.heroCyan)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.targetWeightGrams == nil
                ? "Weight auto, uses last time"
                : "Weight \(WeightFormat.compactWithUnit(grams: set.targetWeightGrams ?? 0, unit: services.settings.unit))")

            // Remove
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(canRemove ? SettColor.iron : .clear)
                    .frame(width: 28, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .accessibilityLabel("Remove set \(number)")
        }
        .padding(.horizontal, 4)
        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            Button { setAuto() } label: { Label("Auto weight (use last time)", systemImage: "wand.and.stars") }
        }
        .sheet(item: $editing) { field in
            switch field {
            case .reps:
                NumericPadSheet(title: "Reps", initialText: "\(set.targetReps)", keyboard: .numberPad) { text in
                    if let v = Int(text.filter(\.isNumber)), v >= 1 { set.targetReps = min(v, 30) }
                }
            case .weight:
                NumericPadSheet(title: "Weight (\(services.settings.unit.symbol))",
                                initialText: weightFieldText, keyboard: .decimalPad) { text in
                    if let value = Double(text), value >= 0 {
                        set.targetWeightGrams = Units.grams(fromDisplay: value, unit: services.settings.unit)
                    }
                }
            }
        }
    }

    private var weightFieldText: String {
        let grams = set.targetWeightGrams ?? (lastExplicitWeightGrams ?? suggestedWeightGrams)
        return WeightFormat.compact(grams: grams, unit: services.settings.unit)
    }

    /// Tapping the weight cell: if AUTO, switch to an explicit value and open the pad;
    /// otherwise just edit the value. (The context menu re-enables AUTO.)
    private func toggleAutoOrEdit() {
        if set.targetWeightGrams == nil {
            let restored = lastExplicitWeightGrams ?? suggestedWeightGrams
            set.targetWeightGrams = restored > 0 ? restored : Units.grams(fromDisplay: 82.5, unit: .lb)
        }
        editing = .weight
    }

    /// targetWeightGrams == nil ⇒ "use last time's weight" at session autofill.
    private func setAuto() {
        lastExplicitWeightGrams = set.targetWeightGrams
        set.targetWeightGrams = nil
        Haptics.selection()
    }
}
