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
            // The rest clock lives full-screen in RestOverlayView BEHIND this sheet, so
            // it vanishes exactly when you open the toolbox — usually DURING rest. Pin a
            // slim rest strip up top so the one time-critical number is always here too.
            .safeAreaInset(edge: .top, spacing: 0) {
                if session.isResting { restStrip }
            }
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

    // MARK: Rest strip — remaining time derived from restEndsAt (never accumulated)

    @ViewBuilder
    private var restStrip: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = restRemaining(at: context.date)
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TimeChamber.scouterGreen)
                Text("REST")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(SettColor.ash)
                Text(restTimeText(remaining))
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                Spacer(minLength: 8)
                restButton("−15") { session.adjustRest(by: -15) }
                restButton("SKIP") { session.skipRest() }
                restButton("+15") { session.adjustRest(by: 15) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(alignment: .bottom) {
                Rectangle().fill(TimeChamber.void.opacity(0.94)).ignoresSafeArea(edges: .top)
                Rectangle().fill(TimeChamber.scouterGreen.opacity(0.4)).frame(height: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest, \(restTimeText(remaining)) remaining")
        }
    }

    private func restButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(TimeChamber.scouterGreen)
                .frame(minWidth: 42, minHeight: 32)
                .background { Capsule().strokeBorder(TimeChamber.scouterGreen.opacity(0.4), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func restRemaining(at date: Date) -> Int {
        guard let ends = session.restEndsAt else { return 0 }
        return max(0, Int(ends.timeIntervalSince(date).rounded(.up)))
    }

    private func restTimeText(_ remaining: Int) -> String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
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
