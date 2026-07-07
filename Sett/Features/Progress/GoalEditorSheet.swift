import SwiftUI
import SwiftData
import SettCore

/// New Goal sheet (Flow 4): preset cards — "Workouts per week" (hero, pre-filled 3),
/// "Volume target" with a stepper, "PR target" with exercise picker + weight
/// stepper — then one cyan Create button. Creation saves and fires the success haptic.
struct GoalEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @Query private var exercises: [Exercise]

    init() {
        let exerciseFilter = #Predicate<Exercise> { $0.deletedAt == nil && !$0.isArchived }
        _exercises = Query(filter: exerciseFilter, sort: [SortDescriptor(\Exercise.name)])
    }

    @State private var kind: GoalKind = .frequency
    @State private var frequencyTarget = 3
    @State private var volumeTargetDisplay = 0
    @State private var prTargetGrams = 0
    @State private var selectedExerciseID: UUID?

    private var unit: WeightUnit { services.settings.unit }

    private var canCreate: Bool {
        kind != .prTarget || selectedExerciseID != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick a goal type")
                        .font(.headline)
                    presetCard(.frequency, title: "Workouts per week",
                               subtitle: "Show up \(frequencyTarget) times a week — the classic.",
                               symbol: "calendar", isHero: true)
                    presetCard(.volumeTarget, title: "Volume target",
                               subtitle: "Total weight moved across all lifts.",
                               symbol: "scalemass.fill")
                    presetCard(.prTarget, title: "PR target",
                               subtitle: "Chase an e1RM on one lift.",
                               symbol: "trophy.fill")
                    configSection
                    createButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(SettColor.screen)
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: seedDefaults)
        }
    }

    // MARK: Preset cards

    private func presetCard(_ cardKind: GoalKind, title: String, subtitle: String,
                            symbol: String, isHero: Bool = false) -> some View {
        Button {
            kind = cardKind
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(isHero ? .title2 : .title3)
                    .foregroundStyle(kind == cardKind ? AnyShapeStyle(SettColor.heroCyan) : AnyShapeStyle(.secondary))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(isHero ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: kind == cardKind ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(kind == cardKind ? AnyShapeStyle(SettColor.heroCyan) : AnyShapeStyle(.tertiary))
            }
            .padding(isHero ? 20 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(kind == cardKind ? SettColor.heroCyan : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Per-kind configuration

    @ViewBuilder
    private var configSection: some View {
        switch kind {
        case .frequency:
            Stepper(value: $frequencyTarget, in: 1...7) {
                HStack {
                    Text("Days per week")
                    Spacer()
                    Text("\(frequencyTarget)×")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.heroCyan)
                }
            }
            .settCard()
        case .volumeTarget:
            Stepper(value: $volumeTargetDisplay, in: 1_000...500_000, step: 1_000) {
                HStack {
                    Text("Volume target")
                    Spacer()
                    Text("\(volumeTargetDisplay.formatted()) \(unit.symbol)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.heroCyan)
                }
            }
            .settCard()
        case .prTarget:
            VStack(spacing: 12) {
                HStack {
                    Text("Exercise")
                    Spacer()
                    Picker("Exercise", selection: $selectedExerciseID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(exercises) { exercise in
                            Text(exercise.name).tag(Optional(exercise.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(SettColor.heroCyan)
                }
                Stepper {
                    HStack {
                        Text("Target e1RM")
                        Spacer()
                        Text(services.settings.displayWeight(prTargetGrams))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(SettColor.heroCyan)
                    }
                } onIncrement: {
                    prTargetGrams += services.settings.incrementGrams
                } onDecrement: {
                    prTargetGrams = max(services.settings.incrementGrams,
                                        prTargetGrams - services.settings.incrementGrams)
                }
            }
            .settCard()
        }
    }

    // MARK: Create

    private var createButton: some View {
        Button(action: create) {
            Text("Create Goal")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canCreate ? AnyShapeStyle(Aura.cyan) : AnyShapeStyle(Color(uiColor: .systemGray4)),
                            in: Capsule())
        }
        .disabled(!canCreate)
    }

    private func create() {
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
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    private func seedDefaults() {
        if volumeTargetDisplay == 0 {
            volumeTargetDisplay = unit == .kg ? 10_000 : 20_000
        }
        if prTargetGrams == 0 {
            prTargetGrams = unit == .kg
                ? Units.grams(fromDisplay: 60, unit: .kg)
                : Units.grams(fromDisplay: 135, unit: .lb)
        }
    }
}
