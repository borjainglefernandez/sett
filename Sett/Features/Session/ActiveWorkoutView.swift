import SwiftUI
import SettCore

/// The Set Player shell (v3.1 — replaces the scrolling card list). A workout is a
/// queue of sets, so the session screen is a player, not a document: one set fills
/// the screen (`SetPlayerView`), rest owns the whole display (`RestOverlayView`),
/// and the old card list survives as the overview sheet (`SessionOverviewSheet`).
///
/// Incognito rules: pure `Color.black` ground (never dungeonBackground in session —
/// no vignette, no grime, no embers), bone/ash/iron text only, hairline dividers
/// instead of etched cards. The only cyan is the LOG slab's hairline flash; the only
/// gold is crit combat text and the beat-reference numeral flash.
///
/// Queue model — view-layer, fully derived, nothing stored: an item is
/// (workoutExercise, set slot). Per exercise, slots = max(planned sets from the
/// source routine, logged sets + 1); the cursor is an (exerciseIndex, slotIndex)
/// pair clamped on every read, so mutations from the overview sheet can never
/// strand it. Swiping past the final set shows the END pane.
struct ActiveWorkoutView: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cursor = QueuePosition(exerciseIndex: 0, slotIndex: 0)
    @State private var hasInitializedCursor = false
    /// Direction of the last queue move — drives the push transition's edge.
    @State private var movesForward = true
    /// Holds the REST overlay ~0.45 s after a beat-reference log so the gold
    /// numeral flash reads before the countdown takes the screen.
    @State private var isHoldingRestOverlay = false

    @State private var isShowingOverview = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingCancel = false

    /// Floating combat text feed, attached once at the player root; the emitter
    /// travels DOWN via `.environment` so `SetPlayerView` can emit on every commit.
    @State private var combatText = CombatTextEmitter()

    @ScaledMetric(relativeTo: .largeTitle) private var endNumeralSize: CGFloat = 56

    var body: some View {
        Group {
            if let workout = session.activeWorkout {
                player(workout)
            } else {
                // Session ended elsewhere; the cover is on its way out.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .combatTextEmitter(combatText)
        .environment(combatText)
        .sheet(isPresented: $isShowingOverview) {
            SessionOverviewSheet()
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

    // MARK: Shell

    private var isRestOverlayVisible: Bool {
        session.restEndsAt != nil && !isHoldingRestOverlay
    }

    private func player(_ workout: Workout) -> some View {
        let exercises = workout.orderedExercises
        let position = clamped(cursor, in: exercises)
        return VStack(spacing: 0) {
            topBar(workout)
                .opacity(isRestOverlayVisible ? 0.55 : 1)
            Rectangle()
                .fill(SettColor.cardBorder)
                .frame(height: 0.5)
            ZStack {
                pane(workout, exercises: exercises, position: position)
                    .transition(paneTransition)
                if isRestOverlayVisible {
                    RestOverlayView(nextLabel: nextPreviewLabel(exercises, from: position),
                                    onAdvance: { advanceCursor() })
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isRestOverlayVisible)
            .simultaneousGesture(swipeGesture(exercises))
        }
        .onAppear { initializeCursorIfNeeded(exercises) }
    }

    private var paneTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return movesForward ? .push(from: .trailing) : .push(from: .leading)
    }

    @ViewBuilder
    private func pane(_ workout: Workout, exercises: [WorkoutExercise],
                      position: QueuePosition) -> some View {
        if exercises.isEmpty {
            emptyPane
        } else if position.exerciseIndex >= exercises.count {
            endPane(workout)
        } else {
            let exercise = exercises[position.exerciseIndex]
            SetPlayerView(workoutExercise: exercise,
                          slotIndex: position.slotIndex,
                          slotCount: slotCount(for: exercise),
                          onLogged: { beat in handleLogged(on: exercise, beatReference: beat) })
                .id("\(exercise.id)-\(position.slotIndex)")
        }
    }

    // MARK: Top bar (✕ · elapsed mono iron · overview · ✓ — all small, ash)

    private func topBar(_ workout: Workout) -> some View {
        HStack(spacing: 0) {
            barButton("xmark", label: "Cancel workout") {
                isConfirmingCancel = true
            }
            Spacer()
            elapsedTimer(workout)
            Spacer()
            barButton("list.bullet", label: "Session overview") {
                isShowingOverview = true
            }
            barButton("checkmark", label: "Finish workout") {
                finishTapped()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func barButton(_ symbol: String, label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SettColor.ash)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Elapsed timer (wall-clock derived — survives backgrounding)

    private func elapsedTimer(_ workout: Workout) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(elapsedText(from: workout.startedAt, at: context.date))
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SettColor.iron)
        }
        .accessibilityLabel("Elapsed time")
    }

    private func elapsedText(from start: Date, at date: Date) -> String {
        let total = max(0, Int(date.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: END pane (past the final set — elapsed, sets logged, END READING)

    private func endPane(_ workout: Workout) -> some View {
        let setsLogged = workout.orderedExercises.reduce(0) { $0 + $1.orderedSets.count }
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(from: workout.startedAt, at: context.date))
                        .font(.system(size: endNumeralSize, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(SettColor.bone)
                }
                Text(setsLogged == 1 ? "1 SET LOGGED" : "\(setsLogged) SETS LOGGED")
                    .font(.system(.caption, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(SettColor.ash)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            PlayerSlab(title: "END READING", flashesCyan: false) {
                finishTapped()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: Empty pane (quick start with no exercises yet)

    private var emptyPane: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 8) {
                SettSigil(size: 28, color: SettColor.ash)
                Text("The Scanner is waiting.")
                    .font(.footnote.monospaced())
                    .foregroundStyle(SettColor.ash)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            PlayerSlab(title: "ADD EXERCISE", flashesCyan: false) {
                isShowingOverview = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: Queue model (derived — slots recompute from the models on every read)

    private func slotCount(for exercise: WorkoutExercise) -> Int {
        max(session.plannedSetCount(for: exercise), exercise.orderedSets.count + 1)
    }

    private func nextOpenSlot(of exercise: WorkoutExercise) -> Int {
        min(exercise.orderedSets.count, slotCount(for: exercise) - 1)
    }

    private func endPosition(_ exercises: [WorkoutExercise]) -> QueuePosition {
        QueuePosition(exerciseIndex: exercises.count, slotIndex: 0)
    }

    private func clamped(_ position: QueuePosition,
                         in exercises: [WorkoutExercise]) -> QueuePosition {
        guard position.exerciseIndex >= 0 else {
            return QueuePosition(exerciseIndex: 0, slotIndex: 0)
        }
        guard position.exerciseIndex < exercises.count else {
            return endPosition(exercises)
        }
        let exercise = exercises[position.exerciseIndex]
        let slot = min(max(position.slotIndex, 0), slotCount(for: exercise) - 1)
        return QueuePosition(exerciseIndex: position.exerciseIndex, slotIndex: slot)
    }

    private func queueLength(_ exercises: [WorkoutExercise]) -> Int {
        exercises.reduce(0) { $0 + slotCount(for: $1) }
    }

    private func flatIndex(of position: QueuePosition,
                           in exercises: [WorkoutExercise]) -> Int {
        guard position.exerciseIndex < exercises.count else { return queueLength(exercises) }
        let before = exercises.prefix(position.exerciseIndex).reduce(0) { $0 + slotCount(for: $1) }
        return before + position.slotIndex
    }

    private func position(atFlatIndex index: Int,
                          in exercises: [WorkoutExercise]) -> QueuePosition {
        var remaining = index
        for (exerciseIndex, exercise) in exercises.enumerated() {
            let slots = slotCount(for: exercise)
            if remaining < slots {
                return QueuePosition(exerciseIndex: exerciseIndex, slotIndex: remaining)
            }
            remaining -= slots
        }
        return endPosition(exercises)
    }

    /// Start on the first exercise with fewer logged sets than planned (resumed
    /// mid-routine), else the first exercise's next open slot.
    private func initializeCursorIfNeeded(_ exercises: [WorkoutExercise]) {
        guard !hasInitializedCursor else { return }
        hasInitializedCursor = true
        if let index = exercises.firstIndex(where: { exercise in
            let planned = session.plannedSetCount(for: exercise)
            return planned > 0 && exercise.orderedSets.count < planned
        }) {
            cursor = QueuePosition(exerciseIndex: index,
                                   slotIndex: nextOpenSlot(of: exercises[index]))
        } else if let first = exercises.first {
            cursor = QueuePosition(exerciseIndex: 0, slotIndex: nextOpenSlot(of: first))
        }
    }

    /// Advance policy (spec): planned sets exhaust → next exercise's first open slot;
    /// plan-less → next set of the same exercise until the user swipes.
    private func advanceTarget(from position: QueuePosition,
                               in exercises: [WorkoutExercise]) -> QueuePosition {
        guard position.exerciseIndex < exercises.count else { return position }
        let exercise = exercises[position.exerciseIndex]
        let planned = session.plannedSetCount(for: exercise)
        if planned > 0 && exercise.orderedSets.count >= planned {
            let nextIndex = position.exerciseIndex + 1
            guard nextIndex < exercises.count else { return endPosition(exercises) }
            return QueuePosition(exerciseIndex: nextIndex,
                                 slotIndex: nextOpenSlot(of: exercises[nextIndex]))
        }
        return QueuePosition(exerciseIndex: position.exerciseIndex,
                             slotIndex: nextOpenSlot(of: exercise))
    }

    private func advanceCursor() {
        guard let workout = session.activeWorkout else { return }
        let exercises = workout.orderedExercises
        move(to: advanceTarget(from: clamped(cursor, in: exercises), in: exercises),
             forward: true)
    }

    private func move(to target: QueuePosition, forward: Bool) {
        movesForward = forward
        withAnimation(.easeInOut(duration: 0.28)) {
            cursor = target
        }
    }

    // MARK: Log → REST / advance

    /// The LOG slab committed a set. `logSet` already auto-started the rest timer;
    /// if this exercise rests, the overlay takes the screen (held ~0.45 s after a
    /// beat-reference log so the gold flash reads), else the cursor advances.
    private func handleLogged(on exercise: WorkoutExercise, beatReference: Bool) {
        let restSeconds = exercise.restSeconds ?? services.settings.defaultRestSeconds
        if restSeconds <= 0 {
            // Clear the zero-length timer logSet started so the overlay never blinks.
            session.skipRest()
        }
        if beatReference {
            isHoldingRestOverlay = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                isHoldingRestOverlay = false
                if restSeconds <= 0 { advanceCursor() }
            }
        } else if restSeconds <= 0 {
            advanceCursor()
        }
    }

    // MARK: NEXT preview (REST overlay caption)

    private func nextPreviewLabel(_ exercises: [WorkoutExercise],
                                  from position: QueuePosition) -> String {
        let target = advanceTarget(from: position, in: exercises)
        guard target.exerciseIndex < exercises.count else { return "NEXT · END READING" }
        let exercise = exercises[target.exerciseIndex]
        let setLabel = "SET \(target.slotIndex + 1)/\(slotCount(for: exercise))"
        if target.exerciseIndex == position.exerciseIndex {
            let ghost = session.ghostValues(for: exercise, slot: target.slotIndex)
            let weight = WeightFormat.compactWithUnit(grams: ghost.weightGrams,
                                                      unit: services.settings.unit)
            return "NEXT · \(weight) × \(ghost.reps) · \(setLabel)"
        }
        return "NEXT · \(exercise.exerciseNameSnapshot.uppercased()) · \(setLabel)"
    }

    // MARK: Swipe (horizontal moves between sets/exercises; SET state doesn't scroll)

    private func swipeGesture(_ exercises: [WorkoutExercise]) -> some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                guard session.restEndsAt == nil else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.4 else { return }
                swipe(dx < 0 ? 1 : -1, in: exercises)
            }
    }

    private func swipe(_ delta: Int, in exercises: [WorkoutExercise]) {
        guard !exercises.isEmpty else { return }
        let length = queueLength(exercises) // END pane sits at index == length
        let current = flatIndex(of: clamped(cursor, in: exercises), in: exercises)
        let target = min(max(current + delta, 0), length)
        guard target != current else { return }
        Haptics.selection()
        move(to: position(atFlatIndex: target, in: exercises), forward: delta > 0)
    }

    // MARK: Finish (✓ works from anywhere; confirms when an exercise has no sets)

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

// MARK: - Queue cursor

/// A position in the derived session queue: (exercise index, set slot index).
/// `exerciseIndex == orderedExercises.count` is the END pane.
struct QueuePosition: Equatable {
    var exerciseIndex: Int
    var slotIndex: Int
}
