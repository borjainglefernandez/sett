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
    @State private var hasLoaded = false
    @State private var isEditingSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                machineSetupCard
                if samples.isEmpty {
                    neverTrainedCard
                } else {
                    if let bestSet {
                        prCard(bestSet)
                    }
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
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: Machine setup (Exercise.instructions — the machine-setup field app-wide)

    /// Etched card near the top: the setup in bone mono with an edit pencil, or a
    /// quiet "Add machine setup" affordance when empty. Edits go through the ONE
    /// shared `MachineSetupSheet` (Session/ExerciseCard.swift).
    private var machineSetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("MACHINE SETUP")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(SettColor.bone)
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
        .sheet(isPresented: $isEditingSetup) {
            MachineSetupSheet(exercise: exercise)
        }
    }

    private var hasSetup: Bool {
        exercise.instructions?.isEmpty == false
    }

    // MARK: PR card (gold — earned)

    private func prCard(_ best: SetSample) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(SettColor.saiyanGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal record")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(services.settings.displayWeight(best.weightGrams)) × \(best.reps)")
                    .font(.title3.bold())
                Text(best.completedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                PowerNumeral(displayInt(maxE1RMGrams), size: .m)
                Text("e1RM \(services.settings.unit.symbol)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .settCard()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettColor.saiyanGold.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal record: \(services.settings.displayWeight(best.weightGrams)) for \(best.reps) reps")
    }

    // MARK: e1RM trend (cyan line, gold dot on the all-time max ONLY)

    private var e1rmChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("e1RM trend (\(services.settings.unit.symbol))")
                .font(.headline)
            Chart(e1rmSeries) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", displayDouble(point.grams))
                )
                .foregroundStyle(SettColor.heroCyan)
                if point.grams == maxE1RMGrams {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("e1RM", displayDouble(point.grams))
                    )
                    .foregroundStyle(SettColor.saiyanGold)
                    .symbolSize(90)
                }
            }
            .frame(height: 180)
        }
        .settCard()
    }

    // MARK: Session volume (second chart beneath)

    private var volumeChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session volume (\(services.settings.unit.symbol)·reps)")
                .font(.headline)
            Chart(volumePoints) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Volume", volumeDisplay(point.volumeGrams))
                )
                .foregroundStyle(SettColor.heroCyan)
            }
            .frame(height: 120)
        }
        .settCard()
    }

    // MARK: Recent sets (grouped by session, newest first, 10 groups max)

    private var recentSetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent sets")
                .font(.headline)
            ForEach(recentGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SettColor.heroCyan)
                    ForEach(Array(group.sets.enumerated()), id: \.offset) { _, sample in
                        HStack(spacing: 8) {
                            Text("\(services.settings.displayWeight(sample.weightGrams)) × \(sample.reps)")
                                .font(.subheadline)
                                .monospacedDigit()
                            if sample.isWarmup {
                                Text("warmup")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(SettColor.cardNested, in: Capsule())
                            }
                            Spacer()
                        }
                    }
                }
                if group.id != recentGroups.last?.id {
                    Divider()
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
            }
            .tint(SettColor.heroCyan)
            Text("Archived exercises are hidden from pickers but keep their history and charts.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Text("Never trained")
                .font(.headline)
            Text("First set sets the baseline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .settCard()
    }

    // MARK: Derivations (computed once per appearance from a sample snapshot)

    private var maxE1RMGrams: Int {
        e1rmSeries.map(\.grams).max() ?? 0
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
    }
}
