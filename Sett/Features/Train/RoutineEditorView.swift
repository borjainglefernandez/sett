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
        List {
            Section {
                TextField("Routine name", text: $name)
                    .font(.headline)
            }
            Section("Scheduled days") {
                dayChips
            }
            Section {
                ForEach($drafts) { $draft in
                    DraftExerciseEditor(draft: $draft)
                }
                .onMove { indices, newOffset in
                    drafts.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { offsets in
                    drafts.remove(atOffsets: offsets)
                }
                Button {
                    isShowingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(SettColor.heroCyan)
                }
                .buttonStyle(.borderless)
            } header: {
                HStack {
                    Text("Exercises")
                    Spacer()
                    if drafts.count > 1 {
                        EditButton()
                            .font(.subheadline)
                    }
                }
            } footer: {
                if drafts.isEmpty {
                    Text("Add your first exercise.")
                }
            }
        }
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

    // MARK: Day chips (bit 0 = Monday … bit 6 = Sunday)

    private var dayChips: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { day in
                let isOn = TrainDays.isSet(daysOfWeekMask, day: day)
                Button {
                    daysOfWeekMask ^= (1 << day)
                    Haptics.selection()
                } label: {
                    Text(TrainDays.letters[day])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? SettColor.heroCyan : SettColor.cardNested,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TrainDays.names[day])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
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

    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.name)
                .font(.headline)
            restStepper
            ForEach($draft.sets) { $set in
                PlannedSetEditorRow(set: $set,
                                    number: number(of: set),
                                    suggestedWeightGrams: suggestedWeight(for: set),
                                    onRemove: { remove(set) })
            }
            Button {
                addSet()
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettColor.heroCyan)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    // MARK: Rest seconds (nil = per-user default)

    private var restStepper: some View {
        Stepper {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(SettColor.heroCyan)
                Text(restText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
        } onIncrement: {
            if let current = draft.restSeconds {
                draft.restSeconds = min(600, current + 15)
            } else {
                draft.restSeconds = services.settings.defaultRestSeconds
            }
            Haptics.selection()
        } onDecrement: {
            if let current = draft.restSeconds, current > 15 {
                draft.restSeconds = current - 15
            } else {
                draft.restSeconds = nil
            }
            Haptics.selection()
        }

    }

    private var restText: String {
        draft.restSeconds.map { "\($0) s rest" }
            ?? "Default rest (\(services.settings.defaultRestSeconds) s)"
    }

    // MARK: Sets

    private func number(of set: RoutineDraftSet) -> Int {
        (draft.sets.firstIndex { $0.id == set.id } ?? 0) + 1
    }

    private func remove(_ set: RoutineDraftSet) {
        draft.sets.removeAll { $0.id == set.id }
        Haptics.light()
    }

    private func addSet() {
        let last = draft.sets.last
        draft.sets.append(RoutineDraftSet(targetReps: last?.targetReps ?? 10,
                                          targetWeightGrams: last?.targetWeightGrams))
        Haptics.light()
    }

    /// When "auto" is switched off, seed the stepper with the nearest explicit
    /// weight in this exercise so the user isn't stepping up from zero.
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

// MARK: - One planned set: reps 1–30, weight stepper or "auto"

private struct PlannedSetEditorRow: View {
    @Binding var set: RoutineDraftSet
    let number: Int
    let suggestedWeightGrams: Int
    let onRemove: () -> Void

    @Environment(AppServices.self) private var services

    /// Weight the stepper held before "Auto weight" was switched on, so toggling
    /// auto on and back off round-trips to the same value.
    @State private var lastExplicitWeightGrams: Int?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Set \(number)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(SettColor.negative)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove set \(number)")
            }
            Stepper {
                Text("\(set.targetReps) reps")
                    .font(.subheadline)
                    .monospacedDigit()
            } onIncrement: {
                if set.targetReps < 30 {
                    set.targetReps += 1
                    Haptics.selection()
                }
            } onDecrement: {
                if set.targetReps > 1 {
                    set.targetReps -= 1
                    Haptics.selection()
                }
            }
            Toggle(isOn: autoWeightBinding) {
                Text("Auto weight")
                    .font(.subheadline)
            }
            .tint(SettColor.heroCyan)
            // Auto on ⇒ no weight stepper at all: the weight comes from last
            // time's set at session autofill, so showing a stepper would lie.
            if let grams = set.targetWeightGrams {
                Stepper {
                    Text(WeightFormat.compactWithUnit(grams: grams, unit: services.settings.unit))
                        .font(.subheadline)
                        .monospacedDigit()
                } onIncrement: {
                    set.targetWeightGrams = grams + services.settings.incrementGrams
                    Haptics.selection()
                } onDecrement: {
                    set.targetWeightGrams = max(0, grams - services.settings.incrementGrams)
                    Haptics.selection()
                }
            }
        }
        .padding(12)
        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// On ⇒ targetWeightGrams == nil ("use last time's weight" at session autofill).
    /// Off ⇒ restore the value from before auto was switched on, else the nearest
    /// explicit weight in this exercise, else a 82.5 lb starting point — never 0.
    private var autoWeightBinding: Binding<Bool> {
        Binding(
            get: { set.targetWeightGrams == nil },
            set: { isAuto in
                if isAuto {
                    lastExplicitWeightGrams = set.targetWeightGrams
                    set.targetWeightGrams = nil
                } else {
                    let restored = lastExplicitWeightGrams ?? suggestedWeightGrams
                    set.targetWeightGrams = restored > 0
                        ? restored
                        : Units.grams(fromDisplay: 82.5, unit: .lb)
                }
                Haptics.selection()
            }
        )
    }
}
