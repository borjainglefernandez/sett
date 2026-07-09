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

    @Environment(\.dismiss) private var dismiss

    @Query private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var pickedIDs: [UUID] = []   // add order preserved

    init(allowsMultiple: Bool = true, onPick: @escaping (Exercise) -> Void) {
        self.onPick = onPick
        self.allowsMultiple = allowsMultiple
        let exerciseFilter = #Predicate<Exercise> { !$0.isArchived && $0.deletedAt == nil }
        _exercises = Query(filter: exerciseFilter, sort: [SortDescriptor(\Exercise.name)])
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedMuscles, id: \.self) { muscle in
                    Section(muscle.rawValue.capitalized) {
                        ForEach(grouped[muscle] ?? []) { exercise in
                            row(exercise)
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle(allowsMultiple ? "Add Exercises" : "Replace Exercise")
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
        } else {
            pickedIDs.append(exercise.id)
            Haptics.light()
        }
    }

    // MARK: Grouping

    private var filtered: [Exercise] {
        guard !searchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedStandardContains(searchText) }
    }

    private var grouped: [Muscle: [Exercise]] {
        Dictionary(grouping: filtered, by: \.muscle)
    }

    private var orderedMuscles: [Muscle] {
        Muscle.allCases.filter { grouped[$0] != nil }
    }

    // MARK: Row

    private func row(_ exercise: Exercise) -> some View {
        let isPicked = pickedIDs.contains(exercise.id)
        return Button {
            if allowsMultiple {
                toggle(exercise)
            } else {
                onPick(exercise)
                Haptics.light()
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: exercise.equipment.symbolName)
                    .foregroundStyle(SettColor.heroCyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .foregroundStyle(.primary)
                    Text(exercise.equipment.rawValue.capitalized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Checkmark once added (multi mode); a plain + affordance otherwise.
                Image(systemName: isPicked ? "checkmark.circle.fill"
                                           : (allowsMultiple ? "plus.circle" : "plus.circle.fill"))
                    .foregroundStyle(isPicked ? SettColor.heroCyan
                                              : (allowsMultiple ? SettColor.iron : SettColor.heroCyan))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
        // .borderless (not .plain): in a List, borderless buttons get the full-row
        // tap target; .plain restricted hit-testing to the label and left most of
        // the row dead — only the trailing + reliably registered.
        .buttonStyle(.borderless)
    }
}
