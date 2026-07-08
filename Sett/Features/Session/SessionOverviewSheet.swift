import SwiftUI
import SettCore

/// Overview state (v3.1): the old exercise-card list survives as a sheet — the
/// toolbox, not the workspace. Add exercises, review every logged set, edit notes
/// and machine setups. Keeps the normal Dark Chamber styling; incognito rules apply
/// to the player behind it, not here.
struct SessionOverviewSheet: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingExercisePicker = false
    /// The sheet gets its own emitter so combat text from SetEntryRow commits rises
    /// over the sheet, not under it on the player root.
    @State private var combatText = CombatTextEmitter()

    var body: some View {
        NavigationStack {
            Group {
                if let workout = session.activeWorkout {
                    list(workout)
                } else {
                    Color.clear
                }
            }
            .dungeonBackground()
            .navigationTitle(session.activeWorkout?.title ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingExercisePicker) {
                ExercisePickerSheet()
            }
        }
        .presentationDetents([.large])
    }

    private func list(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(workout.orderedExercises) { workoutExercise in
                    ExerciseCard(workoutExercise: workoutExercise)
                }
                Button {
                    isShowingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                if workout.orderedExercises.isEmpty {
                    // Quiet hint for the stark empty chamber — ash, not cyan.
                    VStack(spacing: 8) {
                        SettSigil(size: 28, color: SettColor.ash)
                        Text("The Scanner is waiting.")
                            .font(.footnote.monospaced())
                            .foregroundStyle(SettColor.ash)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
        }
        .combatTextEmitter(combatText)
        .environment(combatText)
    }
}
