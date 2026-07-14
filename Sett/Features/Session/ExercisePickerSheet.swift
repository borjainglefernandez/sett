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
            MuscleGroupedPicker(exercises: exercises, searchText: searchText) { exercise in
                row(exercise)
            } footer: {
                createRow
            }
            .overlay {
                if filtered.isEmpty && !searchText.isEmpty {
                    // Not in the catalog? Forge it without leaving the workout.
                    EmptyChamber(title: "No match",
                                 message: "No exercise named “\(searchText)”.",
                                 actionLabel: "Forge “\(searchText)”") {
                        isCreating = true
                    }
                }
            }
            .dungeonBackground()
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

    /// Search-miss overlay uses this to know when nothing matched — same rule the
    /// shared picker filters by, so overlay and list can't disagree.
    private var filtered: [Exercise] {
        ExerciseNameFilter.apply(exercises, query: searchText)
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
                             muscle: exercise.muscle, size: 40, color: SettColor.heroCyan)
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
