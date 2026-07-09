import SwiftUI
import SettCore

/// SET state of the Set Player — the logging scanner, rebuilt as a Time Chamber
/// scouter. One set fills the screen: the exercise name and SET n/m up top; the
/// center is a SCOUTER CORE — huge weight × reps numerals inside a living aura
/// ring whose colour is a live reading of how this set scores against last time
/// (green = holding the line, amber = beat it, red = a new ceiling / overload,
/// steel = output down); beneath, a readable SCOUTER LOG (setting + note)
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
    /// The field whose numeric keypad is open (tap a number to type directly).
    @State private var padField: NumericField?
    /// 0.4 s white-hot overload flash on the numerals on a ceiling break (PR).
    /// No gold in-session — gold is the app-wide power level only.
    @State private var overloadFlash = false
    /// Exercise row behind the loose `exerciseID` — the setting default source.
    @State private var exercise: Exercise?
    /// Previous session's reading at this slot (values + note + setting + prior best).
    @State private var reference: WorkoutSessionStore.SlotReference?
    /// Bumped on log so the aura ring flares (the power-up).
    @State private var burstToken = 0
    /// Live "over the ceiling" edge — drives the PEAK swaps + a one-shot PWR kick.
    @State private var overCeiling = false
    /// Two multiplicative PWR scales: `pwrKick` punches on crossing the ceiling
    /// ("it's over…"), `pwrSurge` punches on any big jump (add a plate → it leaps).
    @State private var pwrKick: CGFloat = 1
    @State private var pwrSurge: CGFloat = 1

    // Scanner acquisition (item 3b): a ~350 ms scanline sweep + digit scramble on
    // every new slot. `acquiring` gates the scramble; `scanProgress` drives the
    // sweep (0 → 1). Reduce Motion direct-sets both to the settled state.
    @State private var acquiring = false
    @State private var acquireFrame = 0
    @State private var scanProgress: CGFloat = 1
    @State private var acquireTask: Task<Void, Never>?

    /// The app's largest numeral — the one fixed-size exception granted to the player.
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 40

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
        .onDisappear { acquireTask?.cancel() }
        .sheet(item: $padField) { field in
            numericPad(for: field)
        }
        .sheet(isPresented: $isEditingNote) {
            SetNoteSheet(initialText: pendingNote ?? "") { pendingNote = $0 }
        }
        .sheet(isPresented: $isEditingSetting) {
            SetNoteSheet(initialText: pendingSetting ?? "",
                         title: "SETTING",
                         placeholder: "seat 5 · pin 9 · collars on") { pendingSetting = $0 }
        }
    }

    // MARK: Live aura reading (the transformation preview)

    /// The aura tier for the CURRENT input, scored against last session's set at
    /// this slot and the all-time prior best — computed in-memory from the cached
    /// `reference`, so it updates instantly as the numbers change (no DB fetch).
    /// The training lens this session scores through (cut/bulk/maintain).
    private var activePhase: TrainingPhase { session.activeWorkout?.phase ?? .maintaining }

    private var liveTier: AuraTier {
        if isWarmup { return .calm }
        guard let ref = reference else { return .base }
        let e1RM = ProgressEngine.e1RMGrams(weightGrams: displayedWeightGrams, reps: displayedReps)
        let isPB = ref.priorBestE1RMGrams > 0 && e1RM > ref.priorBestE1RMGrams
        let refE1RM: Int? = (ref.hasReference && ref.weightGrams != nil && ref.reps != nil)
            ? ProgressEngine.e1RMGrams(weightGrams: ref.weightGrams!, reps: ref.reps!) : nil
        // Reuse the real classifier so the LIVE aura matches the logged verdict.
        let preview = SetReadback(weightDeltaGrams: nil, repsDelta: nil,
                                  isBaseline: refE1RM == nil,
                                  e1RMGrams: e1RM, referenceE1RMGrams: refE1RM,
                                  e1RMDeltaGrams: refE1RM.map { e1RM - $0 },
                                  isPersonalBest: isPB)
        return LogOutcome.classify(readback: preview, phase: activePhase,
                                   isWarmup: false, isCasual: false).auraTier
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
        // If we open onto a set already above the ceiling, reflect that in the
        // initial state (the crossing kick/haptic only fire on a live edge later).
        overCeiling = ceilingPwr > 0 && powerReading >= ceilingPwr
        // Auto-populate from the previous session: the note carries over, and the
        // setting defaults to last session's setting, then the exercise default.
        pendingNote = ref.note
        pendingSetting = ref.setting ?? exercise?.instructions
    }

    // MARK: Header (exercise · SET n/m)

    private var header: some View {
        VStack(spacing: 8) {
            Text(overCeiling ? "CEILING BROKEN" : "TARGET ACQUIRED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(overCeiling ? TimeChamber.scouterRed : liveTier.color)
                .accessibilityHidden(true)
            HStack(spacing: 9) {
                if let equipment = exercise?.equipment {
                    Image(systemName: equipment.symbolName)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(liveTier.color)
                        .accessibilityHidden(true)
                }
                Text(workoutExercise.exerciseNameSnapshot.uppercased())
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .kerning(2)
                    .foregroundStyle(SettColor.bone)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Text("SET \(slotIndex + 1) / \(slotCount)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .kerning(2)
                .foregroundStyle(SettColor.bone)
        }
        .padding(.horizontal, 24)
        // A tight dark halo keeps the header crisp over ANY realm (incl. the bright
        // White Void / Golden Sanctuary).
        .shadow(color: .black.opacity(0.85), radius: 2)
        .shadow(color: .black.opacity(0.5), radius: 7)
    }

    // MARK: Scouter core (numerals inside the living aura ring)

    /// Numbers are always bright bone (legible over the nebula); a ghost (not-yet-
    /// edited) reading is dimmed via opacity rather than a murky colour.
    private var numeralColor: Color {
        overloadFlash ? TimeChamber.scouterRedPale : SettColor.bone
    }

    private var numeralOpacity: Double {
        (isGhost && !isCommitted) ? 0.72 : 1
    }

    /// The scouter reads top-to-bottom: WEIGHT + its picker up top, the PWR power
    /// level dead centre, REPS + its picker at the bottom.
    private var scouterCore: some View {
        ZStack {
            ScouterLens(tier: isCommitted ? .base : liveTier, burstToken: burstToken,
                        charge: liveCharge, ceilingFrac: ceilingFrac, atCeiling: overCeiling)
                .frame(width: 344, height: 236)
                .animation(.easeInOut(duration: 0.35), value: liveTier)
                .animation(.easeOut(duration: 0.3), value: liveCharge)
            VStack(spacing: 0) {
                fieldRow(text: WeightFormat.compact(grams: displayedWeightGrams,
                                                    unit: services.settings.unit),
                         unit: services.settings.unit.symbol.uppercased(),
                         field: .weight, salt: 0x11, accessibility: "Weight")
                Spacer(minLength: 6)
                powerReadout
                Spacer(minLength: 6)
                fieldRow(text: "\(displayedReps)", unit: "REPS",
                         field: .reps, salt: 0x77, accessibility: "Reps")
            }
            .frame(width: 300, height: 150)
            .overlay { acquisitionScanline }
        }
        .frame(minHeight: 248)
        .onChange(of: powerReading) { old, new in handlePowerChange(old: old, new: new) }
    }

    /// Live reactions to the power reading changing as you dial: the signature
    /// "over the ceiling" beat (edge-triggered — PEAK swaps + a kick + a rigid tap
    /// on the false→true crossing only), and a surge on any big jump (a plate leaps
    /// the reading). Pure edge detection — deterministic; Reduce Motion drops the
    /// scale punches but keeps the state/haptic.
    private func handlePowerChange(old: Int, new: Int) {
        let over = ceilingPwr > 0 && new >= ceilingPwr
        if over != overCeiling {
            withAnimation(.easeInOut(duration: 0.25)) { overCeiling = over }
            if over {
                Haptics.rigid()
                if !reduceMotion {
                    pwrKick = 1.15
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { pwrKick = 1 }
                }
            }
        }
        let jump = abs(new - old)
        if !reduceMotion, jump >= 15 {
            pwrSurge = 1.12
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { pwrSurge = 1 }
        }
    }

    /// One half of the scouter: the big number (tap to type) flanked by − / + circle
    /// pickers, with the unit inline. Committed slots show the number alone.
    private func fieldRow(text: String, unit: String, field: NumericField,
                          salt: UInt64, accessibility: String) -> some View {
        HStack(spacing: 12) {
            if !isCommitted { stepCircle("minus") { step(field, -1) } }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                numeralText(text, field: field, salt: salt, accessibility: accessibility)
                unitCaption(unit)
            }
            if !isCommitted { stepCircle("plus") { step(field, 1) } }
        }
    }

    @ViewBuilder
    private var acquisitionScanline: some View {
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

    /// The scouter's power reading — this set's estimated output (e1RM), dead centre
    /// of the lens, rolling as you dial the numbers, in the live scouter hue.
    private var powerReadout: some View {
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                SettSigil(size: 13, color: liveTier.color)
                Text("PWR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(liveTier.color.opacity(0.85))
                Text("\(powerReading)")
                    .font(.system(size: 27, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(liveTier.color)
                    .contentTransition(.numericText(value: Double(powerReading)))
                    .scaleEffect(pwrKick * pwrSurge)
            }
            // The ceiling you're chasing — a dim ghost that flips to OVER (in the
            // live hue) the instant you dial past it.
            if ceilingPwr > 0 {
                Text(overCeiling ? "OVER \(ceilingPwr)" : "CEILING \(ceilingPwr)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(overCeiling ? liveTier.color : SettColor.ash)
            }
        }
        .shadow(color: .black.opacity(0.85), radius: 3)
        .animation(.snappy(duration: 0.2), value: powerReading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overCeiling ? "Power reading \(powerReading), over the ceiling"
                                        : "Power reading \(powerReading)")
    }

    /// This set's e1RM ("output") — from canonical grams, so it's the SAME number
    /// for the same lift regardless of the display unit.
    private var powerReading: Int {
        let grams = ProgressEngine.e1RMGrams(weightGrams: displayedWeightGrams, reps: displayedReps)
        return Int(Units.pounds(fromGrams: grams).rounded())
    }

    /// The all-time ceiling for this slot as a power level (0 = none yet) — the
    /// number you're chasing. Drives the gauge notch (and, in a later beat, the
    /// live "over the ceiling" moment while dialing).
    private var ceilingPwr: Int {
        guard let ref = reference, ref.priorBestE1RMGrams > 0 else { return 0 }
        return Int(Units.pounds(fromGrams: ref.priorBestE1RMGrams).rounded())
    }

    /// Gauge fill (0…1): the live reading against the ceiling, compressed so the
    /// ceiling notch sits at 0.82 of the strip — leaving headroom to sweep visibly
    /// PAST it on a PR. With no ceiling yet, a calm mid-fill. Pure state.
    private var liveCharge: Double {
        guard ceilingPwr > 0 else { return 0.55 }
        return min(1.0, Double(powerReading) / Double(ceilingPwr) * 0.82)
    }

    /// Where the ceiling notch sits on the gauge (−1 = no ceiling → no notch).
    private var ceilingFrac: Double { ceilingPwr > 0 ? 0.82 : -1 }

    private func unitCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .kerning(1)
            .foregroundStyle(SettColor.ash)
            .shadow(color: .black.opacity(0.7), radius: 3)
            .accessibilityHidden(true)
    }

    private func numeralText(_ text: String, field: NumericField, salt: UInt64,
                             accessibility: String) -> some View {
        Text(scanned(text, salt: salt))
            .font(.system(size: numeralSize, weight: .heavy, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(numeralColor)
            .opacity(numeralOpacity)
            .shadow(color: overloadFlash ? TimeChamber.scouterRed.opacity(0.7) : .black.opacity(0.85),
                    radius: overloadFlash ? 12 : 6)
            .fixedSize()
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isCommitted else { return }
                Haptics.selection()
                padField = field   // tap the number → type it on the keypad
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(accessibility) \(text)")
            .accessibilityHint(isCommitted ? "" : "Tap to type, or use the − / + buttons")
    }

    private func stepCircle(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SettColor.bone)
                .frame(width: 36, height: 36)
                .background {
                    Circle().fill(TimeChamber.void.opacity(0.55))
                    Circle().strokeBorder(liveTier.color.opacity(0.45), lineWidth: 1)
                }
                .contentShape(Circle())
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
                    .fill(TimeChamber.void.opacity(0.66))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(liveTier.color.opacity(0.3), lineWidth: 1)
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
                            .foregroundStyle(SettColor.ash)
                        if let tag {
                            Text("· \(tag)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(liveTier.color.opacity(0.8))
                        }
                    }
                    Text(value?.isEmpty == false ? value! : placeholder)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(value?.isEmpty == false ? SettColor.bone : SettColor.ash)
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

    /// The setting row is available for EVERY exercise now (seat/pin/collars/belt
    /// notes apply to free weights too), so the feature is always discoverable.
    private var showsSetting: Bool { true }

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
        let phase = activePhase
        let outcome = LogOutcome.classify(readback: readback, phase: phase,
                                          isWarmup: isWarmup, isCasual: isCasual)

        session.logSet(on: workoutExercise, weightGrams: weightGrams, reps: reps,
                       isWarmup: isWarmup, notes: pendingNote, setting: pendingSetting)
        pendingNote = nil
        pendingSetting = nil
        burstToken += 1

        let loggedSetCount = session.activeWorkout?.orderedExercises
            .reduce(0) { $0 + $1.orderedSets.count } ?? 0
        let message = ScannerMessages.line(for: outcome, loggedSetCount: loggedSetCount)
        session.lastReadback = LoggedReadback(weightGrams: weightGrams, reps: reps,
                                              readback: readback, outcome: outcome,
                                              message: message, phase: phase)

        let e1RMLb = Int(Units.pounds(fromGrams: readback.e1RMGrams).rounded())
        switch outcome {
        case .personalBest, .beat:
            let gainLb = Int(Units.pounds(fromGrams: readback.e1RMDeltaGrams ?? 0).rounded())
            combatText?.emit("+\(gainLb.formatted()) PWR", crit: outcome.isCrit,
                             magnitude: gainLb, color: outcome.auraTier.color)
        case .held:
            combatText?.emit("HELD", crit: false)
        case .heldUnderFire:
            combatText?.emit(phase == .cutting ? "DEFENDED" : "HELD", crit: false)
        case .stalled:
            combatText?.emit("PUSH", crit: false)
        default:
            combatText?.emit("OUTPUT \(e1RMLb.formatted())", crit: false)
        }
        playCommitHaptics(for: outcome)
        if outcome.isCrit {
            overloadFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeOut(duration: 0.2)) { overloadFlash = false }
            }
        }
        onLogged(outcome)
    }

    /// Escalating commit haptics scaled to the outcome — the "kiai" ramp. A PR
    /// climbs light → medium → rigid into the PR double-pulse (landing on the
    /// burst); a beat is a medium → rigid one-two; holds get a light confirm.
    /// NOT gated by Reduce Motion — haptics are a separate accessibility axis.
    private func playCommitHaptics(for outcome: LogOutcome) {
        switch outcome {
        case .personalBest:
            Task { @MainActor in
                Haptics.light()
                try? await Task.sleep(for: .milliseconds(90));  Haptics.medium()
                try? await Task.sleep(for: .milliseconds(90));  Haptics.rigid()
                try? await Task.sleep(for: .milliseconds(120)); Haptics.prSignature()
            }
        case .beat:
            Task { @MainActor in
                Haptics.medium()
                try? await Task.sleep(for: .milliseconds(100)); Haptics.rigid()
            }
        case .held, .heldUnderFire, .baseline, .stalled, .dropped:
            Haptics.light()
        case .warmup, .casual:
            Haptics.selection()
        }
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
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
        .buttonStyle(PressableSlabStyle(enabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityLabel(title.capitalized)
    }
}

/// The slab presses IN (0.97) with a synchronous rigid tap on touch-down — the
/// physical "charge" before LOG fires on touch-up (so commit latency is untouched).
private struct PressableSlabStyle: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && enabled { Haptics.rigid() }
            }
    }
}
