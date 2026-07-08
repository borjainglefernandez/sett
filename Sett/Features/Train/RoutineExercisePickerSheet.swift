import SwiftUI
import SwiftData
import SettCore

/// The routine editor's own searchable exercise picker. It hands the chosen
/// exercise back through a closure and dismisses — it never touches the store
/// (drafts persist only when the editor's Save runs), unlike the Session picker
/// which writes into the active workout.
struct RoutineExercisePickerSheet: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss

    @Query private var exercises: [Exercise]

    @State private var searchText = ""

    init(onPick: @escaping (Exercise) -> Void) {
        self.onPick = onPick
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
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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
        Button {
            onPick(exercise)
            Haptics.light()
            dismiss()
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
                // Visual affordance only — the entire row is the button.
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(SettColor.heroCyan)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        // .borderless (not .plain): in a List, borderless buttons get the full-row
        // tap target; .plain restricted hit-testing to the label and left most of
        // the row dead — only the trailing + reliably registered.
        .buttonStyle(.borderless)
    }
}
