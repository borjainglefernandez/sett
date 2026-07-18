import SwiftUI
import SwiftData
import SettCore
import UniformTypeIdentifiers

/// How an ExerciseCard behaves. The SAME card renders the live session list AND a
/// finished workout — history is the session view frozen, not a lookalike that
/// drifts from it.
enum ExerciseCardMode: Equatable {
    /// Active session: the plan shows as planned rows, one live input row, add-to-plan.
    case live
    /// Finished workout: every row is history (no plan, no input row). `editable`
    /// unlocks corrections — tap-to-fix, swipe, add set.
    case review(editable: Bool)

    var isLive: Bool { self == .live }

    var isEditable: Bool {
        switch self {
        case .live: true
        case .review(let editable): editable
        }
    }
}

/// One collapsible card per exercise: header (muscle icon, name, sets logged), the
/// machine-setup line (visible WHILE training — that's the point), compact confirmed
/// chips for every logged set with a net-vs-reference delta, then a single editable
/// next-set row (`SetEntryRow`). `mode` swaps live logging for history review.
struct ExerciseCard: View {
    let workoutExercise: WorkoutExercise
    var mode: ExerciseCardMode = .live
    /// Review only: a correction to a SEALED workout must move the power level now,
    /// so the owner recomputes here. Live logging settles up at finishWorkout.
    var onMutate: (() -> Void)?

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = true
    /// Exercise row behind the loose `exerciseID` — carries the machine setup.
    @State private var exercise: Exercise?
    /// Committed set whose note is being edited in the shared `SetNoteSheet`.
    @State private var editingSet: SetEntry?
    /// Committed set whose weight/reps are being fixed in `SetValuesEditSheet`.
    @State private var editingValues: SetEntry?
    /// Exercise whose machine setup is being edited in `MachineSetupSheet`.
    @State private var setupTarget: Exercise?
    /// The one logged row currently swiped open (only one at a time per card).
    @State private var openSwipeRowID: UUID?
    /// The logged row currently lifted for a long-press drag reorder.
    @State private var draggingSet: SetEntry?
    /// An unstarted exercise shows its whole plan as PLANNED — tapping the first row
    /// "begins" it (reveals the active input) so the order is deliberate, not pre-armed.
    @State private var hasBegun = false
    /// Mid-session swap: single-select picker adds the replacement, then removes this.
    @State private var isReplacing = false
    /// Removing an exercise WITH logged sets confirms first; an empty one removes directly.
    @State private var isConfirmingRemove = false
    /// Review only: deleting from a sealed workout rewrites its power numbers, so it asks.
    @State private var deletingSet: SetEntry?
    /// The previous session's sets — a full-history DB fetch, resolved ONCE and cached.
    /// Running that fetch from a body-read computed property re-triggered SwiftData
    /// observation on every render (a fetch inside `body`), and setPairs/topTier read it
    /// several times per render — together that pinned a CPU core and froze the workout
    /// detail. Cached because the reference is PRIOR sessions' work, stable for this card.
    @State private var referenceCache: [SetEntry] = []
    @State private var referenceResolved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            machineSetupRow
            if isExpanded {
                VStack(spacing: 6) {
                    // Logged sets (filled), the active next-set input, then every set
                    // still planned as a dimmed placeholder — the whole plan up front.
                    ForEach(setPairs, id: \.set.id) { pair in
                        loggedRow(pair)
                    }
                    if mode.isLive && !planComplete && isStarted {
                        SetEntryRow(workoutExercise: workoutExercise, setNumber: workingLoggedCount + 1)
                    }
                    ForEach(pendingSlots, id: \.self) { ordinal in
                        plannedRow(number: ordinal + 1, slot: ordinal,
                                   canBegin: !isStarted && ordinal == pendingSlots.first)
                    }
                    if workoutExercise.orderedSets.isEmpty && !mode.isLive {
                        Text("No sets logged")
                            .font(.footnote)
                            .foregroundStyle(SettColor.iron)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Live: add a set to the plan on the fly (quick-start and routine
                    // workouts alike). Review: append a forgotten set, edit mode only.
                    if mode.isEditable { addSetButton }
                }
                // Log/delete/duplicate change orderedSets.count — animate so the
                // committed row and the shifting planned rows slide in rather than pop
                // (add/remove planned rows self-animate on plannedWorking, not this key).
                .animation(.snappy(duration: 0.25), value: workoutExercise.orderedSets.count)
            }
        }
        .hudCard(tint: topTier.color)
        .confirmationDialog("Delete this set?",
                            isPresented: Binding(get: { deletingSet != nil },
                                                 set: { if !$0 { deletingSet = nil } }),
                            titleVisibility: .visible,
                            presenting: deletingSet) { set in
            Button("Delete Set", role: .destructive) { mutate { session.deleteSet(set) } }
        } message: { _ in
            Text("Removing it rewrites this workout's power numbers.")
        }
        // Reset the lifted row if a drag is released anywhere over the card (incl. the
        // padding) so a cancelled reorder never leaves a row stuck at 0.35 opacity.
        .onDrop(of: [.text], isTargeted: nil) { _ in draggingSet = nil; return false }
        .onAppear {
            if exercise == nil {
                exercise = session.fetchExercise(id: workoutExercise.exerciseID)
            }
            resolveReferencesIfNeeded()
        }
        .sheet(item: $editingSet) { set in
            SetNoteSheet(initialText: set.notes ?? "") { saveNote($0, on: set) }
        }
        .sheet(item: $editingValues) { set in
            SetValuesEditSheet(set: set, unit: services.settings.unit) { weight, reps, warm in
                mutate { session.editSet(set, weightGrams: weight, reps: reps, isWarmup: warm) }
            }
        }
        .sheet(item: $setupTarget) { target in
            MachineSetupSheet(exercise: target)
        }
    }

    /// The lens this card's sets were scored through — read off the OWNING workout, so
    /// a reviewed session keeps the phase it was logged under (never today's).
    private var phase: TrainingPhase { workoutExercise.workout?.phase ?? .maintaining }
    private var unit: WeightUnit { services.settings.unit }

    /// A logged row: swipe-to-duplicate/delete and drag-to-reorder are live affordances;
    /// review shows the same row, still and correctable.
    @ViewBuilder
    private func loggedRow(_ pair: (set: SetEntry, reference: SetEntry?, label: String)) -> some View {
        if mode.isLive {
            SwipeableSetRow(rowID: pair.set.id, openRowID: $openSwipeRowID,
                            onDuplicate: { session.duplicateSet(pair.set) },
                            onDelete: { session.deleteSet(pair.set) }) {
                setRow(set: pair.set, reference: pair.reference, label: pair.label)
            }
            // Long-press to lift a logged row, drag to reorder sets live.
            .opacity(draggingSet?.id == pair.set.id ? 0.35 : 1)
            .onDrag {
                draggingSet = pair.set
                return NSItemProvider(object: pair.set.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDropDelegate(
                target: pair.set, items: workoutExercise.orderedSets,
                dragging: $draggingSet,
                move: { session.moveSet(in: workoutExercise, from: $0, to: $1) }))
        } else {
            // Live's SwipeableSetRow clips the row to its own capsule; without it the
            // tier accent bar overruns the corner arc and floats free of the row's edge.
            setRow(set: pair.set, reference: pair.reference, label: pair.label)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Every set mutation funnels here so a review correction recomputes the power
    /// level immediately — a mis-logged set poisoned PWR, fixing it must un-poison it.
    private func mutate(_ change: () -> Void) {
        withAnimation(.snappy) {
            change()
            onMutate?()
        }
    }

    /// Same-exercise sets from the most recent finished workout (warm-ups already
    /// excluded), paired to THIS session's working sets by working-set ordinal so a
    /// warm-up never shifts a set onto the wrong reference. Reviewing an old workout
    /// compares against what came before IT, not against sessions logged since.
    private var referenceSets: [SetEntry] { referenceCache }

    /// Resolve the reference sets ONCE (on appear), never during body. The reference is
    /// the previous session's work — independent of edits to THIS workout — so it's
    /// stable for the card's lifetime and safe to cache.
    private func resolveReferencesIfNeeded() {
        guard !referenceResolved else { return }
        referenceResolved = true
        referenceCache = session.previousSets(
            exerciseID: workoutExercise.exerciseID,
            excluding: workoutExercise.workout?.id,
            before: mode.isLive ? nil : workoutExercise.workout?.startedAt)
    }

    /// Ghost autofill for a planned slot, computed from the CACHED references (mirrors
    /// `WorkoutSessionStore.ghostValues`) so a planned row never re-runs the full-history
    /// fetch during body — the same fetch-in-body trap `referenceCache` closes.
    private func ghostValues(slot: Int) -> (weightGrams: Int, reps: Int) {
        if slot >= 0 && slot < referenceCache.count {
            return (referenceCache[slot].weightGrams, referenceCache[slot].reps)
        }
        if let last = workoutExercise.orderedSets.last {
            return (last.weightGrams, last.reps)
        }
        if let reference = referenceCache.last {
            return (reference.weightGrams, reference.reps)
        }
        return (0, 10)
    }

    /// Each logged set paired with last week's set at the same working-set ordinal,
    /// plus its badge label — the working-set number, or "W" for a warm-up.
    private var setPairs: [(set: SetEntry, reference: SetEntry?, label: String)] {
        let refs = referenceSets
        var working = 0
        return workoutExercise.orderedSets.map { set in
            if set.isWarmup { return (set, nil, "W") }
            let ref = working < refs.count ? refs[working] : nil
            working += 1
            return (set, ref, "\(working)")
        }
    }

    private var workingLoggedCount: Int { workoutExercise.orderedSets.filter { !$0.isWarmup }.count }
    /// A finished workout has no plan left to run — its sets ARE the record.
    private var plannedWorking: Int { mode.isLive ? session.plannedSetCount(for: workoutExercise) : 0 }

    /// Every planned working set is logged (only meaningful when there IS a plan).
    private var planComplete: Bool { plannedWorking > 0 && workingLoggedCount >= plannedWorking }

    /// The exercise is underway — a set is logged, or the lifter tapped its first
    /// planned row to begin. Until then the whole plan reads as PLANNED (no armed check).
    private var isStarted: Bool { workingLoggedCount > 0 || hasBegun }

    /// Live: add one set to the session plan on the fly — when the plan was already met
    /// this reopens the active input row, otherwise it appends another placeholder.
    /// Review: append a forgotten set after the last one, ghosting its numbers so the
    /// correction starts from something plausible instead of zero.
    private var addSetButton: some View {
        Button {
            if mode.isLive {
                withAnimation(.snappy) { session.addPlannedSet(to: workoutExercise) }
            } else {
                mutate { session.appendSet(to: workoutExercise) }
            }
        } label: {
            Label("Add set", systemImage: "plus")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(0.5)
                .foregroundStyle(SettColor.heroCyan)
                .frame(maxWidth: .infinity)
                .frame(height: SetRowGrid.rowHeight)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettColor.heroCyan.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.isLive ? "Add another set" : "Add set")
        .accessibilityHint(mode.isLive ? "" : "Appends a set copying the last set's weight and reps")
    }

    /// Working-set ordinals STILL planned after the active next-set input (which covers
    /// ordinal `workingLoggedCount`). Empty for a quick-start (no plan), once the plan
    /// is met, or in review — the whole plan is shown from the start, not one at a time.
    private var pendingSlots: [Int] {
        guard mode.isLive else { return [] }
        guard isStarted else {
            // Not started: the whole plan shows as planned; slot 0 is the "begin" row.
            return Array(0 ..< max(1, plannedWorking))
        }
        let start = workingLoggedCount + 1
        guard plannedWorking > start else { return [] }
        return Array(start ..< plannedWorking)
    }

    // MARK: Effective output + per-set scoring (matches the scouter's green→amber→red)

    private func e1RM(_ set: SetEntry) -> Int {
        let eff = LoadMath.effectiveWeightGrams(
            addedGrams: set.weightGrams, equipment: workoutExercise.equipment,
            bodyweightGrams: workoutExercise.workout?.bodyweightGrams)
        return ProgressEngine.e1RMGrams(weightGrams: eff, reps: set.reps)
    }
    private func pwr(_ set: SetEntry) -> Int { Int(Units.pounds(fromGrams: e1RM(set)).rounded()) }

    /// This set's outcome tier vs last week — reusing the real classifier so a row's
    /// colour is the SAME green/amber/red the scouter showed when it was logged.
    private func setTier(_ set: SetEntry, reference: SetEntry?) -> AuraTier {
        if set.isWarmup { return .calm }
        guard let reference else { return .base }
        let e = e1RM(set), r = e1RM(reference)
        let preview = SetReadback(weightDeltaGrams: nil, repsDelta: nil, isBaseline: false,
                                  e1RMGrams: e, referenceE1RMGrams: r,
                                  e1RMDeltaGrams: e - r, isPersonalBest: false)
        return LogOutcome.classify(readback: preview, phase: phase,
                                   isWarmup: false, isCasual: false).auraTier
    }

    /// Rank the tiers so the card rim + top-PWR read the exercise's BEST set.
    private static let tierRank: [AuraTier] = [.fatigued, .calm, .base, .defended, .ascended, .radiant]
    private var topTier: AuraTier {
        setPairs.filter { !$0.set.isWarmup }
            .map { setTier($0.set, reference: $0.reference) }
            .max { (Self.tierRank.firstIndex(of: $0) ?? 0) < (Self.tierRank.firstIndex(of: $1) ?? 0) } ?? .base
    }
    private var topPwr: Int {
        workoutExercise.orderedSets.filter { !$0.isWarmup }.map { pwr($0) }.max() ?? 0
    }

    // MARK: Header — scouter language (equipment icon + mono name + top-PWR)

    private var header: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                ExerciseIcon(name: workoutExercise.exerciseNameSnapshot,
                             equipment: workoutExercise.equipment,
                             muscle: workoutExercise.muscle,
                             size: 44, color: topTier.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workoutExercise.exerciseNameSnapshot.uppercased())
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(statLine)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Collapses this exercise" : "Expands this exercise")
        // Mid-session escape hatches: swap the lift (machine taken) or drop a
        // mistaken pick entirely. The shell's cursor reconciler absorbs both.
        // Live only — a sealed workout's exercise list is the record.
        .contextMenu {
            if mode.isLive {
                Button {
                    isReplacing = true
                } label: { Label("Replace exercise", systemImage: "arrow.triangle.2.circlepath") }
                Button(role: .destructive) {
                    if workoutExercise.orderedSets.isEmpty {
                        session.removeExercise(workoutExercise)
                    } else {
                        isConfirmingRemove = true
                    }
                } label: { Label("Remove exercise", systemImage: "trash") }
            }
        }
        .sheet(isPresented: $isReplacing) {
            RoutineExercisePickerSheet(allowsMultiple: false, title: "Replace Exercise") { exercise in
                // Add THEN remove, so the workout never passes through an empty state.
                session.addExercise(exercise)
                session.removeExercise(workoutExercise)
            }
        }
        .confirmationDialog("Remove \(workoutExercise.exerciseNameSnapshot)?",
                            isPresented: $isConfirmingRemove,
                            titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) {
                session.removeExercise(workoutExercise)
            }
            Button("Keep exercise", role: .cancel) {}
        } message: {
            Text("Its logged sets will be deleted from this session.")
        }
    }

    private var statLine: String {
        let working = workoutExercise.orderedSets.filter { !$0.isWarmup }
        // Before any working set is logged, surface the queued plan ("3 PLANNED") rather
        // than the empty "0 SETS" — forward pull, matching the START/PLANNED row labels.
        if working.isEmpty && plannedWorking > 0 { return "\(plannedWorking) PLANNED" }
        var parts = ["\(working.count) SET\(working.count == 1 ? "" : "S")"]
        if topPwr > 0 { parts.append("TOP \(topPwr) PWR") }
        // Banked volume this session — "how much work have I done" at a glance.
        let volGrams = working.reduce(0) { $0 + $1.weightGrams * $1.reps }
        if volGrams > 0 {
            let vol = Int((Double(volGrams) / unit.gramsPerUnit).rounded())
            parts.append("\(vol.formatted()) \(unit.symbol.uppercased())")
        }
        return parts.joined(separator: " · ")
    }

    // (Card chrome is the shared ambient .hudCard — the hand-rolled near-twin
    // retired with F71; its faint extra glow was the only casualty.)

    // MARK: Machine setup (Exercise.instructions — what do I set the machine to)

    /// Ash mono caption under the name while a setup exists; a quiet ghost
    /// "Add setup" when empty. Shown for EVERY exercise — a free-weight lift has a
    /// setup worth noting too (bench angle, grip width, pin height, cable position).
    @ViewBuilder
    private var machineSetupRow: some View {
        if let exercise {
            if let setup = exercise.instructions, !setup.isEmpty {
                Button {
                    setupTarget = exercise
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.caption2)
                        Text(setup)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(SettColor.ash)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Setup: \(setup)")
                .accessibilityHint("Edits the setup")
            } else {
                Button {
                    setupTarget = exercise
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.caption2)
                        Text("Add setup")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(SettColor.iron)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add setup")
            }
        }
    }

    // MARK: Set row — a scouter reading per logged set

    /// A committed set rendered in the scouter language: a tier-coloured index badge +
    /// a left accent bar, the lift, its PWR, and the vs-last delta (▲/◇/▼). Tap fixes
    /// the values; a note button opens the note (its text reads as a sub-line below);
    /// long-press fixes the values or deletes.
    private func setRow(set: SetEntry, reference: SetEntry?, label: String) -> some View {
        let tier = setTier(set, reference: reference)
        let delta = (set.isWarmup || reference == nil) ? nil : pwr(set) - pwr(reference!)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let note = set.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(spacing: 0) {
            Button {
                // The toolbox's job is CORRECTING — tap fixes the values. A read-only
                // review row is a record, not a control.
                guard mode.isEditable else { return }
                editingValues = set
            } label: {
                HStack(spacing: 0) {
                    SetIndexBadge(label: label, charge: set.isWarmup ? .warmup : .earned(tier))
                    Spacer().frame(width: SetRowGrid.badgeGap)
                    setValueColumns(weightText: WeightFormat.compactWithUnit(grams: set.weightGrams, unit: unit),
                                    repsText: "\(set.reps)", valueColor: SettColor.bone, weight: .bold)
                    Spacer(minLength: 6)
                    // Trailing cluster: the PWR reading + its vs-last trend held as one
                    // unit (6pt), the delta on a steady min-width seat so ▽/▲/▼ never
                    // crowd PWR or jitter the note's x, then a clean 8pt gap to the note.
                    HStack(spacing: 8) {
                        if set.isWarmup {
                            Text("WARM-UP")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .kerning(1)
                                .foregroundStyle(SettColor.ash)
                        } else {
                            HStack(spacing: 6) {
                                Text("PWR \(pwr(set))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(tier.color.opacity(0.9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if let delta, delta != 0 {
                                    Text(deltaLabel(delta, tier: tier))
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(deltaColor(delta, tier: tier))
                                        .frame(minWidth: 28, alignment: .leading)
                                }
                            }
                        }
                        noteButton(for: set, hasNote: !note.isEmpty)
                    }
                }
                .padding(.horizontal, SetRowGrid.hPad)
                .frame(height: SetRowGrid.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(loggedRowLabel(set: set, label: label, tier: tier, delta: delta))
            .accessibilityHint(mode.isEditable
                               ? "Fixes this set's weight and reps. Long-press for note or delete."
                               : "")
            // A read-only review row is a record: don't announce a button that
            // activates to nothing.
            .accessibilityRemoveTraits(mode.isEditable ? [] : [.isButton])

            if !note.isEmpty { noteLine(note, on: set) }
        }
        .background {
            shape.fill(TimeChamber.void.opacity(0.5))
            HStack {
                RoundedRectangle(cornerRadius: 2).fill(tier.color).frame(width: 3)
                Spacer()
            }
            shape.strokeBorder(tier.color.opacity(0.18), lineWidth: 1)
        }
        .contentShape(shape)
        .contextMenu {
            if mode.isEditable {
                Button {
                    editingValues = set
                } label: { Label("Fix weight & reps", systemImage: "pencil") }
                Button {
                    editingSet = set
                } label: { Label(note.isEmpty ? "Add note" : "Edit note", systemImage: "note.text") }
                Button {
                    mutate { session.duplicateSet(set) }
                } label: { Label("Duplicate set", systemImage: "plus.square.on.square") }
                Button(role: .destructive) {
                    // Live logging deletes on the spot; a sealed workout asks first.
                    if mode.isLive { session.deleteSet(set) } else { deletingSet = set }
                } label: { Label("Delete set", systemImage: "trash") }
            }
        }
    }

    /// The note affordance on a logged set — mirrors the active row's note button so
    /// prior sets get notes too. Cyan (with a dot) when a note exists, quiet iron when
    /// empty but still a one-tap add. Its text reads in full on the sub-line below.
    /// A read-only review row carries no controls — the note still reads below it, and
    /// the gutter stays reserved as clear space so PWR lands on the same x in both
    /// modes (the Edit toggle must not slide the column).
    @ViewBuilder
    private func noteButton(for set: SetEntry, hasNote: Bool) -> some View {
        if mode.isEditable {
            noteButtonControl(for: set, hasNote: hasNote)
        } else {
            Color.clear.frame(width: Self.noteGutter, height: 1)
        }
    }

    /// The logged row's note gutter — reserved in EVERY logged row. Local to this row,
    /// not a SetRowGrid column: SetEntryRow's note button is a different width and sits
    /// beside its commit button.
    private static let noteGutter: CGFloat = 22

    private func noteButtonControl(for set: SetEntry, hasNote: Bool) -> some View {
        Button {
            editingSet = set
        } label: {
            Image(systemName: "note.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hasNote ? SettColor.heroCyan : SettColor.iron)
                .frame(width: Self.noteGutter, height: SetRowGrid.rowHeight)
                .overlay(alignment: .topTrailing) {
                    if hasNote {
                        Circle().fill(SettColor.heroCyan).frame(width: 5, height: 5).offset(x: -3, y: 12)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasNote ? "Edit set note" : "Add set note")
    }

    /// The note text under a logged set — readable in full, tappable to edit (a
    /// read-only review row keeps the text and drops the tap).
    @ViewBuilder
    private func noteLine(_ note: String, on set: SetEntry) -> some View {
        if mode.isEditable {
            Button { editingSet = set } label: { noteLineBody(note).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Note: \(note)")
                .accessibilityHint("Edits this set's note")
        } else {
            noteLineBody(note)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Note: \(note)")
        }
    }

    private func noteLineBody(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SettColor.iron)
                .padding(.top, 1)
            Text(note)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SettColor.ash)
                // Live keeps rows scannable at a glance; review is for reading, so a
                // long note wraps in full instead of dying at the ellipsis.
                .lineLimit(mode.isLive ? 1 : nil)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, SetRowGrid.hPad + SetRowGrid.badge + SetRowGrid.badgeGap)
        .padding(.trailing, SetRowGrid.hPad)
        .padding(.bottom, 8)
        .padding(.top, 1)
    }

    /// A still-to-do planned set: a dashed, dimmed placeholder showing the target (the
    /// ghost autofill) so the whole plan is visible from the start. The active input
    /// row above it is where the next set is actually logged.
    /// Whether the planned rows have a real target to show (a last-week reference OR a
    /// working set logged this session). Otherwise the ghost is the bare (0,10)
    /// fallback — render "— × —" rather than a fake plan.
    private var hasTarget: Bool {
        !referenceSets.isEmpty || workoutExercise.orderedSets.contains { !$0.isWarmup }
    }

    /// A dimmed planned set. `canBegin` marks the FIRST row of an unstarted exercise —
    /// it reads "START" and tapping it reveals the active input (go-in-order nudge).
    private func plannedRow(number: Int, slot: Int, canBegin: Bool) -> some View {
        let ghost = ghostValues(slot: slot)
        let weightText = hasTarget ? WeightFormat.compactWithUnit(grams: ghost.weightGrams, unit: unit) : "—"
        let repsText = hasTarget ? "\(ghost.reps)" : "—"
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 0) {
            plannedInfo(number: number, weightText: weightText, repsText: repsText, canBegin: canBegin)
            // Drop a planned set from this session's plan (never touches the routine).
            Button {
                withAnimation(.snappy) { session.removePlannedSet(from: workoutExercise) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SettColor.iron)
                    .padding(.leading, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove a planned set")
        }
        .padding(.horizontal, SetRowGrid.hPad)
        .frame(height: SetRowGrid.rowHeight)
        .background {
            shape.strokeBorder(canBegin ? SettColor.heroCyan.opacity(0.5) : SettColor.cardBorder.opacity(0.7),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    @ViewBuilder
    private func plannedInfo(number: Int, weightText: String, repsText: String, canBegin: Bool) -> some View {
        let content = HStack(spacing: 0) {
            SetIndexBadge(label: "\(number)", charge: .unearned)
            Spacer().frame(width: SetRowGrid.badgeGap)
            // Target numbers in ash (legible), not iron — they're the functional part.
            setValueColumns(weightText: weightText, repsText: repsText,
                            valueColor: SettColor.ash, weight: .semibold)
            Spacer(minLength: 8)
            Text(canBegin ? "START" : "PLANNED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(canBegin ? SettColor.heroCyan : SettColor.iron)
        }
        if canBegin {
            Button {
                withAnimation(.snappy) { hasBegun = true }
                Haptics.selection()
            } label: { content.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Start set \(number), target \(weightText) by \(repsText)")
            .accessibilityHint("Begins this exercise")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hasTarget ? "Planned set \(number), target \(weightText) by \(repsText)"
                                               : "Planned set \(number)")
        }
    }

    /// Spoken VoiceOver label for a logged row — the whole progress signal (PWR, the
    /// vs-last trend, and the outcome tier) that is otherwise colour/glyph-only.
    private func loggedRowLabel(set: SetEntry, label: String, tier: AuraTier, delta: Int?) -> String {
        let base = "Set \(label), \(WeightFormat.compactWithUnit(grams: set.weightGrams, unit: unit)) by \(set.reps)"
        if set.isWarmup { return base + ", warm-up" }
        var parts = [base, "power \(pwr(set))"]
        if tier == .radiant {
            parts.append("personal best")
        } else if let delta {
            if delta > 0 { parts.append("up \(delta) versus last") }
            else if delta < 0 {
                parts.append(phase == .cutting ? "down \(-delta), expected on a cut" : "down \(-delta) versus last")
            } else { parts.append("held versus last") }
        }
        return parts.joined(separator: ", ")
    }

    /// vs-last PWR delta — the SAME glyph + colour the scouter showed (shared VsLast).
    /// Keyed off this set's classified `tier` so a within-band hold reads neutral (not
    /// a red loss) — matching the row's green aura.
    private func deltaLabel(_ d: Int, tier: AuraTier) -> String { VsLast.label(d, phase: phase, tier: tier) }
    private func deltaColor(_ d: Int, tier: AuraTier) -> Color { VsLast.color(d, phase: phase, tier: tier) }

    /// Mutation rules: updatedAt + needsPush + save on the SetEntry itself.
    private func saveNote(_ note: String?, on set: SetEntry) {
        set.notes = note
        set.updatedAt = .now
        set.needsPush = true
        try? modelContext.save()
        Haptics.selection()
    }

}

// MARK: - Swipeable set row (left → delete, right → duplicate)

/// Wraps a LOGGED set row with a custom horizontal swipe — there is no List cell in
/// the card ScrollView to hang `.swipeActions` on. Right-swipe reveals a cyan duplicate
/// icon; left-swipe a red trash. Both icons grow in with the drag. A decisive swipe past
/// `commit` fires; a lighter swipe rests at the `reveal` detent where the icon is a
/// tappable button; tapping the row (or opening another) closes it. Vertical drags bail
/// on the first sample so the ScrollView keeps the pan; taps (translation < 8) reach the
/// row's own tap-to-fix. VoiceOver reaches both actions via the row's contextMenu +
/// accessibility actions, since it can't swipe.
struct SwipeableSetRow<Content: View>: View {
    let rowID: UUID
    @Binding var openRowID: UUID?
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var base: CGFloat = 0
    @State private var axis: Axis?

    private let reveal: CGFloat = 76
    private let commit: CGFloat = 120
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }
    private var isOpen: Bool { openRowID == rowID }
    private var progress: CGFloat { min(1, abs(offset) / reveal) }

    var body: some View {
        ZStack {
            actionTrack
            content()
                .background(TimeChamber.void, in: shape)   // opaque so the track hides when closed
                .overlay {
                    if isOpen {   // tap the row body to close it (its own Fix button is disabled)
                        Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                    }
                }
                .disabled(isOpen)
                .offset(x: offset)
        }
        .clipShape(shape)
        // Simultaneous (not high-priority): a vertical drag bails on the first sample so
        // the ScrollView keeps its pan; only a horizontal drag moves the offset.
        .simultaneousGesture(dragGesture)
        .onChange(of: openRowID) { _, id in
            if id != rowID && offset != 0 { close() }
        }
        .accessibilityAction(named: "Duplicate set") { onDuplicate() }
        .accessibilityAction(named: "Delete set") { onDelete() }
    }

    private var actionTrack: some View {
        HStack(spacing: 0) {
            actionIcon("plus.square.on.square", tint: SettColor.heroCyan, active: offset > 0) { fire(onDuplicate) }
            Spacer(minLength: 0)
            actionIcon("trash", tint: SettColor.negative, active: offset < 0) { fire(onDelete) }
        }
        .padding(.horizontal, 26)
    }

    private func actionIcon(_ name: String, tint: Color, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: name)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .scaleEffect(0.7 + 0.3 * progress)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(active ? progress : 0)
        .allowsHitTesting(isOpen && active)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if axis == nil {
                    base = offset
                    axis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard axis == .horizontal else { return }
                var next = base + value.translation.width
                if abs(next) > reveal {   // rubber-band past the detent
                    let over = abs(next) - reveal
                    next = (next < 0 ? -1 : 1) * (reveal + over * 0.35)
                }
                offset = next
            }
            .onEnded { value in
                defer { axis = nil }
                guard axis == .horizontal else { offset = base; return }
                let final = base + value.translation.width
                if final <= -commit { fire(onDelete) }
                else if final >= commit { fire(onDuplicate) }
                else if final <= -reveal * 0.6 { snapOpen(-reveal) }
                else if final >= reveal * 0.6 { snapOpen(reveal) }
                else { close() }
            }
    }

    private func snapOpen(_ x: CGFloat) {
        openRowID = rowID
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { offset = x }
        Haptics.selection()
    }

    private func close() {
        if openRowID == rowID { openRowID = nil }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { offset = 0 }
    }

    private func fire(_ action: @escaping () -> Void) {
        if openRowID == rowID { openRowID = nil }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { offset = 0 }
        action()   // delete removes the row from orderedSets; duplicate inserts the clone
    }
}

// MARK: - Set values edit sheet (fix a mis-logged weight / reps / warm-up)

/// Compact editor for a committed set's numbers — the escape hatch for a
/// fat-fingered entry. Hands the corrected values back through `onSave`; the store
/// applies them under the sync rules.
struct SetValuesEditSheet: View {
    let set: SetEntry
    let unit: WeightUnit
    let onSave: (_ weightGrams: Int, _ reps: Int, _ isWarmup: Bool) -> Void

    @State private var weightText = ""
    @State private var reps = 0
    @State private var isWarmup = false

    var body: some View {
        ChamberSheet(title: "Fix Set", onCommit: save) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEIGHT (\(unit.symbol))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(SettColor.bone)
                        .padding(10)
                        .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("REPS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                    // The session's ± flank grammar, not a stock Stepper.
                    ChamberStepper(value: $reps, in: 0...999)
                }
            }
            Toggle(isOn: $isWarmup) {
                Text("WARM-UP")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.ash)
            }
            .tint(TimeChamber.teal)
        }
        .presentationDetents([.height(300)])
        .onAppear {
            weightText = WeightFormat.compact(grams: set.weightGrams, unit: unit)
            reps = set.reps
            isWarmup = set.isWarmup
        }
    }

    private func save() {
        let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        onSave(Units.grams(fromDisplay: max(0, value), unit: unit), max(0, reps), isWarmup)
        Haptics.selection()
    }
}

// MARK: - Machine setup sheet (THE one editor — Session card + Train detail)

/// Compact editor for the machine setup. `Exercise.instructions` IS the
/// machine-setup field app-wide (no schema change); saving mutates it under the
/// standard sync rules (updatedAt + needsPush + save). Save trims whitespace and
/// stores nil for empty text.
struct MachineSetupSheet: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ChamberSheet(title: "Machine Setup", onCommit: save) {
            TextField("seat 4 · back 3 · pin 8", text: $text)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(SettColor.bone)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(12)
                .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .presentationDetents([.height(220)])
        .onAppear {
            text = exercise.instructions ?? ""
            isFocused = true
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.instructions = trimmed.isEmpty ? nil : trimmed
        exercise.updatedAt = .now
        exercise.needsPush = true
        try? modelContext.save()
        Haptics.selection()
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
