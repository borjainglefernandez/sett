import Foundation

/// Pure goal-progress evaluation (design-gamification §6). Goals are checked,
/// not logged: progress derives from the same set/workout samples that feed
/// the rest of the engine. Warmup sets never count.
public enum GoalEvaluator {

    public static func progress(goal: GoalSample, setSamples: [SetSample], workoutSamples: [WorkoutSample],
                                calendar: Calendar, asOf: Date) -> GoalProgress {
        let target = goal.targetValue
        guard target > 0 else {
            // Degenerate target: nothing to reach, treat as complete.
            return GoalProgress(goalID: goal.id, fraction: 1.0, currentValue: 0,
                                targetValue: target, isComplete: true)
        }

        // Evidence window: [startDate, min(asOf, endDate)].
        let windowEnd = min(asOf, goal.endDate ?? asOf)

        let currentValue: Int
        switch goal.kind {
        case .frequency:
            // Distinct workout days in the ISO week containing the evaluation
            // date ("2 of 3 workouts" — the ring resets every week).
            currentValue = frequencyDays(goal: goal, workoutSamples: workoutSamples,
                                         calendar: calendar, windowEnd: windowEnd)
        case .prTarget:
            // Best e1RM (grams) achieved on the goal's exercise inside the window.
            currentValue = qualifyingSets(goal: goal, setSamples: setSamples, windowEnd: windowEnd)
                .map { ProgressEngine.e1RMGrams(weightGrams: $0.weightGrams, reps: $0.reps) }
                .max() ?? 0
        case .volumeTarget:
            // Tonnage (gram·reps) accumulated inside the window.
            currentValue = qualifyingSets(goal: goal, setSamples: setSamples, windowEnd: windowEnd)
                .reduce(0) { $0 + $1.weightGrams * $1.reps }
        }

        let isComplete = goal.completedAt != nil || currentValue >= target
        let fraction = isComplete
            ? 1.0
            : min(1.0, max(0.0, Double(currentValue) / Double(target)))
        return GoalProgress(goalID: goal.id, fraction: fraction, currentValue: currentValue,
                            targetValue: target, isComplete: isComplete)
    }

    // MARK: - Helpers

    /// Non-warmup sets inside the goal window, filtered to the goal's exercise when set.
    private static func qualifyingSets(goal: GoalSample, setSamples: [SetSample],
                                       windowEnd: Date) -> [SetSample] {
        setSamples.filter {
            !$0.isWarmup
                && (goal.exerciseID == nil || $0.exerciseID == goal.exerciseID)
                && $0.completedAt >= goal.startDate
                && $0.completedAt <= windowEnd
        }
    }

    /// Distinct workout days within the week containing `windowEnd`, clipped
    /// to the goal window. Workout samples are already finished workouts.
    private static func frequencyDays(goal: GoalSample, workoutSamples: [WorkoutSample],
                                      calendar: Calendar, windowEnd: Date) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: windowEnd) else { return 0 }
        let dayKeys = Set(
            workoutSamples
                .map(\.startedAt)
                .filter {
                    $0 >= week.start && $0 < week.end
                        && $0 >= goal.startDate && $0 <= windowEnd
                }
                .map { calendar.dateKey(for: $0) }
        )
        return dayKeys.count
    }
}
