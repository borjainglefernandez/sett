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
    /// Display mirror of the catalog `Exercise.instructions` (the machine-setup
    /// field app-wide). Edits go through the shared `MachineSetupSheet`, which
    /// writes the Exercise directly; this mirror keeps the row current.
    var machineSetup: String? = nil
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
    /// The rest value the editor loaded with — lets save() tell an intentional rest
    /// change (apply to all) from an untouched save (preserve each row's own rest).
    @State private var loadedRestSeconds = 90
    @State private var isShowingExercisePicker = false
    /// When set, the picker replaces this draft instead of appending a new one.
    @State private var replacingDraftID: RoutineDraftExercise.ID?
    /// The catalog Exercise whose machine setup is being edited in the shared sheet.
    @State private var setupTarget: Exercise?
    /// The draft that owns `setupTarget`, so its display mirror can refresh on dismiss.
    @State private var setupDraftID: RoutineDraftExercise.ID?
    /// This routine's Time Chamber realm (ChamberBackground.rawValue); nil ⇒ default.
    @State private var domainRaw: String?
    /// This routine's default gym (stamped onto every workout it starts).
    @State private var defaultGymID: UUID?
    @State private var defaultGymName: String?
    @State private var isPickingGym = false
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
                ChamberDomainStrip(selection: $domainRaw, allowsDefault: true, circular: true)
            } header: {
                sectionLabel("REALM")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Section {
                gymControl
            } header: {
                sectionLabel("DEFAULT GYM")
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
            RoutineExercisePickerSheet(allowsMultiple: replacingDraftID == nil) { exercise in
                pick(exercise)
            }
        }
        .sheet(item: $setupTarget, onDismiss: refreshSetupMirror) { exercise in
            MachineSetupSheet(exercise: exercise)
        }
        .sheet(isPresented: $isPickingGym) {
            GymPickerSheet(currentID: defaultGymID) { gym in
                defaultGymID = gym?.id
                defaultGymName = gym?.name
            }
        }
        .onAppear(perform: loadDraftIfNeeded)
    }

    // MARK: Pieces

    private var nameField: some View {
        TextField("", text: $name, prompt: Text("Routine name").foregroundStyle(SettColor.iron))
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(SettColor.bone)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 14)
            .frame(height: 44)
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

    // MARK: Default gym (stamped onto every workout this routine starts)

    private var gymControl: some View {
        Button { isPickingGym = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(SettColor.heroCyan).font(.caption)
                Text(defaultGymName ?? "No default location")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(defaultGymName == nil ? SettColor.ash : SettColor.bone)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .settCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Default gym: \(defaultGymName ?? "not set")")
    }

    // MARK: Default rest (applies to every exercise)

    private var restControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(SettColor.heroCyan).font(.caption)
            Text("Default rest")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SettColor.ash)
            Spacer(minLength: 8)
            stepButton("minus") {
                defaultRestSeconds = max(RestTuning.range.lowerBound, defaultRestSeconds - RestTuning.step); Haptics.selection()
            }
            Text("\(defaultRestSeconds)s")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.bone)
                .monospacedDigit()
                .frame(minWidth: 42)
            stepButton("plus") {
                defaultRestSeconds = min(RestTuning.range.upperBound, defaultRestSeconds + RestTuning.step); Haptics.selection()
            }
        }
        .padding(.vertical, 2)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 30, height: 28)
                .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Exercise row

    private func exerciseRow(_ draft: Binding<RoutineDraftExercise>) -> some View {
        HStack(spacing: 12) {
            ExerciseIcon(name: draft.wrappedValue.name, equipment: draft.wrappedValue.equipment,
                         muscle: Muscle(rawValue: draft.wrappedValue.muscleRaw) ?? .other,
                         size: 40, color: SettColor.heroCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.wrappedValue.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(draft.wrappedValue.equipment.rawValue.capitalized)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettColor.iron)
                setupLine(draft.wrappedValue)
            }
            Spacer(minLength: 6)
            setCountControl(draft)
            let index = drafts.firstIndex { $0.id == draft.wrappedValue.id } ?? 0
            let hasSetup = !(draft.wrappedValue.machineSetup ?? "").isEmpty
            Menu {
                Button {
                    move(fromIndex: index, by: -1)
                } label: { Label("Move up", systemImage: "arrow.up") }
                    .disabled(index == 0)
                Button {
                    move(fromIndex: index, by: 1)
                } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(index >= drafts.count - 1)
                Divider()
                Button {
                    openSetup(for: draft.wrappedValue)
                } label: {
                    Label(hasSetup ? "Edit machine setup" : "Add machine setup",
                          systemImage: "gearshape")
                }
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
                    .frame(width: 26, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Exercise options")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    /// Swap an exercise up or down the list (menu reorder — always available,
    /// no edit mode needed). `by` is −1 (up) or +1 (down).
    private func move(fromIndex index: Int, by offset: Int) {
        let target = index + offset
        guard index >= 0, index < drafts.count, target >= 0, target < drafts.count else { return }
        withAnimation { drafts.swapAt(index, target) }
        Haptics.selection()
    }

    // MARK: Machine setup (Exercise.instructions — what to set the machine to)

    /// At-a-glance setup caption under the name: the saved setup (tappable to
    /// edit) if one exists, a quiet "Add setup" for machines/cables when empty,
    /// hidden for free weights. Mirrors the session card's rule.
    @ViewBuilder
    private func setupLine(_ draft: RoutineDraftExercise) -> some View {
        let setup = draft.machineSetup ?? ""
        if !setup.isEmpty {
            Button { openSetup(for: draft) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill").font(.system(size: 10))
                    Text(setup)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(SettColor.ash)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Machine setup: \(setup)")
            .accessibilityHint("Edits the machine setup")
        } else if draft.equipment == .machine || draft.equipment == .cable {
            Button { openSetup(for: draft) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape").font(.system(size: 10))
                    Text("Add setup")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(SettColor.iron)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add machine setup")
        }
    }

    /// Resolve the catalog Exercise and hand it to the shared setup sheet.
    private func openSetup(for draft: RoutineDraftExercise) {
        guard let exercise = resolveExercise(for: draft) else { return }
        setupDraftID = draft.id
        setupTarget = exercise
    }

    /// The sheet mutated the Exercise in place; pull the fresh setup back into the
    /// draft so the row caption updates without a re-fetch on every body pass.
    private func refreshSetupMirror() {
        defer { setupDraftID = nil }
        guard let id = setupDraftID,
              let idx = drafts.firstIndex(where: { $0.id == id }),
              let exercise = resolveExercise(for: drafts[idx]) else { return }
        drafts[idx].machineSetup = exercise.instructions
    }

    private func setCountControl(_ draft: Binding<RoutineDraftExercise>) -> some View {
        HStack(spacing: 6) {
            stepButton("minus") {
                if draft.wrappedValue.setCount > 1 { draft.wrappedValue.setCount -= 1; Haptics.selection() }
            }
            VStack(spacing: 0) {
                Text("\(draft.wrappedValue.setCount)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                Text(draft.wrappedValue.setCount == 1 ? "SET" : "SETS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.iron)
            }
            .frame(minWidth: 26)
            stepButton("plus") {
                if draft.wrappedValue.setCount < 10 { draft.wrappedValue.setCount += 1; Haptics.selection() }
            }
        }
        .fixedSize()
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
            loadedRestSeconds = defaultRestSeconds
            return
        }
        name = routine.name
        daysOfWeekMask = routine.daysOfWeekMask
        domainRaw = routine.domainRaw
        defaultGymID = routine.defaultGymID
        defaultGymName = routine.defaultGymNameSnapshot
        drafts = routine.orderedExercises.map { re in
            let catalog = catalogExercise(forID: re.exerciseID)
            return RoutineDraftExercise(
                existing: re,
                exerciseID: re.exerciseID,
                name: re.exerciseNameSnapshot,
                muscleRaw: re.muscleRaw,
                equipment: catalog?.equipment ?? .machine,
                setCount: re.plannedSetCount > 0 ? re.plannedSetCount : max(1, re.orderedPlannedSets.count),
                machineSetup: catalog?.instructions
            )
        }
        // Seed the default-rest control from the first override, else the app default.
        defaultRestSeconds = routine.orderedExercises.compactMap(\.restSeconds).first
            ?? services.settings.defaultRestSeconds
        loadedRestSeconds = defaultRestSeconds
    }

    /// Fetch the catalog Exercise behind a loose `exerciseID` (equipment + machine
    /// setup live there). Returns nil if the row references a deleted exercise.
    private func catalogExercise(forID id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Picker callback: replace the flagged draft in place, else append a new one.
    private func pick(_ exercise: Exercise) {
        if let id = replacingDraftID, let idx = drafts.firstIndex(where: { $0.id == id }) {
            drafts[idx].exerciseID = exercise.id
            drafts[idx].name = exercise.name
            drafts[idx].muscleRaw = exercise.muscleRaw
            drafts[idx].equipment = exercise.equipment
            drafts[idx].machineSetup = exercise.instructions
            drafts[idx].pickedExercise = exercise
            Haptics.light()
        } else {
            drafts.append(RoutineDraftExercise(
                pickedExercise: exercise,
                exerciseID: exercise.id,
                name: exercise.name,
                muscleRaw: exercise.muscleRaw,
                equipment: exercise.equipment,
                setCount: 3,
                machineSetup: exercise.instructions
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
            routine.domainRaw = domainRaw
            routine.defaultGymID = defaultGymID
            routine.defaultGymNameSnapshot = defaultGymName
            reconcileExercises(into: routine, now: now)
            routine.updatedAt = now
            routine.needsPush = true
        } else {
            let created = Routine(name: trimmedName, daysOfWeekMask: daysOfWeekMask,
                                  orderIndex: nextOrderIndex(), now: now)
            created.domainRaw = domainRaw
            created.defaultGymID = defaultGymID
            created.defaultGymNameSnapshot = defaultGymName
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
        // Only push the routine default onto existing rows when the user actually
        // CHANGED the rest control — otherwise preserve each exercise's own rest
        // instead of flattening every row to one value on every save.
        let restChanged = defaultRestSeconds != loadedRestSeconds
        for (index, draft) in drafts.enumerated() {
            if let existing = draft.existing {
                var changed = false
                if existing.orderIndex != index { existing.orderIndex = index; changed = true }
                if existing.restSeconds == nil || restChanged, existing.restSeconds != defaultRestSeconds {
                    existing.restSeconds = defaultRestSeconds; changed = true
                }
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
