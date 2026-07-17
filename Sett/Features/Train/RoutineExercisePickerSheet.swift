import SwiftUI
import SwiftData
import SettCore

/// The routine editor's own searchable exercise picker. It hands the chosen
/// exercise back through a closure and dismisses — it never touches the store
/// (drafts persist only when the editor's Save runs), unlike the Session picker
/// which writes into the active workout.
struct RoutineExercisePickerSheet: View {
    let onPick: (Exercise) -> Void
    /// Multi-add (default): tap toggles a checkmark, one "Add N" commit — building a
    /// Push day is one sheet, not six. When false (the replace flow) a tap picks one
    /// and dismisses immediately.
    var allowsMultiple: Bool = true
    /// Overrides the mode-derived navigation title (e.g. a caller's "Swap Exercise").
    var title: String? = nil
    /// Single-select only: the exercise currently occupying the slot, so the sheet
    /// can mark it with a checkmark instead of offering it as a fresh pick.
    var selectedID: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    @Query private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var pickedIDs: [UUID] = []   // add order preserved
    @State private var isCreating = false

    init(allowsMultiple: Bool = true, title: String? = nil, selectedID: UUID? = nil,
         onPick: @escaping (Exercise) -> Void) {
        self.onPick = onPick
        self.allowsMultiple = allowsMultiple
        self.title = title
        self.selectedID = selectedID
        let exerciseFilter = #Predicate<Exercise> { !$0.isArchived && $0.deletedAt == nil }
        _exercises = Query(filter: exerciseFilter, sort: [SortDescriptor(\Exercise.name)])
    }

    var body: some View {
        NavigationStack {
            MuscleGroupedPicker(exercises: exercises, searchText: searchText) { exercise in
                row(exercise)
            } footer: {
                Button {
                    isCreating = true
                } label: {
                    HStack(spacing: 12) {
                        ExerciseGlyphView(muscle: .other)
                            .frame(width: 40, height: 40)
                        Text("Create custom exercise")
                            .foregroundStyle(SettColor.heroCyan)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            .overlay {
                if filtered.isEmpty && !searchText.isEmpty {
                    EmptyChamber(title: "No match",
                                 message: "No exercise named “\(searchText)”.",
                                 actionLabel: "Forge “\(searchText)”") {
                        isCreating = true
                    }
                }
            }
            .dungeonBackground()
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle(title ?? (allowsMultiple ? "Add Exercises" : "Replace Exercise"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if allowsMultiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(pickedIDs.isEmpty ? "Add" : "Add \(pickedIDs.count)") { commit() }
                            .fontWeight(.semibold)
                            .disabled(pickedIDs.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                // A routine-editor creation immediately joins the picked set (multi-add)
                // or picks-and-dismisses (replace flow), matching the row behaviour.
                CreateExerciseSheet(initialName: searchText) { exercise in
                    if allowsMultiple {
                        pickedIDs.append(exercise.id)
                    } else {
                        onPick(exercise)
                        dismiss()
                    }
                }
            }
        }
    }

    /// Commit every picked exercise in tap order, then dismiss.
    private func commit() {
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in pickedIDs { if let ex = byID[id] { onPick(ex) } }
        Haptics.success()
        dismiss()
    }

    private func toggle(_ exercise: Exercise) {
        if let i = pickedIDs.firstIndex(of: exercise.id) {
            pickedIDs.remove(at: i)
            Haptics.selection()
        } else {
            pickedIDs.append(exercise.id)
            Haptics.selection()
        }
    }

    /// Search-miss overlay uses this to know when nothing matched — same rule the
    /// shared picker filters by, so overlay and list can't disagree.
    private var filtered: [Exercise] {
        ExerciseNameFilter.apply(exercises, query: searchText)
    }

    // MARK: Row

    private func row(_ exercise: Exercise) -> some View {
        // Multi: checked once added. Single: checked = the slot's current exercise.
        let isChecked = allowsMultiple ? pickedIDs.contains(exercise.id)
                                       : exercise.id == selectedID
        return Button {
            if allowsMultiple {
                toggle(exercise)
            } else {
                onPick(exercise)
                Haptics.selection()
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                ExerciseIcon(name: exercise.name, equipment: exercise.equipment,
                             muscle: exercise.muscle, size: 40, color: SettColor.heroCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .foregroundStyle(SettColor.bone)
                    Text(exercise.equipment.rawValue.capitalized)
                        .font(.footnote)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer()
                Image(systemName: isChecked ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isChecked ? SettColor.heroCyan
                                               : (allowsMultiple ? SettColor.iron : SettColor.heroCyan))
                    // isChecked recomputes when pickedIDs mutates, so the value-scoped
                    // animation is what drives the plus↔checkmark symbol replace.
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.snappy(duration: 0.2), value: isChecked)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
        // .borderless (not .plain): in a List, borderless buttons get the full-row
        // tap target; .plain restricted hit-testing to the label and left most of
        // the row dead — only the trailing + reliably registered.
        .buttonStyle(.borderless)
    }
}
