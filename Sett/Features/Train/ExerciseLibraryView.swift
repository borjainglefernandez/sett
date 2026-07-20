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
                        Eyebrow(muscle.rawValue.uppercased())
                    }
                    .listRowBackground(SettColor.card)
                    .listRowSeparatorTint(SettColor.cardBorder)
                }
                Section {
                    Button {
                        prefillName = ""
                        isShowingCreateForm = true
                    } label: {
                        CreateExerciseRowLabel()
                    }
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            // Menu-driven bindings (the nav-bar equipment picker) can't route through
            // withAnimation, so the list animates on the value instead.
            .animation(.snappy, value: selectedEquipment)
            .overlay {
                if filtered.isEmpty {
                    if searchText.isEmpty {
                        EmptyChamber(title: "No exercises here",
                                     message: "Try a different filter.")
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
                    muscleChip(muscle, label: muscle.rawValue)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func muscleChip(_ muscle: Muscle?, label: String) -> some View {
        FilterChip(label, active: selectedMuscle == muscle) {
            withAnimation(.snappy) { selectedMuscle = muscle }
            Haptics.selection()
        }
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
        let base = exercises.filter { exercise in
            (selectedMuscle == nil || exercise.muscle == selectedMuscle)
                && (selectedEquipment == nil || exercise.equipment == selectedEquipment)
        }
        // Shared match rule, so this list and the picker sheets can never disagree.
        return ExerciseNameFilter.apply(base, query: searchText)
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
                        .foregroundStyle(exercise.isArchived ? SettColor.ash : SettColor.bone)
                    HStack(spacing: 6) {
                        Text(exercise.equipment.rawValue.capitalized)
                            .font(.footnote)
                            .foregroundStyle(SettColor.ash)
                        if exercise.isArchived {
                            Text("Archived")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(SettColor.ash)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SettColor.cardNested, in: Capsule())
                        }
                    }
                }
                Spacer()
                if let e1rm = bestE1RMs[exercise.id] {
                    // Power-number canon: the gold PowerNumeral is the PL's alone.
                    Text("e1RM \(displayValue(e1rm)) \(services.settings.unit.symbol)")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(SettColor.heroCyan)
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
        EmptyChamber(title: "No match",
                     message: "No exercise named “\(searchText)”.",
                     actionLabel: "Forge “\(searchText)”") {
            prefillName = searchText
            isShowingCreateForm = true
        }
    }

    // MARK: e1RM lookup (computed once per appearance from a sample snapshot)

    private func loadSamplesIfNeeded() {
        guard !hasLoadedSamples else { return }
        hasLoadedSamples = true
        let samples = SampleExtractor.setSamples(context: modelContext)
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
    /// drop the new lift straight into the active workout. Not called on edits.
    var onCreate: ((Exercise) -> Void)? = nil
    let initialName: String
    /// When set, the sheet edits this custom exercise in place (prefilled fields,
    /// "Edit Exercise" title) instead of forging a new row.
    let editing: Exercise?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var existing: [Exercise]

    init(initialName: String, existing: Exercise? = nil,
         onCreate: ((Exercise) -> Void)? = nil) {
        self.initialName = initialName
        self.editing = existing
        self.onCreate = onCreate
        let existingFilter = #Predicate<Exercise> { $0.deletedAt == nil }
        _existing = Query(filter: existingFilter)
    }

    @State private var name = ""
    @State private var muscle: Muscle = .chest
    @State private var equipment: Equipment = .dumbbell
    /// True once Save inserts the row — suppresses the duplicate warning that would
    /// otherwise flash for a frame when the @Query re-fetches and sees the new record.
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    forgePreview
                    nameField
                    muscleGrid
                    equipmentRow
                    if isDuplicate && !isSaving {
                        Label("You've already forged this lift — it's in your library.",
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(SettColor.ash)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .dungeonBackground()
            .navigationTitle(editing == nil ? "Forge Exercise" : "Edit Exercise")
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
            .onAppear {
                if let editing {
                    name = editing.name
                    muscle = editing.muscle
                    equipment = editing.equipment
                } else {
                    name = initialName
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Live preview — the badge this lift will wear, updating with every choice.
    // ExerciseIcon resolves name-first, so typing a known movement ("Bench Press")
    // upgrades the emblem from the muscle default to that movement's warrior art.

    private var forgePreview: some View {
        HStack(spacing: 14) {
            ExerciseIcon(name: trimmedName, equipment: equipment, muscle: muscle,
                         size: 56, color: SettColor.heroCyan)
                .id("\(trimmedName)|\(muscle.rawValue)")   // re-resolve art on change
            VStack(alignment: .leading, spacing: 3) {
                Text(trimmedName.isEmpty ? "Name your lift" : trimmedName)
                    .font(.headline)
                    .foregroundStyle(trimmedName.isEmpty ? SettColor.ash : SettColor.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(muscle.rawValue.uppercased()) · \(equipment.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(SettColor.ash)
            }
            Spacer(minLength: 0)
        }
        .hudCard()
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("NAME")
            TextField("e.g. Landmine Press", text: $name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
                .font(.body)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(SettColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: Muscle grid — every group wears its warrior emblem, tap to choose.

    private var muscleGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("MUSCLE")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 8) {
                ForEach(Muscle.allCases, id: \.self) { candidate in
                    choiceChip(isSelected: muscle == candidate) {
                        muscle = candidate
                    } content: {
                        VStack(spacing: 5) {
                            ExerciseIcon(name: "", equipment: equipment, muscle: candidate,
                                         size: 40, color: SettColor.heroCyan)
                            Text(candidate.rawValue.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(muscle == candidate ? SettColor.bone : SettColor.ash)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .accessibilityLabel(candidate.rawValue.capitalized)
                    .accessibilityAddTraits(muscle == candidate ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: Equipment row — custom implement glyphs (SF Symbols has no gym gear).

    private var equipmentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("EQUIPMENT")
            HStack(spacing: 8) {
                ForEach(Equipment.allCases, id: \.self) { candidate in
                    choiceChip(isSelected: equipment == candidate) {
                        equipment = candidate
                    } content: {
                        VStack(spacing: 6) {
                            EquipmentGlyph(equipment: candidate,
                                           color: equipment == candidate ? SettColor.heroCyan : SettColor.ash)
                                .frame(width: 26, height: 26)
                            Text(candidate.rawValue.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(equipment == candidate ? SettColor.bone : SettColor.ash)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .accessibilityLabel(candidate.rawValue.capitalized)
                    .accessibilityAddTraits(equipment == candidate ? [.isSelected] : [])
                }
            }
        }
    }

    private func choiceChip<Content: View>(isSelected: Bool, action: @escaping () -> Void,
                                           @ViewBuilder content: () -> Content) -> some View {
        Button {
            // 0.15 mirrors ChamberSegments/ChamberStepControl — the fill and
            // border-weight change eases instead of snapping.
            withAnimation(.snappy(duration: 0.15)) { action() }
            Haptics.selection()
        } label: {
            content()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? SettColor.heroCyan.opacity(0.12) : SettColor.card)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? SettColor.heroCyan.opacity(0.8)
                                                 : SettColor.cardBorder.opacity(0.6),
                                      lineWidth: isSelected ? 1.5 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        let candidate = trimmedName
        guard !candidate.isEmpty else { return false }
        return existing.contains { exercise in
            exercise.id != editing?.id   // the row being edited is not its own dupe
                && exercise.muscle == muscle
                && exercise.equipment == equipment
                && exercise.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    private func save() {
        isSaving = true
        if let editing {
            update(editing)
        } else {
            let exercise = Exercise(name: trimmedName, muscle: muscle,
                                    equipment: equipment, isCustom: true)
            modelContext.insert(exercise)
            try? modelContext.save()
            onCreate?(exercise)
        }
        Haptics.success()
        dismiss()
    }

    /// Edit path: mutate the row in place, then refresh the live routine templates
    /// that snapshot its name/muscle. Historical WorkoutExercise snapshots stay
    /// frozen — the log records what the lift was called when it was done.
    private func update(_ exercise: Exercise) {
        let renamed = exercise.name != trimmedName
        let remuscled = exercise.muscleRaw != muscle.rawValue
        exercise.name = trimmedName
        exercise.muscle = muscle
        exercise.equipment = equipment
        exercise.updatedAt = .now
        exercise.needsPush = true
        if renamed || remuscled {
            let id = exercise.id
            let descriptor = FetchDescriptor<RoutineExercise>(
                predicate: #Predicate { $0.exerciseID == id && $0.deletedAt == nil })
            for row in (try? modelContext.fetch(descriptor)) ?? [] {
                row.exerciseNameSnapshot = exercise.name
                row.muscleRaw = exercise.muscleRaw
                row.updatedAt = .now
                row.needsPush = true
            }
        }
        try? modelContext.save()
    }
}
