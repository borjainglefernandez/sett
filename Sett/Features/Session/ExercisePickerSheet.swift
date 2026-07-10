import SwiftUI
import SwiftData
import SettCore

/// Searchable exercise catalog grouped by muscle. Tapping a row adds the exercise
/// to the active workout and dismisses.
struct ExercisePickerSheet: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @Query private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var isCreating = false

    init() {
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
                Section {
                    createRow
                }
            }
            .overlay {
                if filtered.isEmpty && !searchText.isEmpty {
                    // Not in the catalog? Forge it without leaving the workout.
                    ContentUnavailableView {
                        Label("No exercise named “\(searchText)”", systemImage: "magnifyingglass")
                    } actions: {
                        Button {
                            isCreating = true
                        } label: {
                            Label("Create “\(searchText)”", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
            .sheet(isPresented: $isCreating) {
                // Creating mid-workout adds the new lift straight to the session.
                CreateExerciseSheet(initialName: searchText) { exercise in
                    session.addExercise(exercise)
                    Haptics.light()
                    dismiss()
                }
            }
        }
    }

    private var createRow: some View {
        Button {
            isCreating = true
        } label: {
            HStack(spacing: 12) {
                ExerciseGlyphView(muscle: .other)
                    .frame(width: 28, height: 28)
                Text("Create custom exercise")
                    .foregroundStyle(SettColor.heroCyan)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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
            session.addExercise(exercise)
            Haptics.light()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ExerciseIcon(name: exercise.name, equipment: exercise.equipment,
                             muscle: exercise.muscle, size: 28, color: SettColor.heroCyan)
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
