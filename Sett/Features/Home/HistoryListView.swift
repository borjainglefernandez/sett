import SwiftUI
import SwiftData
import SettCore

/// "All Workouts" — the month-grouped history log (design-ux §2).
/// Rows: title, date, duration, half-star rating, net chip vs previous
/// same-exercise sessions, badge count. Sort by date/rating/duration; swipe to
/// soft-delete.
struct HistoryListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query private var workouts: [Workout]
    @Query private var badgeAwards: [BadgeAward]

    init() {
        let workoutFilter = #Predicate<Workout> { $0.endedAt != nil && $0.deletedAt == nil }
        _workouts = Query(filter: workoutFilter, sort: [SortDescriptor(\Workout.startedAt, order: .reverse)])

        let badgeAwardFilter = #Predicate<BadgeAward> { $0.deletedAt == nil }
        _badgeAwards = Query(filter: badgeAwardFilter)
    }

    private enum HistorySort: String, CaseIterable, Identifiable {
        case date = "Date"
        case volume = "Volume"
        case power = "Power"
        case sets = "Sets"
        case reps = "Reps"
        case duration = "Duration"
        case rating = "Rating"
        var id: String { rawValue }
    }

    /// Quick filters that don't need a value; gyms are added dynamically.
    private enum QuickFilter: Hashable {
        case all, rated, prs, casual
        case gym(String)
    }

    @State private var sort: HistorySort = .date
    @State private var ascending = false
    @State private var filter: QuickFilter = .all
    @State private var searchText = ""
    /// Extracted once per appearance/delete; workoutNet is pure over these.
    @State private var samples: [SetSample] = []

    var body: some View {
        List {
            if sort == .date {
                ForEach(monthGroups, id: \.key) { group in
                    Section {
                        ForEach(group.workouts) { workout in
                            row(workout)
                        }
                    } header: {
                        HStack {
                            Eyebrow(monthTitle(group.key).uppercased())
                            Spacer()
                            Text("\(group.workouts.count) WORKOUT\(group.workouts.count == 1 ? "" : "S")")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .kerning(1)
                                .monospacedDigit()
                                .foregroundStyle(SettColor.ash)
                        }
                    }
                    .listRowBackground(SettColor.card)
                    .listRowSeparatorTint(SettColor.cardBorder)
                }
            } else {
                Section {
                    ForEach(displayedWorkouts) { workout in
                        row(workout)
                    }
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)
            }
        }
        .scrollContentBackground(.hidden)
        .dungeonBackground()
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .overlay {
            if workouts.isEmpty {
                EmptyChamber(title: "No workouts yet",
                             message: "Your history writes itself.")
            } else if displayedWorkouts.isEmpty && !searchText.isEmpty {
                EmptyChamber(title: "No match",
                             message: "No workout named \u{201C}\(searchText)\u{201D}.")
            }
        }
        .searchable(text: $searchText, prompt: "Search workouts")
        .navigationTitle("All Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { sortMenu }
        .task { refreshSamples() }
    }

    // MARK: Sorting & grouping

    private var displayedWorkouts: [Workout] {
        var result = workouts
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedStandardContains(searchText) }
        }
        switch filter {
        case .all: break
        case .rated: result = result.filter { ($0.ratingHalfStars ?? 0) > 0 }
        case .prs: result = result.filter { (badgeCounts[$0.id] ?? 0) > 0 }
        case .casual: result = result.filter(\.isCasual)
        case .gym(let name): result = result.filter { $0.gymNameSnapshot == name }
        }
        // A metric to rank by; date uses startedAt directly.
        let ranked: [Workout]
        switch sort {
        case .date:     ranked = result.sorted { $0.startedAt > $1.startedAt }
        case .rating:   ranked = result.sorted { ($0.ratingHalfStars ?? -1) > ($1.ratingHalfStars ?? -1) }
        case .duration: ranked = result.sorted { $0.durationSeconds > $1.durationSeconds }
        case .volume:   ranked = result.sorted { workoutVolumeGrams($0) > workoutVolumeGrams($1) }
        case .power:    ranked = result.sorted { workoutTopE1RM($0) > workoutTopE1RM($1) }
        case .sets:     ranked = result.sorted { workoutSetCount($0) > workoutSetCount($1) }
        case .reps:     ranked = result.sorted { workoutRepCount($0) > workoutRepCount($1) }
        }
        return ascending ? ranked.reversed() : ranked
    }

    private func workoutRepCount(_ w: Workout) -> Int {
        workingSets(w).reduce(0) { $0 + $1.reps }
    }

    /// Distinct gyms present in history — one filter chip each.
    private var presentGyms: [String] {
        Array(Set(workouts.compactMap(\.gymNameSnapshot))).sorted()
    }

    // MARK: Per-workout metrics (computed for sorting; history is small)

    private func workingSets(_ w: Workout) -> [SetEntry] {
        w.orderedExercises.flatMap { $0.orderedSets }.filter { !$0.isWarmup }
    }
    private func workoutVolumeGrams(_ w: Workout) -> Int {
        workingSets(w).reduce(0) { $0 + $1.weightGrams * $1.reps }
    }
    private func workoutSetCount(_ w: Workout) -> Int { workingSets(w).count }
    private func workoutTopE1RM(_ w: Workout) -> Int {
        workingSets(w).map { ProgressEngine.e1RMGrams(weightGrams: $0.weightGrams, reps: $0.reps) }.max() ?? 0
    }

    private var monthGroups: [(key: Date, workouts: [Workout])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: displayedWorkouts) { workout in
            calendar.dateInterval(of: .month, for: workout.startedAt)?.start ?? workout.startedAt
        }
        return grouped.keys.sorted(by: >).map { (key: $0, workouts: grouped[$0] ?? []) }
    }

    private func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(HistorySort.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Divider()
                Toggle(isOn: $ascending) {
                    Label("Ascending", systemImage: "arrow.up")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
    }

    // MARK: Filter bar (quick chips + a live count/tonnage readout)

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("ALL", active: filter == .all) { filter = .all }
                    filterChip("RATED", active: filter == .rated) { filter = .rated }
                    filterChip("PRS", active: filter == .prs) { filter = .prs }
                    filterChip("CASUAL", active: filter == .casual) { filter = .casual }
                    ForEach(presentGyms, id: \.self) { gym in
                        filterChip(gym.uppercased(), active: filter == .gym(gym)) { filter = .gym(gym) }
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 6) {
                Text("\(displayedWorkouts.count) SHOWN")
                Text("·").foregroundStyle(SettColor.iron)
                Text("\(tonnageText) \(services.settings.unit.symbol.uppercased()) TOTAL")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .kerning(1)
            .foregroundStyle(SettColor.ash)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background {
            Rectangle().fill(TimeChamber.void.opacity(0.6)).ignoresSafeArea(edges: .top)
            Rectangle().fill(SettColor.cardBorder.opacity(0.5)).frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func filterChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(active ? SettColor.etch : SettColor.ash)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background {
                    if active { Capsule().fill(SettColor.heroCyan) }
                    else { Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var tonnageText: String {
        let grams = displayedWorkouts.reduce(0) { $0 + workoutVolumeGrams($1) }
        return WeightFormat.compactTonnage(grams: grams, unit: services.settings.unit)
    }

    // MARK: Rows

    private func row(_ workout: Workout) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack(spacing: 12) {
                if let first = workout.orderedExercises.first {
                    ExerciseIcon(name: first.exerciseNameSnapshot,
                                 equipment: first.equipment,
                                 muscle: first.muscle,
                                 size: 40, color: SettColor.heroCyan)
                } else {
                    // Fixed 40pt slot so rows keep one grid even with no exercises.
                    SettSigil(size: 22, color: SettColor.iron.opacity(0.6))
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                    Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let rating = workout.ratingHalfStars, rating > 0 {
                        // Gold audit: a rating is effort, not power/reward — ki cyan.
                        StarRatingRow(halfStars: rating)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(WorkoutFormat.duration(workout.durationSeconds))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if workout.isCasual {
                        // Casual sessions are off the record — the engine returns (0,0)
                        // for them, so "+0 lb" would be a lie. Say what it is instead.
                        Text("CASUAL")
                            .font(.caption2.weight(.bold))
                            .kerning(0.5)
                            .foregroundStyle(SettColor.ash)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SettColor.ash.opacity(0.12), in: Capsule())
                    } else if !samples.isEmpty {
                        netChips(ProgressEngine.workoutNet(samples: samples, workoutID: workout.id),
                                 phase: workout.phase)
                    }
                    if let count = badgeCounts[workout.id], count > 0 {
                        Label("\(count)", systemImage: "medal.fill")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.saiyanGold)
                            .accessibilityLabel("\(count) badge\(count == 1 ? "" : "s") earned")
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(workout)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Net vs previous same-exercise sessions — BOTH deltas (reps + weight), matching
    /// the home strip's pair. Green up, red down, cyan NEW. On a cut workout a lighter
    /// session is expected — neutral ash, never red (the tenet).
    @ViewBuilder
    private func netChips(_ net: NetSummary, phase: TrainingPhase) -> some View {
        if net.isNew {
            Text("NEW")
                .foregroundStyle(SettColor.heroCyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(SettColor.heroCyan.opacity(0.15), in: Capsule())
                .font(.caption2.weight(.bold))
                .monospacedDigit()
        } else {
            HStack(spacing: 4) {
                netChip(value: net.reps, suffix: "reps", phase: phase)
                netChip(value: netDisplayValue(net.volumeGrams), suffix: services.settings.unit.symbol,
                        phase: phase)
            }
        }
    }

    private func netChip(value: Int, suffix: String, phase: TrainingPhase) -> some View {
        let negativeColor = phase == .cutting ? SettColor.ash : SettColor.negative
        let color = value >= 0 ? SettColor.positive : negativeColor
        return Text("\(value >= 0 ? "+" : "")\(value) \(suffix)")
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .font(.caption2.weight(.bold))
            .monospacedDigit()
    }

    private func netDisplayValue(_ grams: Int) -> Int {
        Int((Double(grams) / services.settings.unit.gramsPerUnit).rounded())
    }

    private var badgeCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for award in badgeAwards {
            guard let workoutID = award.workoutID else { continue }
            counts[workoutID, default: 0] += 1
        }
        return counts
    }

    // MARK: Data

    private func refreshSamples() {
        samples = SampleExtractor.setSamples(context: modelContext)
    }

    private func delete(_ workout: Workout) {
        // Route through the store so the workout's child exercises + sets are tombstoned
        // too (not left live under a deleted parent).
        services.session.deleteWorkout(workout)
        refreshSamples()
    }
}

