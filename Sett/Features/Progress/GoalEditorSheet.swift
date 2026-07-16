import SwiftUI
import SwiftData
import SettCore

/// New/Edit Goal sheet (Flow 4): preset cards — "Workouts per week" (hero, pre-filled 3),
/// "Volume target" with a stepper, "PR target" with exercise picker + weight
/// stepper — then one cyan commit button. When `editing` is set the kind is locked
/// and Save mutates the goal in place (createdAt/startDate untouched).
struct GoalEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @Query private var exercises: [Exercise]

    /// Non-nil = edit mode: kind locked, commit rewrites targets in place.
    let editing: Goal?

    init(initialKind: GoalKind = .frequency, editing: Goal? = nil) {
        let exerciseFilter = #Predicate<Exercise> { $0.deletedAt == nil && !$0.isArchived }
        _exercises = Query(filter: exerciseFilter, sort: [SortDescriptor(\Exercise.name)])
        self.editing = editing
        _kind = State(initialValue: editing?.kind ?? initialKind)
    }

    @State private var kind: GoalKind = .frequency
    @State private var frequencyTarget = 3
    @State private var volumeTargetDisplay = 0
    @State private var prTargetGrams = 0
    /// Tap-to-type numeric pads for the two weight-valued targets — steppers alone
    /// were the only way to move big values.
    @State private var isTypingTarget = false
    @State private var isTypingVolume = false
    @State private var selectedExerciseID: UUID?
    @State private var selectedExerciseName: String?
    @State private var isPickingExercise = false

    private var unit: WeightUnit { services.settings.unit }
    private var isEditing: Bool { editing != nil }

    private var canCreate: Bool {
        kind != .prTarget || selectedExerciseID != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick a goal type")
                        .font(.headline)
                        .foregroundStyle(SettColor.bone)
                    presetCard(.frequency, title: "Workouts per week",
                               subtitle: "Show up \(frequencyTarget) time\(frequencyTarget == 1 ? "" : "s") a week — the classic.",
                               symbol: "calendar", isHero: true)
                    presetCard(.volumeTarget, title: "Volume target",
                               subtitle: "Total weight moved across all lifts.",
                               symbol: "scalemass.fill")
                    presetCard(.prTarget, title: "One-rep max",
                               subtitle: "Hit a target 1RM on one lift.",
                               symbol: "medal.fill")
                    configSection
                    ChamberCTAButton(isEditing ? "Save Goal" : "Create Goal",
                                     enabled: canCreate, action: commit)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .dungeonBackground()
            .navigationTitle(isEditing ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create", action: commit)
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
            }
            .onAppear(perform: seedDefaults)
            .sheet(isPresented: $isTypingTarget) {
                NumericPadSheet(title: "Target 1RM (\(unit.symbol))",
                                initialText: WeightFormat.compact(grams: prTargetGrams, unit: unit),
                                keyboard: .decimalPad) { text in
                    let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
                    guard value > 0 else { return }
                    prTargetGrams = Units.grams(fromDisplay: value, unit: unit)
                }
            }
            .sheet(isPresented: $isTypingVolume) {
                NumericPadSheet(title: "Volume Target (\(unit.symbol))",
                                initialText: "\(volumeTargetDisplay)",
                                keyboard: .numberPad) { text in
                    guard let value = Int(text.filter(\.isNumber)), value > 0 else { return }
                    volumeTargetDisplay = min(500_000, value)
                }
            }
            .sheet(isPresented: $isPickingExercise) {
                RoutineExercisePickerSheet(allowsMultiple: false,
                                           title: "Choose Exercise",
                                           selectedID: selectedExerciseID) { exercise in
                    selectedExerciseID = exercise.id
                    selectedExerciseName = exercise.name
                }
            }
        }
    }

    // MARK: Preset cards (locked in edit mode — a goal never changes kind)

    private func presetCard(_ cardKind: GoalKind, title: String, subtitle: String,
                            symbol: String, isHero: Bool = false) -> some View {
        Button {
            kind = cardKind
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(isHero ? .title2 : .title3)
                    .foregroundStyle(kind == cardKind ? AnyShapeStyle(SettColor.heroCyan) : AnyShapeStyle(SettColor.ash))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(isHero ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(SettColor.bone)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SettColor.ash)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: kind == cardKind ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(kind == cardKind ? AnyShapeStyle(SettColor.heroCyan) : AnyShapeStyle(SettColor.iron))
            }
            .padding(isHero ? 20 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(kind == cardKind ? SettColor.heroCyan : .clear, lineWidth: 2)
            }
            .opacity(isEditing && kind != cardKind ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isEditing)
    }

    // MARK: Per-kind configuration

    @ViewBuilder
    private var configSection: some View {
        switch kind {
        case .frequency:
            HStack {
                Text("Days per week")
                    .foregroundStyle(SettColor.bone)
                Spacer()
                ChamberStepper(value: $frequencyTarget, in: 1...7)
            }
            .settCard()
        case .volumeTarget:
            HStack {
                Text("Volume target")
                    .foregroundStyle(SettColor.bone)
                Spacer()
                ChamberStepControl(text: "\(volumeTargetDisplay.formatted()) \(unit.symbol)",
                                   onDecrement: { volumeTargetDisplay = max(1_000, volumeTargetDisplay - 1_000) },
                                   onIncrement: { volumeTargetDisplay = min(500_000, volumeTargetDisplay + 1_000) },
                                   onTapValue: { isTypingVolume = true })
            }
            .settCard()
        case .prTarget:
            VStack(spacing: 12) {
                Button {
                    isPickingExercise = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Exercise")
                            .foregroundStyle(SettColor.bone)
                        Spacer(minLength: 8)
                        Text(selectedExerciseName ?? "Choose…")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(selectedExerciseName == nil ? SettColor.ash : SettColor.heroCyan)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SettColor.iron)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exercise: \(selectedExerciseName ?? "not chosen")")
                HStack {
                    Text("Target 1RM")
                        .foregroundStyle(SettColor.bone)
                    Spacer()
                    ChamberStepControl(text: services.settings.displayWeight(prTargetGrams),
                                       onDecrement: {
                                           prTargetGrams = max(services.settings.incrementGrams,
                                                               prTargetGrams - services.settings.incrementGrams)
                                       },
                                       onIncrement: { prTargetGrams += services.settings.incrementGrams },
                                       onTapValue: { isTypingTarget = true })
                }
            }
            .settCard()
        }
    }

    // MARK: Commit (insert new, or rewrite the edited goal's targets in place)

    private func commit() {
        guard canCreate else { return }
        if let editing {
            save(into: editing)
        } else {
            insertNew()
        }
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    private func insertNew() {
        let goal: Goal
        switch kind {
        case .frequency:
            goal = Goal(kind: .frequency, targetValue: frequencyTarget)
        case .volumeTarget:
            goal = Goal(kind: .volumeTarget,
                        targetValue: Units.grams(fromDisplay: Double(volumeTargetDisplay), unit: unit))
        case .prTarget:
            guard let exercise = exercises.first(where: { $0.id == selectedExerciseID }) else { return }
            goal = Goal(kind: .prTarget, targetValue: prTargetGrams,
                        exerciseID: exercise.id, exerciseNameSnapshot: exercise.name)
        }
        modelContext.insert(goal)
    }

    /// Edit mode only touches the targets — createdAt/startDate stay, so streak
    /// windows and evaluator history don't reset.
    private func save(into goal: Goal) {
        switch kind {
        case .frequency:
            goal.targetValue = frequencyTarget
        case .volumeTarget:
            goal.targetValue = Units.grams(fromDisplay: Double(volumeTargetDisplay), unit: unit)
        case .prTarget:
            guard let exercise = exercises.first(where: { $0.id == selectedExerciseID }) else { return }
            goal.targetValue = prTargetGrams
            goal.exerciseID = exercise.id
            goal.exerciseNameSnapshot = exercise.name
        }
        goal.updatedAt = .now
        goal.needsPush = true
    }

    private func seedDefaults() {
        if let editing {
            prefill(from: editing)
        }
        if volumeTargetDisplay == 0 {
            volumeTargetDisplay = unit == .kg ? 10_000 : 20_000
        }
        if prTargetGrams == 0 {
            prTargetGrams = unit == .kg
                ? Units.grams(fromDisplay: 60, unit: .kg)
                : Units.grams(fromDisplay: 135, unit: .lb)
        }
    }

    private func prefill(from goal: Goal) {
        switch goal.kind {
        case .frequency:
            frequencyTarget = goal.targetValue
        case .volumeTarget:
            volumeTargetDisplay = Int((Double(goal.targetValue) / unit.gramsPerUnit).rounded())
        case .prTarget:
            prTargetGrams = goal.targetValue
            selectedExerciseID = goal.exerciseID
            selectedExerciseName = goal.exerciseNameSnapshot
        }
    }
}
