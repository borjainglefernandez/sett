import SwiftUI
import SwiftData
import SettCore

/// The exercise catalog: search, muscle filter chips, and an equipment filter
/// menu in the nav bar (kept off the chip scroller so the two never collide).
/// Rows show the equipment icon and, when the exercise has history, its latest
/// session-best e1RM as a gold power numeral. Tap → ExerciseDetailView.
struct ExerciseLibraryView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query private var exercises: [Exercise]

    init() {
        let exerciseFilter = #Predicate<Exercise> { $0.deletedAt == nil }
        _exercises = Query(filter: exerciseFilter, sort: [SortDescriptor(\Exercise.name)])
    }

    @State private var searchText = ""
    @State private var selectedMuscle: Muscle?
    @State private var selectedEquipment: Equipment?

    /// Set samples snapshotted once per appearance; e1RMs derive from them.
    @State private var samples: [SetSample] = []
    @State private var bestE1RMs: [UUID: Int] = [:]
    @State private var hasLoadedSamples = false

    @State private var isShowingCreateForm = false
    @State private var prefillName = ""

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.vertical, 8)
            List {
                ForEach(orderedMuscles, id: \.self) { muscle in
                    Section {
                        ForEach(grouped[muscle] ?? []) { exercise in
                            row(exercise)
                        }
                    } header: {
                        sectionHeader(muscle.rawValue.uppercased())
                    }
                    .listRowBackground(SettColor.card)
                    .listRowSeparatorTint(SettColor.cardBorder)
                }
                Section {
                    Button {
                        prefillName = ""
                        isShowingCreateForm = true
                    } label: {
                        Label("Create custom exercise", systemImage: "plus")
                            .foregroundStyle(SettColor.heroCyan)
                    }
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("No exercises",
                                               systemImage: "dumbbell.fill",
                                               description: Text("Try a different filter."))
                    } else {
                        searchMissView
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                equipmentMenu
            }
        }
        .sheet(isPresented: $isShowingCreateForm) {
            CreateExerciseSheet(initialName: prefillName)
        }
        .onAppear(perform: loadSamplesIfNeeded)
    }

    // MARK: Filter bar (muscle chips; the equipment menu lives in the nav bar)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                muscleChip(nil, label: "All")
                ForEach(Muscle.allCases, id: \.self) { muscle in
                    muscleChip(muscle, label: muscle.rawValue.capitalized)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// The mono small-caps ash convention (NET THIS WEEK, THIS WEEK, …).
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .kerning(1.5)
            .foregroundStyle(SettColor.ash)
    }

    private func muscleChip(_ muscle: Muscle?, label: String) -> some View {
        let isSelected = selectedMuscle == muscle
        return Button {
            selectedMuscle = muscle
            Haptics.selection()
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? SettColor.heroCyan : SettColor.card, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var equipmentMenu: some View {
        Menu {
            Picker("Equipment", selection: $selectedEquipment) {
                Text("All Equipment").tag(Equipment?.none)
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    Label(equipment.rawValue.capitalized, systemImage: equipment.symbolName)
                        .tag(Equipment?.some(equipment))
                }
            }
        } label: {
            Image(systemName: selectedEquipment == nil
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.title3)
                .foregroundStyle(SettColor.heroCyan)
        }
        .accessibilityLabel("Filter by equipment")
    }

    // MARK: Filtering & grouping

    private var filtered: [Exercise] {
        exercises.filter { exercise in
            (selectedMuscle == nil || exercise.muscle == selectedMuscle)
                && (selectedEquipment == nil || exercise.equipment == selectedEquipment)
                && (searchText.isEmpty || exercise.name.localizedStandardContains(searchText))
        }
    }

    private var grouped: [Muscle: [Exercise]] {
        Dictionary(grouping: filtered, by: \.muscle)
    }

    private var orderedMuscles: [Muscle] {
        Muscle.allCases.filter { grouped[$0] != nil }
    }

    // MARK: Row

    private func row(_ exercise: Exercise) -> some View {
        NavigationLink {
            ExerciseDetailView(exercise: exercise)
        } label: {
            HStack(spacing: 12) {
                ExerciseIcon(name: exercise.name, equipment: exercise.equipment,
                             muscle: exercise.muscle, size: 40, color: SettColor.heroCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .foregroundStyle(exercise.isArchived ? .secondary : .primary)
                    HStack(spacing: 6) {
                        Text(exercise.equipment.rawValue.capitalized)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if exercise.isArchived {
                            Text("Archived")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SettColor.cardNested, in: Capsule())
                        }
                    }
                }
                Spacer()
                if let e1rm = bestE1RMs[exercise.id] {
                    PowerNumeral(displayValue(e1rm), size: .m)
                        .accessibilityLabel("e1RM \(displayValue(e1rm)) \(services.settings.unit.symbol)")
                }
            }
        }
        .frame(minHeight: 44)
    }

    private func displayValue(_ grams: Int) -> Int {
        Int(Units.displayValue(grams: grams, unit: services.settings.unit).rounded())
    }

    // MARK: Search miss ("No match — create '<query>'?")

    private var searchMissView: some View {
        ContentUnavailableView {
            Label("No match", systemImage: "magnifyingglass")
        } description: {
            Text("No exercise named “\(searchText)”.")
        } actions: {
            Button("Create “\(searchText)”") {
                prefillName = searchText
                isShowingCreateForm = true
            }
            .font(.headline)
        }
    }

    // MARK: e1RM lookup (computed once per appearance from a sample snapshot)

    private func loadSamplesIfNeeded() {
        guard !hasLoadedSamples else { return }
        hasLoadedSamples = true
        samples = SampleExtractor.setSamples(context: modelContext)
        var result: [UUID: Int] = [:]
        let byExercise = Dictionary(grouping: samples, by: \.exerciseID)
        for (exerciseID, subset) in byExercise {
            if let latest = ProgressEngine.bestE1RMSeries(samples: subset, exerciseID: exerciseID).last {
                result[exerciseID] = latest.e1RMGrams
            }
        }
        bestE1RMs = result
    }
}

// MARK: - Create custom exercise (duplicate name+muscle+equipment guard)

struct CreateExerciseSheet: View {
    /// Invoked with the newly created exercise — the in-session picker uses this to
    /// drop the new lift straight into the active workout.
    var onCreate: ((Exercise) -> Void)? = nil
    let initialName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var existing: [Exercise]

    init(initialName: String, onCreate: ((Exercise) -> Void)? = nil) {
        self.initialName = initialName
        self.onCreate = onCreate
        let existingFilter = #Predicate<Exercise> { $0.deletedAt == nil }
        _existing = Query(filter: existingFilter)
    }

    @State private var name = ""
    @State private var muscle: Muscle = .chest
    @State private var equipment: Equipment = .dumbbell

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Muscle", selection: $muscle) {
                        ForEach(Muscle.allCases, id: \.self) { muscle in
                            Text(muscle.rawValue.capitalized).tag(muscle)
                        }
                    }
                    // Custom lifts wear the muscle group's warrior emblem — show the
                    // badge this exercise will carry, live with the picker.
                    HStack(spacing: 12) {
                        ExerciseGlyphView(muscle: muscle)
                            .frame(width: 44, height: 44)
                        Text("Battle emblem")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                        Spacer()
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases, id: \.self) { equipment in
                            Label(equipment.rawValue.capitalized, systemImage: equipment.symbolName)
                                .tag(equipment)
                        }
                    }
                } footer: {
                    if isDuplicate {
                        Label("This exercise is already in your library.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(SettColor.negative)
                    }
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty || isDuplicate)
                }
            }
            .onAppear { name = initialName }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        let candidate = trimmedName
        guard !candidate.isEmpty else { return false }
        return existing.contains { exercise in
            exercise.muscle == muscle
                && exercise.equipment == equipment
                && exercise.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    private func save() {
        let exercise = Exercise(name: trimmedName, muscle: muscle,
                                equipment: equipment, isCustom: true)
        modelContext.insert(exercise)
        try? modelContext.save()
        Haptics.success()
        onCreate?(exercise)
        dismiss()
    }
}
