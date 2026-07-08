import SwiftUI
import SettCore

/// SET state of the Set Player (v3.1): one set fills the screen. Upper third names
/// the exercise (mono small-caps ash), `SET n / m` (iron) and the machine-setup line;
/// the center is the numbers, huge — weight × reps in the app's largest mono numerals
/// (bone once edited or committed, iron ghost otherwise); the bottom is the LOG slab.
///
/// Incognito: everything sits on pure black. The only cyan is the slab's hairline
/// flash on LOG; the only gold is a 0.4 s numeral flash when the set beats reference.
/// Adjustments are reachable, never visible by default: tap a numeral for a stepper
/// capsule (auto-hides after 4 s), long-press for the numeric pad.
struct SetPlayerView: View {
    let workoutExercise: WorkoutExercise
    let slotIndex: Int
    let slotCount: Int
    /// Called after a successful commit; the shell owns the REST/advance transition.
    let onLogged: (_ beatReference: Bool) -> Void

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    /// Injected by ActiveWorkoutView (`.environment(combatText)`); optional so the
    /// pane still renders outside an active-session context (previews).
    @Environment(CombatTextEmitter.self) private var combatText: CombatTextEmitter?

    @State private var weightGrams = 0
    @State private var reps = 0
    @State private var isGhost = true
    @State private var isWarmup = false
    /// Note staged for the commit — travels into `logSet` with the slab press.
    @State private var pendingNote: String?
    @State private var isEditingNote = false
    /// Stepper capsule under one numeral; nil = the happy path (numbers + slab only).
    @State private var activeStepper: NumericField?
    @State private var stepperHideTask: Task<Void, Never>?
    @State private var padField: NumericField?
    /// 0.4 s gold flash on the numerals when the logged set beat its reference.
    @State private var goldFlash = false
    /// Exercise row behind the loose `exerciseID` — carries the machine setup.
    @State private var exercise: Exercise?

    /// The app's largest numeral — the one fixed-size exception granted to the player.
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 24)
            Spacer(minLength: 12)
            numerals
            Spacer(minLength: 12)
            chipsRow
                .padding(.bottom, 14)
            slab
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { load() }
        .onDisappear { stepperHideTask?.cancel() }
        .sheet(item: $padField) { field in
            numericPad(for: field)
        }
        .sheet(isPresented: $isEditingNote) {
            SetNoteSheet(initialText: pendingNote ?? "") { pendingNote = $0 }
        }
    }

    // MARK: Slot state

    /// Non-nil when this slot was already committed (the user swiped back to it).
    private var committedSet: SetEntry? {
        let sets = workoutExercise.orderedSets
        guard slotIndex >= 0 && slotIndex < sets.count else { return nil }
        return sets[slotIndex]
    }

    private var displayedWeightGrams: Int { committedSet?.weightGrams ?? weightGrams }
    private var displayedReps: Int { committedSet?.reps ?? reps }

    private func load() {
        if exercise == nil {
            exercise = session.fetchExercise(id: workoutExercise.exerciseID)
        }
        guard committedSet == nil else { return }
        let ghost = session.ghostValues(for: workoutExercise, slot: slotIndex)
        weightGrams = ghost.weightGrams
        reps = ghost.reps
        isGhost = true
    }

    // MARK: Header (upper third — mono small-caps ash · SET n/m iron · setup line)

    private var header: some View {
        VStack(spacing: 10) {
            Text(workoutExercise.exerciseNameSnapshot.uppercased())
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .kerning(2)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("SET \(slotIndex + 1) / \(slotCount)")
                .font(.system(.caption, design: .monospaced))
                .kerning(2)
                .foregroundStyle(SettColor.iron)
            if let setup = exercise?.instructions, !setup.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption2)
                    Text(setup)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(SettColor.ash)
                .accessibilityLabel("Machine setup: \(setup)")
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: The numbers, huge

    private var numeralColor: Color {
        if goldFlash { return SettColor.saiyanGold }
        if committedSet != nil || !isGhost { return SettColor.bone }
        return SettColor.iron
    }

    private var numerals: some View {
        HStack(alignment: .top, spacing: 12) {
            numeralColumn(text: WeightFormat.compact(grams: displayedWeightGrams,
                                                     unit: services.settings.unit),
                          caption: services.settings.unit.symbol,
                          field: .weight,
                          accessibility: "Weight")
            Text("×")
                .font(.system(size: numeralSize * 0.45, weight: .heavy, design: .monospaced))
                .foregroundStyle(SettColor.iron)
                .padding(.top, numeralSize * 0.28)
                .accessibilityHidden(true)
            numeralColumn(text: "\(displayedReps)",
                          caption: "reps",
                          field: .reps,
                          accessibility: "Reps")
        }
        .padding(.horizontal, 20)
    }

    private func numeralColumn(text: String, caption: String,
                               field: NumericField, accessibility: String) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: numeralSize, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(numeralColor)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard committedSet == nil else { return }
                    showStepper(for: field)
                }
                .onLongPressGesture(minimumDuration: 0.4) {
                    guard committedSet == nil else { return }
                    stepperHideTask?.cancel()
                    activeStepper = nil
                    padField = field
                }
            Text(caption)
                .font(.system(.caption, design: .monospaced))
                .kerning(2)
                .foregroundStyle(SettColor.iron)
            if activeStepper == field {
                stepperCapsule(for: field)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibility) \(text)")
        .accessibilityHint(committedSet == nil ? "Tap to adjust, long press for keypad" : "")
    }

    // MARK: Adjust (stepper capsule — materializes beneath, auto-hides after 4 s)

    private func showStepper(for field: NumericField) {
        withAnimation(.snappy(duration: 0.18)) { activeStepper = field }
        Haptics.selection()
        scheduleStepperAutoHide()
    }

    private func scheduleStepperAutoHide() {
        stepperHideTask?.cancel()
        stepperHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { activeStepper = nil }
        }
    }

    private func stepperCapsule(for field: NumericField) -> some View {
        HStack(spacing: 0) {
            stepButton("minus") { step(field, -1) }
            Rectangle()
                .fill(SettColor.cardBorder)
                .frame(width: 1, height: 20)
            stepButton("plus") { step(field, 1) }
        }
        .background {
            ZStack {
                Capsule().fill(Color.black)
                Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1)
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(SettColor.bone)
                .frame(width: 56, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "minus" ? "Decrease" : "Increase")
    }

    private func step(_ field: NumericField, _ direction: Int) {
        switch field {
        case .weight:
            weightGrams = max(0, weightGrams + direction * services.settings.incrementGrams)
        case .reps:
            reps = max(0, reps + direction)
        }
        isGhost = false
        Haptics.selection()
        scheduleStepperAutoHide()
    }

    // MARK: Numeric pad (long-press — shared NumericPadSheet)

    private func numericPad(for field: NumericField) -> some View {
        let unit = services.settings.unit
        switch field {
        case .weight:
            return NumericPadSheet(
                title: "Weight (\(unit.symbol))",
                initialText: WeightFormat.compact(grams: weightGrams, unit: unit),
                keyboard: .decimalPad
            ) { text in
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                      value >= 0 else { return }
                weightGrams = Units.grams(fromDisplay: value, unit: unit)
                isGhost = false
            }
        case .reps:
            return NumericPadSheet(
                title: "Reps",
                initialText: "\(reps)",
                keyboard: .numberPad
            ) { text in
                guard let value = Int(text), value >= 0 else { return }
                reps = value
                isGhost = false
            }
        }
    }

    // MARK: W chip + note icon (small, above the slab — open slots only)

    @ViewBuilder
    private var chipsRow: some View {
        if committedSet == nil {
            HStack(spacing: 20) {
                Button {
                    isWarmup.toggle()
                    Haptics.selection()
                } label: {
                    Text("W")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isWarmup ? SettColor.heroCyan.opacity(0.6) : SettColor.iron)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle().strokeBorder(
                                isWarmup ? SettColor.heroCyan.opacity(0.4) : SettColor.cardBorder,
                                lineWidth: 1
                            )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isWarmup ? "Warmup set, on" : "Warmup set, off")

                Button {
                    isEditingNote = true
                } label: {
                    Image(systemName: "note.text")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(hasPendingNote ? SettColor.bone : SettColor.iron)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle().strokeBorder(SettColor.cardBorder, lineWidth: 1)
                        }
                        .contentShape(Circle())
                        .overlay(alignment: .topTrailing) {
                            if hasPendingNote {
                                Circle()
                                    .fill(SettColor.bone)
                                    .frame(width: 5, height: 5)
                                    .offset(x: -3, y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasPendingNote ? "Edit set note" : "Add set note")
            }
        }
    }

    private var hasPendingNote: Bool {
        pendingNote?.isEmpty == false
    }

    // MARK: The LOG slab

    @ViewBuilder
    private var slab: some View {
        if committedSet != nil {
            PlayerSlab(title: "LOGGED", flashesCyan: false, isEnabled: false) {}
        } else {
            PlayerSlab(title: "LOG SET", isEnabled: reps > 0) { log() }
        }
    }

    /// Commit the visible values. Crit when this set's weight beats the reference set
    /// at the index it lands on — the same rule as the overview's chips. Celebration
    /// plays AFTER the write; the shell holds the REST transition for the gold flash.
    private func log() {
        let index = workoutExercise.orderedSets.count
        let references = session.previousSets(exerciseID: workoutExercise.exerciseID,
                                              excluding: workoutExercise.workout?.id)
        let beatReference = index < references.count && weightGrams > references[index].weightGrams

        session.logSet(on: workoutExercise, weightGrams: weightGrams, reps: reps,
                       isWarmup: isWarmup, notes: pendingNote)
        pendingNote = nil
        stepperHideTask?.cancel()
        activeStepper = nil

        // Floating combat text: +N PWR, N = this set's volume load in whole pounds.
        let volumeLb = Int(Units.pounds(fromGrams: weightGrams * reps).rounded())
        combatText?.emit("+\(volumeLb.formatted()) PWR", crit: beatReference)
        if beatReference {
            Haptics.prSignature()
            goldFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeOut(duration: 0.2)) { goldFlash = false }
            }
        }
        onLogged(beatReference)
    }
}

// MARK: - PlayerSlab (LOG SET · END READING · ADD EXERCISE)

/// The full-width ≥96 pt commit slab: mono label on a monochrome etched capsule
/// (outer iron hairline, inner near-black groove — no gold, this is incognito).
/// Pressing flashes the session's only sanctioned cyan (a brief hairline) and runs
/// `action` immediately — input latency is sacred, celebration is the caller's job.
struct PlayerSlab: View {
    let title: String
    var flashesCyan = true
    var isEnabled = true
    let action: () -> Void

    @State private var flashOpacity: Double = 0

    var body: some View {
        Button {
            if flashesCyan {
                flashOpacity = 1
                withAnimation(.easeOut(duration: 0.4)) { flashOpacity = 0 }
            }
            action()
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .kerning(4)
                .foregroundStyle(isEnabled ? SettColor.bone : SettColor.iron)
                .frame(maxWidth: .infinity, minHeight: 96)
                .background {
                    ZStack {
                        Capsule().fill(Color.black)
                        Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1)
                        Capsule().strokeBorder(SettColor.etch, lineWidth: 1).padding(2)
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(SettColor.heroCyan, lineWidth: 1)
                        .opacity(flashOpacity)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title.capitalized)
    }
}
