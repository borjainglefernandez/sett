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

    /// Badges earned in THIS session — the medal/PR moment the history row
    /// celebrates, surfaced here where the user relives the workout.
    @Query private var badgeAwards: [BadgeAward]

    init(workout: Workout) {
        self.workout = workout
        let wid = workout.id
        _badgeAwards = Query(
            filter: #Predicate<BadgeAward> { $0.workoutID == wid && $0.deletedAt == nil },
            sort: [SortDescriptor(\BadgeAward.earnedAt)])
    }

    /// Unlocks corrections — the shared ExerciseCard's review affordances, plus the
    /// header's own live controls (title, date, rating, location, off-the-record).
    @State private var editing = false
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
                // THE session list's card, not a lookalike: same tiers, same vs-last
                // deltas, same rows. Edit mode unlocks the same corrections.
                ForEach(workout.orderedExercises) { workoutExercise in
                    ExerciseCard(workoutExercise: workoutExercise,
                                 mode: .review(editable: editing),
                                 onMutate: recomputeAfterCorrection)
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
        .onAppear {
            refreshNet()
            #if DEBUG
            // Screenshot harness: SETT_DEBUG_SURFACE=detail SETT_DEBUG_EDIT=1 opens
            // straight into edit mode (the simulator can't be clicked into it).
            if !(ProcessInfo.processInfo.environment["SETT_DEBUG_EDIT"] ?? "").isEmpty {
                editing = true
            }
            #endif
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Done" : "Edit") { withAnimation(.snappy) { editing.toggle() } }
                    .fontWeight(editing ? .semibold : .regular)
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
        .sheet(isPresented: $isEditingNotes) {
            SetNoteSheet(initialText: workout.notes ?? "",
                         title: "Session Notes",
                         placeholder: "how it went, what to change…") { text in
                session.setWorkoutNotes(text, for: workout)
            }
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
            } else if net?.isNew == true, !workout.isCasual {
                StatusChip("NEW", tint: SettColor.heroCyan)
            }
            if !badgeAwards.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badgeAwards) { award in
                        StatusChip(badgeName(award.badgeKey), tint: SettColor.saiyanGold,
                                   icon: "medal.fill")
                    }
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
                    stat(BodyweightFormat.valueWithUnit(grams: bodyweight,
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

    /// Config's display name for an earned badge key; the raw key is a safe fallback.
    private func badgeName(_ key: String) -> String {
        services.progression.config?.badge(key)?.name ?? key
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
            .contentTransition(.numericText(value: Double(value)))
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
                                   withAnimation(.snappy) {
                                       session.setStartDate(date, for: workout)
                                       recomputeAfterCorrection()
                                   }
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
                withAnimation(.snappy) {
                    session.setCasual(casual, for: workout)
                    recomputeAfterCorrection()
                }
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
