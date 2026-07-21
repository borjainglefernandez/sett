import SwiftUI
import SwiftData
import Charts
import SettCore

// MARK: - Chart points (private to this screen)

private struct E1RMPoint: Identifiable {
    let date: Date
    let grams: Int
    var id: Date { date }
}

private struct VolumePoint: Identifiable {
    let id: UUID          // workout id
    let date: Date
    let volumeGrams: Int
}

private struct SessionGroup: Identifiable {
    let id: UUID          // workout id
    let date: Date
    let sets: [SetSample]
}

// MARK: - Detail

/// Per-exercise history & stats (design-ux §2 — the screen v1 lacked):
/// e1RM trend line with a gold dot on the all-time max, session volume bars,
/// gold PR card, recent sets grouped by session, archive toggle.
/// Charts are Apple-Health-grade clean: cyan series, gold ONLY for the PR mark.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @State private var samples: [SetSample] = []
    @State private var e1rmSeries: [E1RMPoint] = []
    @State private var volumePoints: [VolumePoint] = []
    @State private var bestSet: SetSample?
    @State private var recentGroups: [SessionGroup] = []
    /// The active PR-target goal for this lift, if the user set one (nil otherwise).
    @State private var prTargetGoal: Goal?
    @State private var hasLoaded = false
    @State private var isEditingSetup = false
    /// Custom lifts only: the shared forge sheet in edit mode.
    @State private var isEditingExercise = false
    /// Chart reveal: the plot masks in left-to-right on first appear, then the gold
    /// all-time-PR dot pops after the line reaches it. This screen is about watching
    /// strength climb — so it draws, rather than snapping in fully formed.
    @State private var chartsDrawn = false
    @State private var prDotPopped = false
    /// Once the crown has landed, it breathes a slow gold glow — a record that's still
    /// alive, not a dead marker. Stays false (static) under Reduce Motion.
    @State private var prPulsing = false
    /// Touch-scrub position on each chart — a RuleMark + callout reads the exact
    /// session under the finger. nil when not scrubbing.
    @State private var e1rmScrubDate: Date?
    @State private var volumeScrubDate: Date?
    /// One-shot sweep for the PR-target ring (mirrors GoalRingView's on-appear fill).
    @State private var targetSweep = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                heroHeader
                if showsMachineSetupCard {
                    machineSetupCard
                }
                if samples.isEmpty {
                    neverTrainedCard
                } else {
                    if let bestSet {
                        prCard(bestSet)
                    }
                    prTargetCard
                    e1rmChartCard
                    volumeChartCard
                    recentSetsCard
                }
                archiveCard
            }
            .padding(16)
        }
        .dungeonBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Catalog lifts are canon; only the user's own creations are editable.
            if exercise.isCustom {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditingExercise = true }
                }
            }
        }
        .sheet(isPresented: $isEditingSetup) {
            MachineSetupSheet(exercise: exercise)
        }
        .sheet(isPresented: $isEditingExercise) {
            CreateExerciseSheet(initialName: "", existing: exercise)
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: Header (hero the commissioned art — it only ever drew at list size)

    /// A compact identity row that leads the screen: the exercise's region-framed
    /// Gemini art at 64pt beside its name and muscle · equipment line. The art is canon
    /// for every lift but had only ever rendered at ~44pt in pickers — never large.
    /// `ExerciseIcon` keeps the same art → muscle-art → glyph fallback the lists use.
    private var heroHeader: some View {
        HStack(spacing: 14) {
            ExerciseIcon(name: exercise.name, equipment: exercise.equipment,
                         muscle: exercise.muscle, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Eyebrow("\(exercise.muscle.rawValue) · \(exercise.equipment.rawValue)".uppercased())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Machine setup (Exercise.instructions — the machine-setup field app-wide)

    /// Etched card near the top: the setup in bone mono with an edit pencil, or a
    /// quiet "Add machine setup" affordance when empty. Edits go through the ONE
    /// shared `MachineSetupSheet` (Session/ExerciseCard.swift).
    private var machineSetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Eyebrow("MACHINE SETUP", tint: SettColor.bone)
                Spacer()
                if hasSetup {
                    Button {
                        isEditingSetup = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SettColor.ash)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit machine setup")
                }
            }
            if let setup = exercise.instructions, !setup.isEmpty {
                Text(setup)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(SettColor.bone)
            } else {
                Button {
                    isEditingSetup = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.caption)
                        Text("Add machine setup")
                            .font(.subheadline)
                    }
                    .foregroundStyle(SettColor.ash)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var hasSetup: Bool {
        exercise.instructions?.isEmpty == false
    }

    /// Free weights and bodyweight have nothing to dial in, so the empty card
    /// hides for them (mirrors the session ExerciseCard rule). A saved setup
    /// always shows, whatever the equipment.
    private var showsMachineSetupCard: Bool {
        hasSetup || exercise.equipment == .machine || exercise.equipment == .cable
    }

    // MARK: PR card (gold — earned)

    private func prCard(_ best: SetSample) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "medal.fill")
                .font(.title2)
                .foregroundStyle(SettColor.saiyanGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal record")
                    .font(.subheadline)
                    .foregroundStyle(SettColor.ash)
                Text("\(services.settings.displayWeight(best.weightGrams)) × \(best.reps)")
                    .font(.title3.bold())
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(best.completedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(SettColor.ash)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                PowerNumeral(displayInt(maxE1RMGrams), size: .m)
                Text("e1RM \(services.settings.unit.symbol)")
                    .font(.caption2)
                    .foregroundStyle(SettColor.ash)
            }
        }
        .settCard()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettColor.saiyanGold.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal record: \(services.settings.displayWeight(best.weightGrams)) for \(best.reps) reps. Estimated one-rep max \(displayInt(maxE1RMGrams)) \(services.settings.unit.symbol).")
    }

    // MARK: PR-target goal (cyan ring in progress; the ring itself turns gold once
    // earned — gold stays reserved for the earned PR numeral in prCard otherwise)

    /// Distance-to-goal for the committed PR target on this lift. Shown only when an
    /// active prTarget goal exists; a local ring (see `targetRing`) carries the same
    /// grammar as GoalRingView but reads the remaining amount. EmptyView with no goal.
    @ViewBuilder
    private var prTargetCard: some View {
        if let goal = prTargetGoal {
            let progress = goalProgress(for: goal)
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("TARGET")
                HStack(spacing: 16) {
                    targetRing(progress)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target \(progress.targetValue) \(services.settings.unit.symbol)")
                            .font(.subheadline)
                            .foregroundStyle(SettColor.bone)
                        if progress.isComplete {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SettColor.saiyanGold)
                        } else {
                            // The distance now lives inside the ring ("12 TO GO"), so the
                            // label states the current lift instead of repeating the gap.
                            Text("Current \(progress.currentValue) \(services.settings.unit.symbol)")
                                .font(.subheadline)
                                .foregroundStyle(SettColor.ash)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settCard()
        }
    }

    /// Evaluate the goal from this lift's samples and convert the gram-valued PR
    /// current/target into display units, exactly as GoalsSection.displayProgress does.
    private func goalProgress(for goal: Goal) -> GoalProgress {
        let sample = GoalSample(id: goal.id, kind: goal.kind, targetValue: goal.targetValue,
                                exerciseID: goal.exerciseID, startDate: goal.startDate,
                                endDate: goal.endDate, isActive: goal.isActive,
                                completedAt: goal.completedAt, createdAt: goal.createdAt)
        let raw = GoalEvaluator.progress(goal: sample, setSamples: samples, workoutSamples: [],
                                         calendar: .current, asOf: .now)
        let unit = services.settings.unit
        return GoalProgress(
            goalID: raw.goalID,
            fraction: raw.fraction,
            currentValue: Int((Double(raw.currentValue) / unit.gramsPerUnit).rounded()),
            targetValue: Int((Double(raw.targetValue) / unit.gramsPerUnit).rounded()),
            isComplete: raw.isComplete
        )
    }

    /// The PR-target ring, drawn locally so its center reads the DISTANCE ("12 TO GO")
    /// rather than "current/target". The target already sits in the label beside it, so
    /// GoalRingView's inner "220/232" was the number said twice. Same grammar otherwise:
    /// 12pt round-cap trim, cyan in progress, gold once earned.
    private func targetRing(_ progress: GoalProgress) -> some View {
        let remaining = max(0, progress.targetValue - progress.currentValue)
        return ZStack {
            Circle()
                .stroke(SettColor.cardNested, lineWidth: 12)
            Circle()
                .trim(from: 0, to: targetSweep ? progress.fraction : 0)
                .stroke(progress.isComplete ? Aura.gold : Aura.cyan,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                if progress.isComplete {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(SettColor.saiyanGold)
                } else {
                    Text("\(remaining)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(SettColor.bone)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("TO GO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.isComplete
            ? "Target reached"
            : "\(remaining) \(services.settings.unit.symbol) to go, \(progress.currentValue) of \(progress.targetValue)")
        .onAppear {
            guard !targetSweep else { return }
            if reduceMotion {
                targetSweep = true
            } else {
                withAnimation(.snappy(duration: 0.5)) { targetSweep = true }
            }
        }
    }

    // MARK: e1RM trend (cyan line, gold dot on the all-time max ONLY)

    private var e1rmChartCard: some View {
        let scrub = nearestE1RM(to: e1rmScrubDate)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardTitle("e1RM trend (\(services.settings.unit.symbol))")
                Spacer(minLength: 8)
                if let scrub {
                    chartReadout(date: scrub.date,
                                 value: "\(displayInt(scrub.grams)) \(services.settings.unit.symbol)")
                }
            }
            Chart {
                ForEach(e1rmSeries) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("e1RM", displayDouble(point.grams))
                    )
                    .foregroundStyle(SettColor.heroCyan)
                    if point.id == prPoint?.id {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("e1RM", displayDouble(point.grams))
                        )
                        .foregroundStyle(SettColor.saiyanGold)
                        .symbolSize(90)
                        .annotation(position: .overlay, overflowResolution: .init(x: .fit, y: .fit)) {
                            Circle()
                                .fill(Aura.gold)
                                .frame(width: 11, height: 11)
                                .auraGlow(SettColor.saiyanGold, radius: 8)
                                // The crown lands only once the cyan line has swept up to it.
                                .scaleEffect(prDotPopped ? 1 : 0.2)
                                // A separate breathe so it never collides with the landing pop.
                                .scaleEffect(prPulsing ? 1.18 : 1)
                                .opacity(prDotPopped ? 1 : 0)
                        }
                    }
                }
                if let scrub {
                    RuleMark(x: .value("Date", scrub.date))
                        .foregroundStyle(SettColor.ash.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Date", scrub.date),
                              y: .value("e1RM", displayDouble(scrub.grams)))
                        .foregroundStyle(SettColor.heroCyan)
                        .symbolSize(80)
                }
            }
            .chartYScale(domain: e1rmYDomain)
            .chartXScale(domain: e1rmXDomain)
            .scouterChart(xCount: 4, yCount: 4)
            .chartXSelection(value: $e1rmScrubDate)
            .frame(height: 180)
            .mask(chartWipe)
        }
        .settCard()
        // Both charts are in the tree together once samples load, so one trigger drives
        // the shared reveal. (loadIfNeeded's onAppear runs while samples is still empty,
        // before these cards mount — this is where the plot actually exists.)
        .onAppear(perform: revealCharts)
    }

    /// Left-anchored wipe that grows from 0 to full width as `chartsDrawn` flips.
    private var chartWipe: some View {
        GeometryReader { geo in
            Rectangle().frame(width: chartsDrawn ? geo.size.width : 0)
        }
    }

    private func revealCharts() {
        guard !chartsDrawn else { return }
        if reduceMotion {
            chartsDrawn = true
            prDotPopped = true
            return
        }
        withAnimation(.easeOut(duration: 0.6)) { chartsDrawn = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { prDotPopped = true }
            // Let the pop settle, then the crown breathes a slow gold glow forever.
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { prPulsing = true }
        }
    }

    // MARK: Session volume (second chart beneath)

    private var volumeChartCard: some View {
        let scrub = nearestVolume(to: volumeScrubDate)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardTitle("Session volume (\(services.settings.unit.symbol)·reps)")
                Spacer(minLength: 8)
                if let scrub {
                    chartReadout(date: scrub.date,
                                 value: Int(volumeDisplay(scrub.volumeGrams).rounded()).formatted())
                }
            }
            Chart {
                ForEach(volumePoints) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Volume", volumeDisplay(point.volumeGrams)),
                        // Was a 1–2px hairline that read as a barcode — fill ~60% of the
                        // day slot so each session lands as a real bar.
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(scrub?.id == point.id
                                     ? SettColor.heroCyan
                                     : SettColor.heroCyan.opacity(scrub == nil ? 1 : 0.4))
                }
            }
            .chartXScale(domain: volumeXDomain)
            .chartYScale(domain: volumeYDomain)
            .scouterChart(xCount: 4, yCount: 4)
            .chartXSelection(value: $volumeScrubDate)
            .frame(height: 120)
            .mask(chartWipe)
        }
        .settCard()
    }

    /// The date + value pill that reads out the scrubbed session, shown beside the
    /// chart title while a finger is down.
    private func chartReadout(date: Date, value: String) -> some View {
        HStack(spacing: 6) {
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .foregroundStyle(SettColor.ash)
            Text(value)
                .foregroundStyle(SettColor.bone)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .transition(.opacity)
    }

    // MARK: Recent sets (grouped by session, newest first, last 5 — tap into the workout)

    private var recentSetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Recent sets")
            ForEach(recentGroups) { group in
                NavigationLink {
                    if let workout = workout(id: group.id) {
                        WorkoutDetailView(workout: workout)
                    } else {
                        EmptyChamber(title: "Workout unavailable",
                                     message: "This session is no longer on record.")
                    }
                } label: {
                    recentGroupRow(group)
                }
                .buttonStyle(.plain)
                if group.id != recentGroups.last?.id {
                    Rectangle()
                        .fill(SettColor.cardBorder)
                        .frame(height: 1)
                }
            }
        }
        .settCard()
    }

    private func recentGroupRow(_ group: SessionGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(group.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettColor.heroCyan)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
            }
            ForEach(Array(group.sets.enumerated()), id: \.offset) { _, sample in
                HStack(spacing: 8) {
                    Text("\(services.settings.displayWeight(sample.weightGrams)) × \(sample.reps)")
                        .font(.subheadline)
                        .foregroundStyle(SettColor.bone)
                        .monospacedDigit()
                    if sample.isWarmup {
                        StatusChip("warmup")
                    }
                    Spacer()
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this workout")
    }

    // MARK: Archive (isArchived + updatedAt + needsPush; history survives)

    private var archiveCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: archiveBinding) {
                Label("Archive exercise", systemImage: "archivebox")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SettColor.bone)
            }
            .tint(SettColor.heroCyan)
            Text("Archived exercises are hidden from pickers but keep their history and charts.")
                .font(.caption)
                .foregroundStyle(SettColor.ash)
        }
        .settCard()
    }

    private var archiveBinding: Binding<Bool> {
        Binding(
            get: { exercise.isArchived },
            set: { newValue in
                exercise.isArchived = newValue
                exercise.updatedAt = .now
                exercise.needsPush = true
                try? modelContext.save()
                Haptics.selection()
            }
        )
    }

    // MARK: Empty state

    private var neverTrainedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36))
                .foregroundStyle(SettColor.ash)
            Text("Never trained")
                .font(.headline)
                .foregroundStyle(SettColor.bone)
            Text("First set sets the baseline.")
                .font(.subheadline)
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity)
        .settCard()
    }

    // MARK: Derivations (computed once per appearance from a sample snapshot)

    private var maxE1RMGrams: Int {
        e1rmSeries.map(\.grams).max() ?? 0
    }

    /// The single all-time-max point (earliest session on a tie) — the ONE gold dot,
    /// so a plateau at the max never scatters duplicate marks.
    private var prPoint: E1RMPoint? {
        e1rmSeries.max { $0.grams < $1.grams }
    }

    private var e1rmXDomain: ClosedRange<Date> { Self.paddedDateDomain(e1rmSeries.map(\.date)) }
    private var volumeXDomain: ClosedRange<Date> { Self.paddedDateDomain(volumePoints.map(\.date)) }

    /// Y domain with headroom above the peak (and a little below the floor) so the top
    /// tick label isn't flush at the plot's top edge, where it clipped ("22|0"). Also
    /// stops the PR peak from jamming into the ceiling.
    private var e1rmYDomain: ClosedRange<Double> {
        let values = e1rmSeries.map { displayDouble($0.grams) }
        guard let lo = values.min(), let hi = values.max(), lo < hi else {
            let v = values.first ?? 0
            return (v - 1) ... (v + 1)
        }
        let pad = (hi - lo) * 0.12
        return (lo - pad) ... (hi + pad)
    }

    /// Bars sit on zero; just add top headroom so the top volume tick label has room.
    private var volumeYDomain: ClosedRange<Double> {
        let hi = volumePoints.map { volumeDisplay($0.volumeGrams) }.max() ?? 0
        return 0 ... max(hi * 1.12, 1)
    }

    /// The series point nearest the scrub date — snaps the RuleMark + readout to a real
    /// session rather than floating between them. nil when not scrubbing.
    private func nearestE1RM(to date: Date?) -> E1RMPoint? {
        guard let date, !e1rmSeries.isEmpty else { return nil }
        return e1rmSeries.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func nearestVolume(to date: Date?) -> VolumePoint? {
        guard let date, !volumePoints.isEmpty else { return nil }
        return volumePoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    /// The finished workout behind a recent-sets group, fetched by its loose id — the
    /// same resolver the PR feed uses to open a session.
    private func workout(id: UUID) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// A date range padded on both ends so edge points/bars (esp. the most recent
    /// session) aren't clipped at the plot boundary — the "last month cut off" bug.
    private static func paddedDateDomain(_ dates: [Date]) -> ClosedRange<Date> {
        let day: TimeInterval = 86_400
        guard let first = dates.min(), let last = dates.max() else {
            let anchor = Date()
            return anchor.addingTimeInterval(-day) ... anchor.addingTimeInterval(day)
        }
        guard first < last else {
            return first.addingTimeInterval(-day * 3) ... first.addingTimeInterval(day * 3)
        }
        let pad = max(last.timeIntervalSince(first) * 0.04, day * 2)
        return first.addingTimeInterval(-pad) ... last.addingTimeInterval(pad)
    }

    private func displayDouble(_ grams: Int) -> Double {
        Units.displayValue(grams: grams, unit: services.settings.unit)
    }

    private func displayInt(_ grams: Int) -> Int {
        Int(displayDouble(grams).rounded())
    }

    /// Volume load converted to display-unit·reps (raw division; no plate rounding).
    private func volumeDisplay(_ volumeGrams: Int) -> Double {
        Double(volumeGrams) / services.settings.unit.gramsPerUnit
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        let mine = SampleExtractor.setSamples(context: modelContext)
            .filter { $0.exerciseID == exercise.id }
        samples = mine

        e1rmSeries = ProgressEngine.bestE1RMSeries(samples: mine, exerciseID: exercise.id)
            .map { E1RMPoint(date: $0.date, grams: $0.e1RMGrams) }

        let working = mine.filter { !$0.isWarmup }

        volumePoints = Dictionary(grouping: working, by: \.workoutID)
            .compactMap { workoutID, sets -> VolumePoint? in
                guard let date = sets.map(\.completedAt).min() else { return nil }
                let volume = sets.reduce(0) { $0 + $1.weightGrams * $1.reps }
                return VolumePoint(id: workoutID, date: date, volumeGrams: volume)
            }
            .sorted { $0.date < $1.date }

        bestSet = working.max { lhs, rhs in
            let left = ProgressEngine.e1RMGrams(weightGrams: lhs.weightGrams, reps: lhs.reps)
            let right = ProgressEngine.e1RMGrams(weightGrams: rhs.weightGrams, reps: rhs.reps)
            return left == right ? lhs.completedAt < rhs.completedAt : left < right
        }

        recentGroups = Array(
            Dictionary(grouping: mine, by: \.workoutID)
                .compactMap { workoutID, sets -> SessionGroup? in
                    guard let date = sets.map(\.completedAt).min() else { return nil }
                    return SessionGroup(id: workoutID, date: date,
                                        sets: sets.sorted { $0.completedAt < $1.completedAt })
                }
                .sorted { $0.date > $1.date }
                .prefix(5)
        )

        // The committed PR target for this lift, if any — surfaces distance-to-goal.
        let exerciseID: UUID? = exercise.id
        let goalDescriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isActive && $0.exerciseID == exerciseID })
        prTargetGoal = (try? modelContext.fetch(goalDescriptor))?.first { $0.kind == .prTarget }
    }
}
