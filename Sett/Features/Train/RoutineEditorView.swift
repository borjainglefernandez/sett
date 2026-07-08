import SwiftUI
import SwiftData
import SettCore

// MARK: - Local draft (value type; nothing touches the store until Save)

/// A routine plans an exercise and HOW MANY sets — never target reps/weight.
/// The session ghost-fills from last time's actual performance, so the routine's
/// only job is to line up the work and let progressive overload do the rest.
private struct RoutineDraftExercise: Identifiable {
    let id = UUID()
    /// Set when this draft mirrors a persisted RoutineExercise (editing).
    var existing: RoutineExercise? = nil
    /// Set when the exercise was picked from the library in this session.
    var pickedExercise: Exercise? = nil
    var exerciseID: UUID
    var name: String
    var muscleRaw: String
    var equipment: Equipment
    var setCount: Int = 3
}

// MARK: - Editor

/// Build or edit a routine template. All edits accumulate in local draft values;
/// the Routine and children are created/reconciled ONLY on Save — never on init
/// (the v1 flaw). Editing reconciles in place, bumping updatedAt/needsPush.
struct RoutineEditorView: View {
    let routine: Routine?

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var daysOfWeekMask = 0
    @State private var drafts: [RoutineDraftExercise] = []
    /// One rest value applied to every exercise in the routine (QoL: a default rest).
    @State private var defaultRestSeconds = 90
    @State private var isShowingExercisePicker = false
    /// When set, the picker replaces this draft instead of appending a new one.
    @State private var replacingDraftID: RoutineDraftExercise.ID?
    @State private var hasLoadedDraft = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section {
                nameField
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Section {
                dayChips
                restControl
            } header: {
                sectionLabel("SCHEDULE")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Section {
                ForEach($drafts) { $draft in
                    exerciseRow($draft)
                        .listRowBackground(rowBackground)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { remove(draft) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove { from, to in
                    drafts.move(fromOffsets: from, toOffset: to)
                    Haptics.selection()
                }
                addExerciseButton
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                sectionLabel("EXERCISES")
            } footer: {
                if drafts.isEmpty {
                    Text("Add your first exercise. Swipe a row to delete; tap Reorder to rearrange.")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(SettColor.iron)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .dungeonBackground()
        .environment(\.editMode, $editMode)
        .navigationTitle(routine == nil ? "New Routine" : "Edit Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if drafts.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .sheet(isPresented: $isShowingExercisePicker, onDismiss: { replacingDraftID = nil }) {
            RoutineExercisePickerSheet { exercise in
                pick(exercise)
            }
        }
        .onAppear(perform: loadDraftIfNeeded)
    }

    // MARK: Pieces

    private var nameField: some View {
        TextField("", text: $name, prompt: Text("Routine name").foregroundStyle(SettColor.iron))
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(SettColor.bone)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .settCard()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .kerning(2)
            .foregroundStyle(SettColor.ash)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(SettColor.card)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SettColor.cardBorder, lineWidth: 1)
            }
    }

    // MARK: Scheduled days (Sunday-first display; bit 0 = Monday semantics unchanged)

    private var dayChips: some View {
        HStack(spacing: 6) {
            ForEach(TrainDays.sundayFirstOrder, id: \.self) { day in
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
        .padding(.top, 4)
    }

    // MARK: Default rest (applies to every exercise)

    private var restControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer").foregroundStyle(SettColor.heroCyan).font(.footnote)
            Text("Default rest")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(SettColor.bone)
            Spacer()
            Text("\(defaultRestSeconds)s")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.ash)
                .monospacedDigit()
            stepButton("minus") {
                defaultRestSeconds = max(15, defaultRestSeconds - 15); Haptics.selection()
            }
            stepButton("plus") {
                defaultRestSeconds = min(600, defaultRestSeconds + 15); Haptics.selection()
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .settCard()
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

    // MARK: Exercise row

    private func exerciseRow(_ draft: Binding<RoutineDraftExercise>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: draft.wrappedValue.equipment.symbolName)
                .font(.body)
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.wrappedValue.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(1)
                Text(draft.wrappedValue.equipment.rawValue.capitalized)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettColor.iron)
            }
            Spacer(minLength: 8)
            setCountControl(draft)
            Menu {
                Button {
                    replacingDraftID = draft.wrappedValue.id
                    isShowingExercisePicker = true
                } label: { Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath") }
                Button(role: .destructive) { remove(draft.wrappedValue) } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SettColor.ash)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Exercise options")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func setCountControl(_ draft: Binding<RoutineDraftExercise>) -> some View {
        HStack(spacing: 8) {
            stepButton("minus") {
                if draft.wrappedValue.setCount > 1 { draft.wrappedValue.setCount -= 1; Haptics.selection() }
            }
            VStack(spacing: 0) {
                Text("\(draft.wrappedValue.setCount)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                Text(draft.wrappedValue.setCount == 1 ? "SET" : "SETS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.iron)
            }
            .frame(minWidth: 34)
            stepButton("plus") {
                if draft.wrappedValue.setCount < 10 { draft.wrappedValue.setCount += 1; Haptics.selection() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(draft.wrappedValue.setCount) sets")
    }

    private var addExerciseButton: some View {
        Button {
            replacingDraftID = nil
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

    // MARK: Draft lifecycle

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        guard let routine else {
            defaultRestSeconds = services.settings.defaultRestSeconds
            return
        }
        name = routine.name
        daysOfWeekMask = routine.daysOfWeekMask
        drafts = routine.orderedExercises.map { re in
            RoutineDraftExercise(
                existing: re,
                exerciseID: re.exerciseID,
                name: re.exerciseNameSnapshot,
                muscleRaw: re.muscleRaw,
                equipment: equipment(forExerciseID: re.exerciseID),
                setCount: re.plannedSetCount > 0 ? re.plannedSetCount : max(1, re.orderedPlannedSets.count)
            )
        }
        // Seed the default-rest control from the first override, else the app default.
        defaultRestSeconds = routine.orderedExercises.compactMap(\.restSeconds).first
            ?? services.settings.defaultRestSeconds
    }

    private func equipment(forExerciseID id: UUID) -> Equipment {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.equipment ?? .machine
    }

    /// Picker callback: replace the flagged draft in place, else append a new one.
    private func pick(_ exercise: Exercise) {
        if let id = replacingDraftID, let idx = drafts.firstIndex(where: { $0.id == id }) {
            drafts[idx].exerciseID = exercise.id
            drafts[idx].name = exercise.name
            drafts[idx].muscleRaw = exercise.muscleRaw
            drafts[idx].equipment = exercise.equipment
            drafts[idx].pickedExercise = exercise
            Haptics.light()
        } else {
            drafts.append(RoutineDraftExercise(
                pickedExercise: exercise,
                exerciseID: exercise.id,
                name: exercise.name,
                muscleRaw: exercise.muscleRaw,
                equipment: exercise.equipment,
                setCount: 3
            ))
            Haptics.light()
        }
        replacingDraftID = nil
    }

    private func remove(_ draft: RoutineDraftExercise) {
        drafts.removeAll { $0.id == draft.id }
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

    /// Reconcile drafts against persisted rows: mutate kept rows in place (bumping
    /// updatedAt/needsPush only when something changed), insert new, soft-delete removed.
    /// Every kept/new exercise gets the routine default rest and its draft set count.
    private func reconcileExercises(into routine: Routine, now: Date) {
        let keptIDs = Set(drafts.compactMap { $0.existing?.id })
        for re in routine.orderedExercises where !keptIDs.contains(re.id) {
            re.deletedAt = now
            re.updatedAt = now
            re.needsPush = true
        }
        for (index, draft) in drafts.enumerated() {
            if let existing = draft.existing {
                var changed = false
                if existing.orderIndex != index { existing.orderIndex = index; changed = true }
                if existing.restSeconds != defaultRestSeconds { existing.restSeconds = defaultRestSeconds; changed = true }
                if existing.plannedSetCount != draft.setCount { existing.plannedSetCount = draft.setCount; changed = true }
                if existing.exerciseID != draft.exerciseID {
                    existing.exerciseID = draft.exerciseID
                    existing.exerciseNameSnapshot = draft.name
                    existing.muscleRaw = draft.muscleRaw
                    changed = true
                }
                // Retire any legacy per-set target rows — routines no longer use them.
                for planned in existing.orderedPlannedSets {
                    planned.deletedAt = now; planned.updatedAt = now; planned.needsPush = true
                }
                if changed { existing.updatedAt = now; existing.needsPush = true }
            } else if let exercise = resolveExercise(for: draft) {
                insertRoutineExercise(from: draft, at: index, into: routine,
                                      exercise: exercise, now: now)
            }
        }
    }

    private func insertRoutineExercise(from draft: RoutineDraftExercise, at index: Int,
                                       into routine: Routine, exercise: Exercise, now: Date) {
        let re = RoutineExercise(orderIndex: index, exercise: exercise,
                                 setCount: draft.setCount, now: now)
        re.restSeconds = defaultRestSeconds
        re.routine = routine
        modelContext.insert(re)
    }

    private func resolveExercise(for draft: RoutineDraftExercise) -> Exercise? {
        if let picked = draft.pickedExercise { return picked }
        let id = draft.exerciseID
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func nextOrderIndex() -> Int {
        let descriptor = FetchDescriptor<Routine>()
        let routines = (try? modelContext.fetch(descriptor)) ?? []
        return (routines.map(\.orderIndex).max() ?? -1) + 1
    }
}
