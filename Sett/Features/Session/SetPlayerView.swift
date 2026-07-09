import SwiftUI
import SettCore

/// SET state of the Set Player — the logging scanner, rebuilt as a Time Chamber
/// scouter. One set fills the screen: the exercise name and SET n/m up top; the
/// center is a SCOUTER CORE — huge weight × reps numerals inside a living aura
/// ring whose colour is a live reading of how this set scores against last time
/// (cyan = holding, gold = ascending/beat, white-gold = a new ceiling, indigo =
/// down); beneath, a readable SCOUTER LOG showing the machine setting and note
/// (both auto-populated from the previous session); then the LOG slab.
///
/// The number stays sacred — input latency first, spectacle around it. On LOG the
/// aura BURSTS (the power-up) and the shell fires the full transformation.
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
    /// Note + setting staged for the commit — travel into `logSet` with the slab
    /// press. Both auto-populate from the previous session on load.
    @State private var pendingNote: String?
    @State private var pendingSetting: String?
    @State private var isEditingNote = false
    @State private var isEditingSetting = false
    /// Stepper capsule under one numeral; nil = the happy path (numbers + slab only).
    @State private var activeStepper: NumericField?
    @State private var stepperHideTask: Task<Void, Never>?
    @State private var padField: NumericField?
    /// 0.4 s gold flash on the numerals when the logged set beat its reference.
    @State private var goldFlash = false
    /// Exercise row behind the loose `exerciseID` — the setting default source.
    @State private var exercise: Exercise?
    /// Previous session's reading at this slot (values + note + setting + prior best).
    @State private var reference: WorkoutSessionStore.SlotReference?
    /// Bumped on log so the aura ring flares (the power-up).
    @State private var burstToken = 0

    // Scanner acquisition (item 3b): a ~350 ms scanline sweep + digit scramble on
    // every new slot. `acquiring` gates the scramble; `scanProgress` drives the
    // sweep (0 → 1). Reduce Motion direct-sets both to the settled state.
    @State private var acquiring = false
    @State private var acquireFrame = 0
    @State private var scanProgress: CGFloat = 1
    @State private var acquireTask: Task<Void, Never>?

    /// The app's largest numeral — the one fixed-size exception granted to the player.
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 22)
            Spacer(minLength: 8)
            scouterCore
            Spacer(minLength: 8)
            readout
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            chipsRow
                .padding(.bottom, 12)
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
        .sheet(isPresented: $isEditingSetting) {
            SetNoteSheet(initialText: pendingSetting ?? "",
                         title: "MACHINE SETTING",
                         placeholder: "seat 5 · rope · pin 9") { pendingSetting = $0 }
        }
    }

    // MARK: Live aura reading (the transformation preview)

    /// The aura tier for the CURRENT input, scored against last session's set at
    /// this slot and the all-time prior best — computed in-memory from the cached
    /// `reference`, so it updates instantly as the numbers change (no DB fetch).
    private var liveTier: AuraTier {
        if isWarmup { return .calm }
        guard let ref = reference else { return .base }
        let e1RM = ProgressEngine.e1RMGrams(weightGrams: displayedWeightGrams, reps: displayedReps)
        if ref.priorBestE1RMGrams > 0, e1RM > ref.priorBestE1RMGrams { return .radiant }
        guard ref.hasReference, let rw = ref.weightGrams, let rr = ref.reps else { return .base }
        let refE1RM = ProgressEngine.e1RMGrams(weightGrams: rw, reps: rr)
        let delta = e1RM - refE1RM
        if delta > 0 { return .ascended }
        if delta == 0 { return .base }
        return .fatigued
    }

    // MARK: Acquisition (scanline sweep + deterministic digit scramble)

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
            for step in 1 ... 7 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                acquireFrame = step
            }
            guard !Task.isCancelled else { return }
            acquiring = false
        }
    }

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

    private var committedSet: SetEntry? {
        let sets = workoutExercise.orderedSets
        guard slotIndex >= 0 && slotIndex < sets.count else { return nil }
        return sets[slotIndex]
    }

    private var displayedWeightGrams: Int { committedSet?.weightGrams ?? weightGrams }
    private var displayedReps: Int { committedSet?.reps ?? reps }
    private var isCommitted: Bool { committedSet != nil }

    private func load() {
        if exercise == nil {
            exercise = session.fetchExercise(id: workoutExercise.exerciseID)
        }
        if let committed = committedSet {
            // Committed slot: reflect what was actually logged (read-only).
            pendingNote = committed.notes
            pendingSetting = committed.setting
            return
        }
        let ref = session.slotReference(for: workoutExercise, slot: slotIndex)
        reference = ref
        let ghost = session.ghostValues(for: workoutExercise, slot: slotIndex)
        weightGrams = ghost.weightGrams
        reps = ghost.reps
        isGhost = true
        // Auto-populate from the previous session: the note carries over, and the
        // setting defaults to last session's setting, then the exercise default.
        pendingNote = ref.note
        pendingSetting = ref.setting ?? exercise?.instructions
    }

    // MARK: Header (exercise · SET n/m)

    private var header: some View {
        VStack(spacing: 8) {
            Text("TARGET ACQUIRED")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(liveTier.color.opacity(0.8))
                .accessibilityHidden(true)
            Text(workoutExercise.exerciseNameSnapshot.uppercased())
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .kerning(2)
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("SET \(slotIndex + 1) / \(slotCount)")
                .font(.system(.caption, design: .monospaced))
                .kerning(2)
                .foregroundStyle(SettColor.ash)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Scouter core (numerals inside the living aura ring)

    /// Numbers are always bright bone (legible over the nebula); a ghost (not-yet-
    /// edited) reading is dimmed via opacity rather than a murky colour.
    private var numeralColor: Color {
        goldFlash ? SettColor.saiyanGold : SettColor.bone
    }

    private var numeralOpacity: Double {
        (isGhost && !isCommitted) ? 0.72 : 1
    }

    private var scouterCore: some View {
        ZStack {
            // Soft dark well so the numerals always read over the busy nebula,
            // while the colourful void still glows outside the ring.
            Circle()
                .fill(RadialGradient(colors: [TimeChamber.void.opacity(0.6), .clear],
                                     center: .center, startRadius: 0, endRadius: 155))
                .frame(width: 320, height: 320)
            AuraRing(tier: isCommitted ? .base : liveTier, burstToken: burstToken)
                .frame(width: 300, height: 300)
                .animation(.easeInOut(duration: 0.35), value: liveTier)
            numerals
        }
        .frame(height: 320)
    }

    private var numerals: some View {
        HStack(alignment: .top, spacing: 10) {
            numeralColumn(text: WeightFormat.compact(grams: displayedWeightGrams,
                                                     unit: services.settings.unit),
                          caption: services.settings.unit.symbol,
                          field: .weight,
                          salt: 0x11,
                          accessibility: "Weight")
            Text("×")
                .font(.system(size: numeralSize * 0.42, weight: .heavy, design: .monospaced))
                .foregroundStyle(SettColor.ash)
                .padding(.top, numeralSize * 0.28)
                .accessibilityHidden(true)
            numeralColumn(text: "\(displayedReps)",
                          caption: "reps",
                          field: .reps,
                          salt: 0x77,
                          accessibility: "Reps")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .overlay {
            CornerReticle(arm: 16)
                .stroke(liveTier.color.opacity(0.55), lineWidth: 1.5)
                .padding(2)
                .accessibilityHidden(true)
        }
        .overlay {
            if acquiring {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(liveTier.secondary)
                        .frame(height: 1.5)
                        .offset(y: scanProgress * proxy.size.height)
                        .opacity(0.85)
                        .shadow(color: liveTier.color, radius: 4)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 280)
    }

    private func numeralColumn(text: String, caption: String,
                               field: NumericField, salt: UInt64,
                               accessibility: String) -> some View {
        VStack(spacing: 6) {
            Text(scanned(text, salt: salt))
                .font(.system(size: numeralSize, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(numeralColor)
                .opacity(numeralOpacity)
                .shadow(color: goldFlash ? SettColor.saiyanGold.opacity(0.7) : .black.opacity(0.75),
                        radius: goldFlash ? 12 : 8)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isCommitted else { return }
                    showStepper(for: field)
                }
                .onLongPressGesture(minimumDuration: 0.4) {
                    guard !isCommitted else { return }
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
        .accessibilityHint(isCommitted ? "" : "Tap to adjust, long press for keypad")
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
                Capsule().fill(TimeChamber.void.opacity(0.85))
                Capsule().strokeBorder(liveTier.color.opacity(0.5), lineWidth: 1)
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

    // MARK: Scouter log (readable setting + note — auto-populated from last session)

    @ViewBuilder
    private var readout: some View {
        if showsSetting || hasNote || !isCommitted {
            VStack(spacing: 0) {
                if showsSetting {
                    readoutRow(icon: "gearshape.fill",
                               label: "SETTING",
                               value: pendingSetting,
                               placeholder: "Add setting",
                               tag: settingCarried ? "last time" : nil) {
                        guard !isCommitted else { return }
                        isEditingSetting = true
                    }
                }
                if showsSetting && (hasNote || !isCommitted) {
                    Rectangle().fill(SettColor.cardBorder).frame(height: 0.5)
                        .padding(.horizontal, 12)
                }
                if hasNote || !isCommitted {
                    readoutRow(icon: "text.alignleft",
                               label: "NOTE",
                               value: pendingNote,
                               placeholder: "Add note",
                               tag: noteCarried ? "last time" : nil) {
                        guard !isCommitted else { return }
                        isEditingNote = true
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TimeChamber.void.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(liveTier.color.opacity(0.28), lineWidth: 1)
                    }
            }
        }
    }

    private func readoutRow(icon: String, label: String, value: String?,
                            placeholder: String, tag: String?,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundStyle(liveTier.color)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .kerning(1.5)
                            .foregroundStyle(SettColor.iron)
                        if let tag {
                            Text("· \(tag)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(liveTier.color.opacity(0.8))
                        }
                    }
                    Text(value?.isEmpty == false ? value! : placeholder)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(value?.isEmpty == false ? SettColor.bone : SettColor.iron)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if !isCommitted {
                    Image(systemName: "square.and.pencil")
                        .font(.caption)
                        .foregroundStyle(SettColor.iron)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCommitted)
        .accessibilityLabel("\(label): \(value?.isEmpty == false ? value! : "none")")
    }

    private var showsSetting: Bool {
        if pendingSetting?.isEmpty == false { return true }
        guard let equipment = exercise?.equipment else { return false }
        return equipment == .machine || equipment == .cable
    }

    private var hasNote: Bool { pendingNote?.isEmpty == false }
    private var settingCarried: Bool {
        !isCommitted && pendingSetting?.isEmpty == false && pendingSetting == reference?.setting
    }
    private var noteCarried: Bool {
        !isCommitted && pendingNote?.isEmpty == false && pendingNote == reference?.note
    }

    // MARK: Warm-up chip (open slots only)

    @ViewBuilder
    private var chipsRow: some View {
        if !isCommitted {
            Button {
                isWarmup.toggle()
                Haptics.selection()
            } label: {
                Text("WARM-UP")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(isWarmup ? TimeChamber.teal : SettColor.ash)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background {
                        Capsule().strokeBorder(
                            isWarmup ? TimeChamber.teal.opacity(0.6) : SettColor.cardBorder,
                            lineWidth: 1
                        )
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWarmup ? "Warm-up set, on" : "Warm-up set, off")
        }
    }

    // MARK: The LOG slab

    @ViewBuilder
    private var slab: some View {
        if isCommitted {
            PlayerSlab(title: "LOGGED", flashesCyan: false, isEnabled: false) {}
        } else {
            PlayerSlab(title: "LOG SET", accent: liveTier.color, isEnabled: reps > 0) { log() }
        }
    }

    /// Commit the visible values. Crit when this set's weight beats the reference set
    /// at the index it lands on. Celebration plays AFTER the write; the shell holds
    /// the REST transition for the gold flash.
    private func log() {
        let index = workoutExercise.orderedSets.count
        let isCasual = session.activeWorkout?.isCasual ?? false
        let readback = session.readback(for: workoutExercise, slot: index,
                                        weightGrams: weightGrams, reps: reps)
        let outcome = LogOutcome.classify(readback: readback,
                                          isWarmup: isWarmup, isCasual: isCasual)

        session.logSet(on: workoutExercise, weightGrams: weightGrams, reps: reps,
                       isWarmup: isWarmup, notes: pendingNote, setting: pendingSetting)
        pendingNote = nil
        pendingSetting = nil
        stepperHideTask?.cancel()
        activeStepper = nil
        burstToken += 1

        let loggedSetCount = session.activeWorkout?.orderedExercises
            .reduce(0) { $0 + $1.orderedSets.count } ?? 0
        let message = ScannerMessages.line(for: outcome, loggedSetCount: loggedSetCount)
        session.lastReadback = LoggedReadback(weightGrams: weightGrams, reps: reps,
                                              readback: readback, outcome: outcome,
                                              message: message)

        let e1RMLb = Int(Units.pounds(fromGrams: readback.e1RMGrams).rounded())
        switch outcome {
        case .personalBest, .beat:
            let gainLb = Int(Units.pounds(fromGrams: readback.e1RMDeltaGrams ?? 0).rounded())
            combatText?.emit("+\(gainLb.formatted()) PWR", crit: outcome.isCrit)
        default:
            combatText?.emit("OUTPUT \(e1RMLb.formatted())", crit: false)
        }
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

/// The full-width ≥96 pt commit slab: mono label on an etched capsule. Pressing
/// flashes the accent (a brief hairline) and runs `action` immediately — input
/// latency is sacred, celebration is the caller's job.
struct PlayerSlab: View {
    let title: String
    var flashesCyan = true
    var accent: Color = SettColor.heroCyan
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
                .frame(maxWidth: .infinity, minHeight: 92)
                .background {
                    ZStack {
                        Capsule().fill(TimeChamber.void.opacity(0.7))
                        Capsule().strokeBorder(isEnabled ? accent.opacity(0.5) : SettColor.cardBorder,
                                               lineWidth: 1)
                        Capsule().strokeBorder(SettColor.etch, lineWidth: 1).padding(2)
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(accent, lineWidth: 1.5)
                        .opacity(flashOpacity)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title.capitalized)
    }
}
