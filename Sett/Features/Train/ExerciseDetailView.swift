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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
    /// active prTarget goal exists; reuses GoalRingView so it reads like every other
    /// goal in the app. EmptyView when there's no goal.
    @ViewBuilder
    private var prTargetCard: some View {
        if let goal = prTargetGoal {
            let progress = goalProgress(for: goal)
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("TARGET")
                HStack(spacing: 16) {
                    GoalRingView(progress: progress, title: exercise.name)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target \(progress.targetValue) \(services.settings.unit.symbol)")
                            .font(.subheadline)
                            .foregroundStyle(SettColor.bone)
                        if progress.isComplete {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SettColor.saiyanGold)
                        } else {
                            Text("\(max(0, progress.targetValue - progress.currentValue)) \(services.settings.unit.symbol) to go")
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

    // MARK: e1RM trend (cyan line, gold dot on the all-time max ONLY)

    private var e1rmChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("e1RM trend (\(services.settings.unit.symbol))")
            Chart(e1rmSeries) { point in
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
                            .opacity(prDotPopped ? 1 : 0)
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXScale(domain: e1rmXDomain)
            .scouterChart()
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
        }
    }

    // MARK: Session volume (second chart beneath)

    private var volumeChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("Session volume (\(services.settings.unit.symbol)·reps)")
            Chart(volumePoints) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Volume", volumeDisplay(point.volumeGrams))
                )
                .foregroundStyle(SettColor.heroCyan)
            }
            .chartXScale(domain: volumeXDomain)
            .scouterChart()
            .frame(height: 120)
            .mask(chartWipe)
        }
        .settCard()
    }

    // MARK: Recent sets (grouped by session, newest first, 10 groups max)

    private var recentSetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Recent sets")
            ForEach(recentGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SettColor.heroCyan)
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
                if group.id != recentGroups.last?.id {
                    Rectangle()
                        .fill(SettColor.cardBorder)
                        .frame(height: 1)
                }
            }
        }
        .settCard()
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
                .prefix(10)
        )

        // The committed PR target for this lift, if any — surfaces distance-to-goal.
        let exerciseID: UUID? = exercise.id
        let goalDescriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isActive && $0.exerciseID == exerciseID })
        prTargetGoal = (try? modelContext.fetch(goalDescriptor))?.first { $0.kind == .prTarget }
    }
}
