import SwiftUI
import SettCore

/// One collapsible card per exercise in the active workout: header (muscle icon, name,
/// sets logged), compact confirmed chips for every logged set with a net-vs-reference
/// delta, then a single editable next-set row (`SetEntryRow`).
struct ExerciseCard: View {
    let workoutExercise: WorkoutExercise

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isExpanded {
                let logged = workoutExercise.orderedSets
                let references = referenceSets
                if !logged.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(logged.enumerated()), id: \.element.id) { index, set in
                            confirmedChip(set: set,
                                          reference: index < references.count ? references[index] : nil,
                                          number: index + 1)
                        }
                    }
                }
                SetEntryRow(workoutExercise: workoutExercise)
            }
        }
        .settCard()
    }

    /// Same-exercise sets from the most recent finished workout, paired by index.
    private var referenceSets: [SetEntry] {
        session.previousSets(exerciseID: workoutExercise.exerciseID,
                             excluding: workoutExercise.workout?.id)
    }

    // MARK: Header

    private var header: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: workoutExercise.muscle.sessionSymbolName)
                    .font(.title3)
                    .foregroundStyle(SettColor.heroCyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutExercise.exerciseNameSnapshot)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(setsLoggedLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var setsLoggedLabel: String {
        let count = workoutExercise.orderedSets.count
        return count == 1 ? "1 set logged" : "\(count) sets logged"
    }

    // MARK: Confirmed set chips

    private func confirmedChip(set: SetEntry, reference: SetEntry?, number: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SettColor.heroCyan)
            Text("\(number)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("\(services.settings.displayWeight(set.weightGrams)) × \(set.reps)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            Spacer()
            if let chip = netChip(set: set, reference: reference) {
                Text(chip.text)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(chip.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private struct NetChip {
        let text: String
        let color: Color
    }

    /// Weight delta first ("+5 lb"); same weight → reps delta ("+2 reps"); identical → no chip.
    /// No reference at this index (fresh territory) → no chip.
    private func netChip(set: SetEntry, reference: SetEntry?) -> NetChip? {
        guard let reference else { return nil }
        let unit = services.settings.unit
        let weightDelta = set.weightGrams - reference.weightGrams
        if weightDelta != 0 {
            let value = Units.displayValue(grams: abs(weightDelta), unit: unit)
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(format: "%.2f", value)
            let sign = weightDelta > 0 ? "+" : "−"
            return NetChip(text: "\(sign)\(formatted) \(unit.symbol)",
                           color: weightDelta > 0 ? SettColor.positive : SettColor.negative)
        }
        let repsDelta = set.reps - reference.reps
        if repsDelta != 0 {
            let sign = repsDelta > 0 ? "+" : "−"
            return NetChip(text: "\(sign)\(abs(repsDelta)) reps",
                           color: repsDelta > 0 ? SettColor.positive : SettColor.negative)
        }
        return nil
    }
}

// MARK: - Muscle icon mapping (Session feature)

extension Muscle {
    var sessionSymbolName: String {
        switch self {
        case .chest: "figure.arms.open"
        case .triceps: "figure.strengthtraining.traditional"
        case .biceps: "figure.strengthtraining.functional"
        case .shoulders: "figure.wave"
        case .back: "figure.rower"
        case .legs: "figure.run"
        case .core: "figure.core.training"
        case .other: "dumbbell.fill"
        }
    }
}
