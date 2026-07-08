import SwiftUI
import SwiftData
import SettCore

/// Full-screen active session UI (Flow 1). Zero network dependency; every control
/// reads and writes the local store through `WorkoutSessionStore`.
///
/// The elapsed timer derives purely from `workout.startedAt` wall clock via
/// `TimelineView`, so it survives backgrounding and app kill. Pause is omitted in v0
/// (`pausedSeconds` stays 0); the design's pause control ships in a later pass.
struct ActiveWorkoutView: View {
    @Environment(WorkoutSessionStore.self) private var session

    @State private var isShowingExercisePicker = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false

    /// Floating combat text feed (Dark Chamber v3): the overlay is attached once
    /// at ScrollView level, and the emitter travels DOWN via `.environment` so
    /// `SetEntryRow` can emit "+N PWR" on every checkmark commit.
    @State private var combatText = CombatTextEmitter()

    var body: some View {
        NavigationStack {
            Group {
                if let workout = session.activeWorkout {
                    workoutBody(workout)
                } else {
                    // Session ended elsewhere; the cover is on its way out.
                    Color.clear
                }
            }
            .dungeonBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isConfirmingCancel = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel workout")
                }
                ToolbarItem(placement: .principal) {
                    elapsedTimer
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        finishTapped()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Finish workout")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if session.restEndsAt != nil {
                    RestTimerBar()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $isShowingExercisePicker) {
                ExercisePickerSheet()
            }
            .confirmationDialog("Finish workout?",
                                isPresented: $isConfirmingFinish,
                                titleVisibility: .visible) {
                Button("Finish anyway") { session.finishWorkout() }
                Button("Keep training", role: .cancel) {}
            } message: {
                Text("Some exercises have no sets logged yet.")
            }
            .confirmationDialog("Discard this workout?",
                                isPresented: $isConfirmingCancel,
                                titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { session.cancelWorkout() }
                Button("Keep training", role: .cancel) {}
            } message: {
                Text("All sets logged in this session will be deleted.")
            }
        }
    }

    // MARK: Body

    private func workoutBody(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(workout.title)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 4)
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
                    // Quiet hint for the stark empty chamber — ash, not cyan:
                    // it's ambience, not a call to action.
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

    // MARK: Elapsed timer (wall-clock derived — survives backgrounding)

    private var elapsedTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(elapsedText(at: context.date))
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(SettColor.card, in: Capsule())
        .shadow(color: SettColor.heroCyan.opacity(0.35), radius: 6)
    }

    private func elapsedText(at date: Date) -> String {
        guard let start = session.activeWorkout?.startedAt else { return "0:00" }
        let total = max(0, Int(date.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: Finish

    private func finishTapped() {
        guard let workout = session.activeWorkout else { return }
        let hasEmptyExercise = workout.orderedExercises.contains { $0.orderedSets.isEmpty }
        if hasEmptyExercise {
            Haptics.error()
            isConfirmingFinish = true
        } else {
            session.finishWorkout()
        }
    }
}
