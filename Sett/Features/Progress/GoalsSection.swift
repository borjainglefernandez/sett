import SwiftUI
import SwiftData
import SettCore

/// Card 5 — goals (Flow 4): one ring per active goal (gold + checkmark once
/// complete), tap to edit, swipe-left to soft-delete, "New Goal" opens the
/// editor sheet. Progress is always computed by `GoalEvaluator` from workout data.
struct GoalsSection: View {
    let goals: [Goal]
    let setSamples: [SetSample]
    let workoutSamples: [WorkoutSample]
    let unit: WeightUnit
    let calendar: Calendar

    @Environment(\.modelContext) private var modelContext
    @State private var isShowingEditor = false
    @State private var editingGoal: Goal?
    /// Goals whose completed-state gold burst already played this view lifetime.
    @State private var celebrated: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow("GOALS")
                Spacer()
                Button {
                    isShowingEditor = true
                } label: {
                    Label("New Goal", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if goals.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(goals) { goal in
                        SwipeToDeleteRow(onDelete: { delete(goal) },
                                         onTap: { editingGoal = goal }) {
                            goalRow(goal)
                        }
                        .accessibilityAction(named: "Edit") { editingGoal = goal }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            GoalEditorSheet()
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditorSheet(editing: goal)
        }
    }

    // MARK: Rows

    private func goalRow(_ goal: Goal) -> some View {
        let progress = displayProgress(goal)
        return HStack(spacing: 16) {
            GoalRingView(progress: progress, title: title(for: goal))
                .overlay {
                    // One gold burst per goal the first time it renders complete;
                    // the timed insert removes the (already-spent) burst afterwards.
                    if progress.isComplete, !celebrated.contains(goal.id) {
                        AuraBurstView(gold: true)
                            .task {
                                try? await Task.sleep(for: .seconds(1))
                                celebrated.insert(goal.id)
                            }
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(detail(for: goal))
                    .font(.subheadline)
                    .foregroundStyle(SettColor.ash)
                if progress.isComplete {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SettColor.saiyanGold)
                }
            }
            Spacer(minLength: 0)
        }
        .settCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Text("Set your first goal — start with 3 workouts a week")
                .font(.subheadline)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
            ChamberCTAButton("3 × / week") {
                createPresetFrequencyGoal()
            }
        }
        .frame(maxWidth: .infinity)
        .settCard()
    }

    // MARK: Evaluation

    private func sample(_ goal: Goal) -> GoalSample {
        GoalSample(id: goal.id, kind: goal.kind, targetValue: goal.targetValue,
                   exerciseID: goal.exerciseID, startDate: goal.startDate, endDate: goal.endDate,
                   isActive: goal.isActive, completedAt: goal.completedAt, createdAt: goal.createdAt)
    }

    /// Gram-valued kinds (PR, volume) are mapped to display units for the ring;
    /// the fraction and completion come straight from the evaluator.
    private func displayProgress(_ goal: Goal) -> GoalProgress {
        let raw = GoalEvaluator.progress(goal: sample(goal), setSamples: setSamples,
                                         workoutSamples: workoutSamples,
                                         calendar: calendar, asOf: .now)
        switch goal.kind {
        case .frequency:
            return raw
        case .prTarget, .volumeTarget:
            return GoalProgress(
                goalID: raw.goalID,
                fraction: raw.fraction,
                currentValue: Int((Double(raw.currentValue) / unit.gramsPerUnit).rounded()),
                targetValue: Int((Double(raw.targetValue) / unit.gramsPerUnit).rounded()),
                isComplete: raw.isComplete
            )
        }
    }

    private func title(for goal: Goal) -> String {
        switch goal.kind {
        case .frequency: "Workouts / week"
        case .prTarget: goal.exerciseNameSnapshot ?? "PR target"
        case .volumeTarget: "Volume target"
        }
    }

    private func detail(for goal: Goal) -> String {
        switch goal.kind {
        case .frequency:
            "\(goal.targetValue) workout\(goal.targetValue == 1 ? "" : "s") a week"
        case .prTarget:
            "Target e1RM \(WeightText.formatted(grams: goal.targetValue, unit: unit))"
        case .volumeTarget:
            "Target volume \(volumeText(goal.targetValue))"
        }
    }

    private func volumeText(_ grams: Int) -> String {
        let value = Int((Double(grams) / unit.gramsPerUnit).rounded())
        return "\(value.formatted()) \(unit.symbol)"
    }

    // MARK: Mutations

    private func delete(_ goal: Goal) {
        goal.deletedAt = .now
        goal.updatedAt = .now
        goal.needsPush = true
        try? modelContext.save()
        Haptics.light()
    }

    private func createPresetFrequencyGoal() {
        let goal = Goal(kind: .frequency, targetValue: 3)
        modelContext.insert(goal)
        try? modelContext.save()
        Haptics.success()
    }
}

// MARK: - Swipe-to-delete (custom — rows live in a ScrollView, not a List)

private struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    /// Fired on a plain tap when the row is fully closed (open rows close instead).
    var onTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false

    private let revealWidth: CGFloat = 76

    var body: some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                // Recover a row left partly-open by an interrupted drag (isOpen would be
                // false then, stranding the offset) — gate on the actual offset instead.
                if offsetX != 0 { close() } else { onTap?() }
            }
            .offset(x: offsetX)
            .background(alignment: .trailing) {
                deleteBackground
            }
            .gesture(drag)
            .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var deleteBackground: some View {
        Button {
            withAnimation(.snappy) { onDelete() }
        } label: {
            Image(systemName: "trash.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(SettColor.negative, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityLabel("Delete goal")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base: CGFloat = isOpen ? -revealWidth : 0
                offsetX = min(0, max(-revealWidth - 24, base + value.translation.width))
            }
            .onEnded { value in
                let base: CGFloat = isOpen ? -revealWidth : 0
                let projected = base + value.translation.width
                withAnimation(.snappy) {
                    if projected < -revealWidth / 2 {
                        offsetX = -revealWidth
                        isOpen = true
                    } else {
                        offsetX = 0
                        isOpen = false
                    }
                }
            }
    }

    private func close() {
        withAnimation(.snappy) {
            offsetX = 0
            isOpen = false
        }
    }
}
