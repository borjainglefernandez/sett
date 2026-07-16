import SwiftUI
import SwiftData
import SettCore

/// Review one finished workout (design-ux §2): stats header, every set as
/// logged, notes, and "Repeat workout" — a fresh session with the same
/// exercises, presented by the root fullScreenCover.
struct WorkoutDetailView: View {
    let workout: Workout

    @Environment(AppServices.self) private var services
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    /// Committed set being corrected in the shared value editor.
    @State private var editingSet: SetEntry?
    /// Committed set whose note is open in the shared note sheet.
    @State private var notingSet: SetEntry?
    /// Set awaiting the delete confirmation (deleting rewrites PWR).
    @State private var deletingSet: SetEntry?
    @State private var isPickingGym = false
    @State private var isRenaming = false
    @State private var isEditingNotes = false
    /// Net vs the previous same-exercise sessions — the same readout the history rows
    /// wear, so the detail answers "did I progress?" without going back.
    @State private var net: NetSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                ForEach(workout.orderedExercises) { workoutExercise in
                    exerciseCard(workoutExercise)
                }
                if editing {
                    editableNotesCard
                } else if let notes = workout.notes, !notes.isEmpty {
                    notesCard(notes)
                }
                if !editing { repeatButton }
            }
            .padding(16)
        }
        .dungeonBackground()
        .onAppear(perform: refreshNet)
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                    .fontWeight(editing ? .semibold : .regular)
            }
        }
        .sheet(item: $editingSet) { set in
            SetValuesEditSheet(set: set, unit: services.settings.unit) { weight, reps, warm in
                session.editSet(set, weightGrams: weight, reps: reps, isWarmup: warm)
                recomputeAfterCorrection()
            }
        }
        .sheet(isPresented: $isPickingGym) {
            GymPickerSheet(currentID: workout.gymID) { gym in
                session.setGym(gym, for: workout)
            }
        }
        .sheet(isPresented: $isRenaming) {
            WorkoutRenameSheet(initialTitle: workout.title) { title in
                session.renameWorkout(title, for: workout)
            }
        }
        .sheet(item: $notingSet) { set in
            SetNoteSheet(initialText: set.notes ?? "") { text in
                set.notes = text
                set.updatedAt = .now
                set.needsPush = true
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $isEditingNotes) {
            SetNoteSheet(initialText: workout.notes ?? "",
                         title: "Session Notes",
                         placeholder: "how it went, what to change…") { text in
                session.setWorkoutNotes(text, for: workout)
            }
        }
        .confirmationDialog("Delete this set?",
                            isPresented: Binding(get: { deletingSet != nil },
                                                 set: { if !$0 { deletingSet = nil } }),
                            titleVisibility: .visible,
                            presenting: deletingSet) { set in
            Button("Delete Set", role: .destructive) {
                session.deleteSet(set)
                recomputeAfterCorrection()
            }
        } message: { _ in
            Text("Removing it rewrites this workout's power numbers.")
        }
    }

    /// A finished-workout correction should move the power level now, not on some later
    /// recompute — a mis-logged set poisoned PWR, so fixing it must un-poison it.
    private func recomputeAfterCorrection() {
        services.progression.recompute(context: modelContext)
        refreshNet()   // corrections move the vs-last readout too
    }

    private func refreshNet() {
        let samples = SampleExtractor.setSamples(context: modelContext)
        net = ProgressEngine.workoutNet(samples: samples, workoutID: workout.id)
    }

    // MARK: Header (duration / rating / bodyweight / gym)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing { titleRow }
            dateRow
            if let net, !workout.isCasual, !net.isNew {
                HStack(spacing: 8) {
                    Eyebrow("NET VS LAST")
                    netChip(value: net.reps, suffix: "reps")
                    netChip(value: Int((Double(net.volumeGrams) / services.settings.unit.gramsPerUnit).rounded()),
                            suffix: services.settings.unit.symbol)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                stat(WorkoutFormat.duration(workout.durationSeconds), caption: "duration")
                if editing {
                    VStack(alignment: .leading, spacing: 4) {
                        editableStars
                        Text("rating")
                            .font(.footnote)
                            .foregroundStyle(SettColor.ash)
                    }
                } else if let rating = workout.ratingHalfStars, rating > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        StarRatingRow(halfStars: rating, starSize: 13)
                        Text("rating")
                            .font(.footnote)
                            .foregroundStyle(SettColor.ash)
                    }
                }
                if let bodyweight = workout.bodyweightGrams {
                    stat(WeightFormat.compactWithUnit(grams: bodyweight,
                                                      unit: services.settings.unit),
                         caption: "bodyweight")
                }
            }
            locationRow
            if editing { casualToggle }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    /// Net chip — the history rows' grammar (+N green / −N red, cut-neutral ash).
    private func netChip(value: Int, suffix: String) -> some View {
        let negativeColor = workout.phase == .cutting ? SettColor.ash : SettColor.negative
        let color = value >= 0 ? SettColor.positive : negativeColor
        return Text("\(value >= 0 ? "+" : "")\(value) \(suffix)")
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .font(.caption2.weight(.bold))
            .monospacedDigit()
    }

    /// Title — read-only text lives in the nav bar; edit mode surfaces it here as
    /// a live control (the same cyan-tap grammar as the location row).
    private var titleRow: some View {
        Button { isRenaming = true } label: {
            HStack(spacing: 6) {
                Text(workout.title)
                    .font(.headline)
                    .foregroundStyle(SettColor.heroCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Title: \(workout.title)")
        .accessibilityHint("Renames this workout")
    }

    /// Start date — static read-back normally, a compact DatePicker in edit mode.
    /// Moving the date reorders history + references, hence the recompute.
    @ViewBuilder
    private var dateRow: some View {
        if editing {
            HStack {
                Eyebrow("STARTED")
                Spacer()
                DatePicker("Workout start date",
                           selection: Binding(
                               get: { workout.startedAt },
                               set: { date in
                                   session.setStartDate(date, for: workout)
                                   recomputeAfterCorrection()
                               }),
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(SettColor.heroCyan)
            }
        } else {
            Text(workout.startedAt.formatted(date: .complete, time: .shortened))
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
    }

    /// Tappable stars (full-star taps; re-tapping the current value clears) with one
    /// adjustable VoiceOver control — the summary sheet's rating grammar, half-step.
    private var editableStars: some View {
        let rating = workout.ratingHalfStars ?? 0
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    session.setRating(rating == star * 2 ? nil : star * 2, for: workout)
                } label: {
                    Image(systemName: starSymbol(star, rating: rating))
                        .font(.system(size: 15))
                        .foregroundStyle(SettColor.heroCyan)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout rating")
        .accessibilityValue(rating == 0 ? "Not rated"
                            : "\(String(format: "%.1f", Double(rating) / 2)) stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: session.setRating(min(10, rating + 1), for: workout)
            case .decrement: session.setRating(rating <= 1 ? nil : rating - 1, for: workout)
            @unknown default: break
            }
        }
    }

    private func starSymbol(_ star: Int, rating: Int) -> String {
        if rating >= star * 2 {
            "star.fill"
        } else if rating == star * 2 - 1 {
            "star.leadinghalf.filled"
        } else {
            "star"
        }
    }

    /// Off-the-record toggle — casual gates net-progress inclusion, so flipping it
    /// must re-run the engine immediately.
    private var casualToggle: some View {
        Toggle(isOn: Binding(
            get: { workout.isCasual },
            set: { casual in
                session.setCasual(casual, for: workout)
                recomputeAfterCorrection()
            })) {
            Text("OFF THE RECORD")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.ash)
        }
        .tint(TimeChamber.teal)
    }

    /// Location — always shown once set; in edit mode it's a live control (and offers
    /// "Add location" when empty). Mirrors the active session's overview row.
    @ViewBuilder
    private var locationRow: some View {
        if editing {
            Button { isPickingGym = true } label: {
                HStack(spacing: 6) {
                    Label(workout.gymNameSnapshot ?? "Add location",
                          systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(SettColor.heroCyan)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SettColor.iron)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location: \(workout.gymNameSnapshot ?? "not set")")
            .accessibilityHint("Changes this workout's gym")
        } else if let gym = workout.gymNameSnapshot {
            Label(gym, systemImage: "mappin.and.ellipse")
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
    }

    private func stat(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
    }


    // MARK: Exercises — the active session's scouter card, in read-back form.
    // Same icon medallion, mono header, stat line, badge + value grid; the top set
    // wears amber, the rest green, warm-ups ash — history reads like the session did.

    private func exerciseCard(_ workoutExercise: WorkoutExercise) -> some View {
        let topID = topSetID(workoutExercise)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ExerciseIcon(name: workoutExercise.exerciseNameSnapshot,
                             equipment: workoutExercise.equipment,
                             muscle: workoutExercise.muscle,
                             size: 44,
                             color: topID == nil ? SettColor.heroCyan : TimeChamber.scouterAmber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workoutExercise.exerciseNameSnapshot.uppercased())
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(statLine(workoutExercise))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                ForEach(workoutExercise.orderedSets, id: \.id) { set in
                    setRow(set, in: workoutExercise, isTop: set.id == topID)
                }
            }
            if workoutExercise.orderedSets.isEmpty {
                Text("No sets logged")
                    .font(.footnote)
                    .foregroundStyle(SettColor.iron)
            }
            if editing { addSetRow(workoutExercise) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudCard(tint: topID == nil ? SettColor.heroCyan : TimeChamber.scouterAmber)
    }

    private func setRow(_ set: SetEntry, in workoutExercise: WorkoutExercise,
                        isTop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                SetIndexBadge(label: badgeLabel(set, in: workoutExercise),
                              charge: set.isWarmup ? .warmup : .earned(isTop ? .ascended : .base))
                Spacer().frame(width: SetRowGrid.badgeGap)
                setValueColumns(
                    weightText: WeightFormat.compactWithUnit(grams: set.weightGrams,
                                                             unit: services.settings.unit),
                    repsText: "\(set.reps)",
                    valueColor: editing ? SettColor.heroCyan : SettColor.bone,
                    weight: .semibold)
                Spacer(minLength: 0)
                if !set.isWarmup {
                    Text("PWR \(pwr(set, in: workoutExercise))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(isTop ? TimeChamber.scouterAmber : TimeChamber.scouterGreen)
                }
                if editing {
                    Button(role: .destructive) {
                        deletingSet = set
                    } label: {
                        Image(systemName: "trash")
                            .font(.footnote)
                            .foregroundStyle(SettColor.negative)
                            .frame(width: 40, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete set")
                }
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
            .onTapGesture {
                guard editing else { return }
                editingSet = set
            }
            // The in-session set grammar, so history corrections speak the same verbs.
            .contextMenu {
                if editing {
                    Button { editingSet = set } label: {
                        Label("Fix weight & reps", systemImage: "pencil")
                    }
                    Button { notingSet = set } label: {
                        Label("Edit note", systemImage: "note.text")
                    }
                    Button {
                        session.duplicateSet(set)
                        recomputeAfterCorrection()
                    } label: {
                        Label("Duplicate set", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) { deletingSet = set } label: {
                        Label("Delete set", systemImage: "trash")
                    }
                }
            }
            .accessibilityAddTraits(editing ? [.isButton] : [])
            .accessibilityHint(editing ? "Edits this set's values" : "")
            // Per-set note, indented to the value columns.
            if let setNotes = set.notes, !setNotes.isEmpty {
                Text(setNotes)
                    .font(.caption)
                    .foregroundStyle(SettColor.ash)
                    .padding(.leading, SetRowGrid.badge + SetRowGrid.badgeGap)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, SetRowGrid.hPad)
        // The SESSION list's slab grammar — void fill, tier accent bar, hairline rim —
        // so a finished workout reads like the live one, not a bare stat sheet.
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            ZStack {
                shape.fill(TimeChamber.void.opacity(0.5))
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(set.isWarmup ? SettColor.iron.opacity(0.6)
                              : (isTop ? TimeChamber.scouterAmber : TimeChamber.scouterGreen))
                        .frame(width: 3)
                    Spacer()
                }
                shape.strokeBorder(SettColor.cardBorder, lineWidth: 1)
            }
        }
    }

    /// Dashed slot at the card's foot — appends one set after the last, ghosting its
    /// numbers so the correction starts from something plausible instead of zero.
    private func addSetRow(_ workoutExercise: WorkoutExercise) -> some View {
        Button {
            addSet(to: workoutExercise)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                Text("ADD SET")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1.5)
            }
            .foregroundStyle(SettColor.heroCyan)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SettColor.cardBorder,
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add set")
        .accessibilityHint("Appends a set copying the last set's weight and reps")
    }

    /// Insert AFTER the last set (a forgotten set, not a reorder), under the
    /// standard sync rules; the new volume moves PWR now.
    private func addSet(to workoutExercise: WorkoutExercise) {
        let last = workoutExercise.orderedSets.last
        let set = SetEntry(orderIndex: (last?.orderIndex ?? -1) + 1,
                           weightGrams: last?.weightGrams ?? 0,
                           entryUnit: services.settings.unit,
                           reps: last?.reps ?? 0)
        set.workoutExercise = workoutExercise
        modelContext.insert(set)
        workout.updatedAt = .now
        workout.needsPush = true
        try? modelContext.save()
        recomputeAfterCorrection()
        Haptics.light()
    }

    // MARK: Per-set scoring (same effective-load PWR the session showed)

    private func pwr(_ set: SetEntry, in workoutExercise: WorkoutExercise) -> Int {
        let eff = LoadMath.effectiveWeightGrams(
            addedGrams: set.weightGrams, equipment: workoutExercise.equipment,
            bodyweightGrams: workout.bodyweightGrams)
        return Int(Units.pounds(fromGrams: ProgressEngine.e1RMGrams(weightGrams: eff,
                                                                    reps: set.reps)).rounded())
    }

    /// The set with the session's best e1RM — wears the amber crown.
    private func topSetID(_ workoutExercise: WorkoutExercise) -> UUID? {
        workoutExercise.orderedSets.filter { !$0.isWarmup }
            .max { pwr($0, in: workoutExercise) < pwr($1, in: workoutExercise) }?.id
    }

    private func statLine(_ workoutExercise: WorkoutExercise) -> String {
        let working = workoutExercise.orderedSets.filter { !$0.isWarmup }
        var parts = ["\(working.count) SET\(working.count == 1 ? "" : "S")"]
        if let top = working.map({ pwr($0, in: workoutExercise) }).max(), top > 0 {
            parts.append("TOP \(top) PWR")
        }
        let volGrams = working.reduce(0) { $0 + $1.weightGrams * $1.reps }
        if volGrams > 0 {
            let vol = Int((Double(volGrams) / services.settings.unit.gramsPerUnit).rounded())
            parts.append("\(vol.formatted()) \(services.settings.unit.symbol.uppercased())")
        }
        return parts.joined(separator: " · ")
    }

    /// Working-set ordinal, "W" for warm-ups — the overview's badge language.
    private func badgeLabel(_ set: SetEntry, in workoutExercise: WorkoutExercise) -> String {
        if set.isWarmup { return "W" }
        var n = 0
        for sibling in workoutExercise.orderedSets where !sibling.isWarmup {
            n += 1
            if sibling.id == set.id { return "\(n)" }
        }
        return "\(n)"
    }

    // MARK: Notes

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(SettColor.bone)
            Text(notes)
                .font(.body)
                .foregroundStyle(SettColor.bone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    /// Edit mode always renders the notes card — empty reads as an invitation.
    private var editableNotesCard: some View {
        let notes = workout.notes ?? ""
        return Button { isEditingNotes = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Notes", systemImage: "note.text")
                        .font(.headline)
                        .foregroundStyle(SettColor.bone)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SettColor.iron)
                }
                Text(notes.isEmpty ? "Add session notes" : notes)
                    .font(.body)
                    .foregroundStyle(notes.isEmpty ? SettColor.ash : SettColor.bone)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits this workout's notes")
    }

    // MARK: Repeat

    private var repeatButton: some View {
        ChamberCTAButton("Repeat Workout") { repeatWorkout() }
            .padding(.top, 4)
    }

    private func repeatWorkout() {
        session.quickStart(title: workout.title)
        for exerciseID in distinctExerciseIDs {
            guard let exercise = fetchExercise(id: exerciseID) else { continue }
            session.addExercise(exercise)
        }
        dismiss()
    }

    /// Exercise IDs in workout order, deduplicated.
    private var distinctExerciseIDs: [UUID] {
        var seen = Set<UUID>()
        return workout.orderedExercises.compactMap {
            seen.insert($0.exerciseID).inserted ? $0.exerciseID : nil
        }
    }

    private func fetchExercise(id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let exercise = (try? modelContext.fetch(descriptor))?.first,
              exercise.deletedAt == nil else { return nil }
        return exercise
    }
}

// MARK: - Rename sheet (finished-workout title, in the shared shell)

/// One TextField in a ChamberSheet; the store trims and rejects empty on its side
/// too, but SAVE stays disabled until there is something to save.
private struct WorkoutRenameSheet: View {
    let initialTitle: String
    let onSave: (String) -> Void

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ChamberSheet(title: "Rename Workout",
                     canCommit: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                     onCommit: { onSave(title) }) {
            TextField("Workout title", text: $title)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(SettColor.bone)
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(12)
                .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .presentationDetents([.height(220)])
        .onAppear {
            title = initialTitle
            isFocused = true
        }
    }
}
