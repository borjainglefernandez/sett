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
    /// Carries the classified outcome so the shell can tint the transition.
    let onLogged: (_ outcome: LogOutcome) -> Void

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var isEditingSetup = false

    // Scanner acquisition (item 3b): a ~350 ms scanline sweep + digit scramble on
    // every new slot. `acquiring` gates the scramble; `scanProgress` drives the
    // sweep (0 → 1). Reduce Motion direct-sets both to the settled state.
    @State private var acquiring = false
    @State private var acquireFrame = 0
    @State private var scanProgress: CGFloat = 1
    @State private var acquireTask: Task<Void, Never>?

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
        .onAppear { load(); startAcquisition() }
        .onDisappear { stepperHideTask?.cancel(); acquireTask?.cancel() }
        .sheet(item: $padField) { field in
            numericPad(for: field)
        }
        .sheet(isPresented: $isEditingNote) {
            SetNoteSheet(initialText: pendingNote ?? "") { pendingNote = $0 }
        }
        .sheet(isPresented: $isEditingSetup) {
            if let exercise { MachineSetupSheet(exercise: exercise) }
        }
    }

    // MARK: Acquisition (item 3b — scanline sweep + deterministic digit scramble)

    /// Seed derived from exercise + slot so the scramble is deterministic per slot.
    private var acquireSeed: UInt64 {
        let base = UInt64(bitPattern: Int64(workoutExercise.exerciseID.hashValue))
        return base &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(slotIndex + 1))
    }

    private func startAcquisition() {
        acquireTask?.cancel()
        guard !reduceMotion else {
            acquiring = false
            scanProgress = 1
            return
        }
        acquiring = true
        acquireFrame = 0
        scanProgress = 0
        withAnimation(.linear(duration: 0.35)) { scanProgress = 1 }
        acquireTask = Task { @MainActor in
            // ~7 scramble frames across 350 ms (50 ms cadence), then settle.
            for step in 1 ... 7 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                acquireFrame = step
            }
            guard !Task.isCancelled else { return }
            acquiring = false
        }
    }

    /// During acquisition, replace each digit of `text` with a seeded pseudo-random
    /// digit (Knuth LCG, re-seeded per frame + position); non-digits pass through.
    private func scanned(_ text: String, salt: UInt64) -> String {
        guard acquiring else { return text }
        var state = acquireSeed &+ salt &+ UInt64(acquireFrame + 1) &* 0x9E37_79B9_7F4A_7C15
        var out = ""
        for character in text {
            if character.isNumber {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                out += String((state >> 33) % 10)
            } else {
                out += String(character)
            }
        }
        return out
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
            Text("TARGET ACQUIRED")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.iron)
                .accessibilityHidden(true)
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
            machineSetup
        }
        .padding(.horizontal, 24)
    }

    // MARK: Machine setup (item 2 — in-session access to the setup line)

    @ViewBuilder
    private var machineSetup: some View {
        if let setup = exercise?.instructions, !setup.isEmpty {
            Button {
                isEditingSetup = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption2)
                    Text(setup)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(SettColor.ash)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Machine setup: \(setup)")
            .accessibilityHint("Tap to edit")
        } else if let equipment = exercise?.equipment, equipment == .machine || equipment == .cable {
            Button {
                isEditingSetup = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.caption2)
                    Text("SETUP")
                        .font(.system(.caption, design: .monospaced))
                        .kerning(2)
                }
                .foregroundStyle(SettColor.iron)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add machine setup")
        }
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
                          salt: 0x11,
                          accessibility: "Weight")
            Text("×")
                .font(.system(size: numeralSize * 0.45, weight: .heavy, design: .monospaced))
                .foregroundStyle(SettColor.iron)
                .padding(.top, numeralSize * 0.28)
                .accessibilityHidden(true)
            numeralColumn(text: "\(displayedReps)",
                          caption: "reps",
                          field: .reps,
                          salt: 0x77,
                          accessibility: "Reps")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay {
            // (3a) targeting reticle framing the numeral block.
            CornerReticle(arm: 18)
                .stroke(SettColor.iron, lineWidth: 1.5)
                .padding(4)
                .accessibilityHidden(true)
        }
        .overlay {
            // (3b) a 1 pt bone scanline sweeping the block during acquisition.
            if acquiring {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(SettColor.bone)
                        .frame(height: 1)
                        .offset(y: scanProgress * proxy.size.height)
                        .opacity(0.8)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func numeralColumn(text: String, caption: String,
                               field: NumericField, salt: UInt64,
                               accessibility: String) -> some View {
        VStack(spacing: 8) {
            Text(scanned(text, salt: salt))
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
                    Text("WARM-UP")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(isWarmup ? SettColor.heroCyan.opacity(0.7) : SettColor.ash)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background {
                            Capsule().strokeBorder(
                                isWarmup ? SettColor.heroCyan.opacity(0.45) : SettColor.cardBorder,
                                lineWidth: 1
                            )
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isWarmup ? "Warm-up set, on" : "Warm-up set, off")

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
        // Reference deltas + outcome, resolved BEFORE logging so the slot index
        // still points at this set. Casual workouts never crit and suppress deltas.
        let index = workoutExercise.orderedSets.count
        let isCasual = session.activeWorkout?.isCasual ?? false
        let readback = session.readback(for: workoutExercise, slot: index,
                                        weightGrams: weightGrams, reps: reps)
        let outcome = LogOutcome.classify(readback: readback,
                                          isWarmup: isWarmup, isCasual: isCasual)

        session.logSet(on: workoutExercise, weightGrams: weightGrams, reps: reps,
                       isWarmup: isWarmup, notes: pendingNote)
        pendingNote = nil
        stepperHideTask?.cancel()
        activeStepper = nil

        // Scanner message (item 5): deterministic pick keyed by the running logged
        // set count (this set now included) — no randomness APIs.
        let loggedSetCount = session.activeWorkout?.orderedExercises
            .reduce(0) { $0 + $1.orderedSets.count } ?? 0
        let message = ScannerMessages.line(for: outcome, loggedSetCount: loggedSetCount)
        session.lastReadback = LoggedReadback(weightGrams: weightGrams, reps: reps,
                                              readback: readback, outcome: outcome,
                                              message: message)

        // Floating combat text: +N PWR, N = this set's volume load in whole pounds.
        // Crit only when the weight beat the reference and the set isn't off the record.
        let volumeLb = Int(Units.pounds(fromGrams: weightGrams * reps).rounded())
        combatText?.emit("+\(volumeLb.formatted()) PWR", crit: outcome.isCrit)
        if outcome.isCrit {
            Haptics.prSignature()
            goldFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeOut(duration: 0.2)) { goldFlash = false }
            }
        }
        onLogged(outcome)
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
