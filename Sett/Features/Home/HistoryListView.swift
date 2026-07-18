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

    /// Per-workout volume/sets/reps/top-e1RM, traversed ONCE (refreshMetrics) rather than
    /// re-summed over every workout's orderedExercises → orderedSets on each render — that
    /// per-frame relationship walk (via the tonnage total + metric sorts) pinned a CPU core
    /// when a navigation push kept this list re-rendering. Finished workouts are immutable.
    private struct WorkoutMetrics { var volume = 0; var sets = 0; var reps = 0; var topE1RM = 0 }
    @State private var metrics: [UUID: WorkoutMetrics] = [:]

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
                }
            } else {
                Section {
                    ForEach(displayedWorkouts) { workout in
                        row(workout)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // The Menu's Picker/Toggle mutate the bindings directly — animate the
        // resulting reshuffle at the List, matching the chips' withAnimation.
        .animation(.snappy, value: sort)
        .animation(.snappy, value: ascending)
        .dungeonBackground()
        .safeAreaInset(edge: .top, spacing: 0) { filterBar }
        .overlay {
            if workouts.isEmpty {
                EmptyChamber(title: "No workouts yet",
                             message: "Your history writes itself.")
            } else if displayedWorkouts.isEmpty && !searchText.isEmpty {
                EmptyChamber(title: "No match",
                             message: "No workout named \u{201C}\(searchText)\u{201D}.")
            } else if displayedWorkouts.isEmpty {
                EmptyChamber(title: "No workouts match",
                             message: "No sessions fit this filter.",
                             actionLabel: "Show all") { select(.all) }
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

    /// Distinct gyms present in history — one filter chip each.
    private var presentGyms: [String] {
        Array(Set(workouts.compactMap(\.gymNameSnapshot))).sorted()
    }

    // MARK: Per-workout metrics — read from the `metrics` cache (never the DB, per render)

    private func workoutVolumeGrams(_ w: Workout) -> Int { metrics[w.id]?.volume ?? 0 }
    private func workoutSetCount(_ w: Workout) -> Int { metrics[w.id]?.sets ?? 0 }
    private func workoutRepCount(_ w: Workout) -> Int { metrics[w.id]?.reps ?? 0 }
    private func workoutTopE1RM(_ w: Workout) -> Int { metrics[w.id]?.topE1RM ?? 0 }

    /// Traverse every finished workout's sets ONCE into `metrics`. Score power on
    /// EFFECTIVE load (bodyweight equipment adds the lifter's weight), matching
    /// ExerciseCard.e1RM. Called on appear and after a delete — never during body.
    private func refreshMetrics() {
        var next: [UUID: WorkoutMetrics] = [:]
        for workout in workouts {
            var m = WorkoutMetrics()
            var top = 0
            for exercise in workout.orderedExercises {
                for set in exercise.orderedSets where !set.isWarmup {
                    m.volume += set.weightGrams * set.reps
                    m.sets += 1
                    m.reps += set.reps
                    let e1rm = ProgressEngine.e1RMGrams(
                        weightGrams: LoadMath.effectiveWeightGrams(
                            addedGrams: set.weightGrams, equipment: exercise.equipment,
                            bodyweightGrams: workout.bodyweightGrams),
                        reps: set.reps)
                    if e1rm > top { top = e1rm }
                }
            }
            m.topE1RM = top
            next[workout.id] = m
        }
        metrics = next
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
                    FilterChip("ALL", active: filter == .all) { select(.all) }
                    FilterChip("RATED", active: filter == .rated) { select(.rated) }
                    FilterChip("PRS", active: filter == .prs) { select(.prs) }
                    FilterChip("CASUAL", active: filter == .casual) { select(.casual) }
                    ForEach(presentGyms, id: \.self) { gym in
                        FilterChip(gym, active: filter == .gym(gym)) { select(.gym(gym)) }
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 6) {
                Text("\(displayedWorkouts.count) SHOWN")
                    .contentTransition(.numericText())
                Text("·").foregroundStyle(SettColor.iron)
                Text("\(tonnageText) \(services.settings.unit.symbol.uppercased()) TOTAL")
                    .contentTransition(.numericText())
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

    /// One path for every chip tap: animate the reshuffle, then click.
    private func select(_ newFilter: QuickFilter) {
        withAnimation(.snappy) { filter = newFilter }
        Haptics.selection()
    }

    private var tonnageText: String {
        let grams = displayedWorkouts.reduce(0) { $0 + workoutVolumeGrams($1) }
        return WeightFormat.compactTonnage(grams: grams, unit: services.settings.unit)
    }

    // MARK: Rows

    /// Each workout is its own HUD slab on the clear chamber (RoutineListView's
    /// hosting pattern) instead of a stock grouped-list cell.
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
                        .foregroundStyle(SettColor.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(SettColor.ash)
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
                        .foregroundStyle(SettColor.ash)
                    if workout.isCasual {
                        // Casual sessions are off the record — the engine returns (0,0)
                        // for them, so "+0 lb" would be a lie. Say what it is instead.
                        StatusChip("CASUAL")
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
            .hudCard()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
        refreshMetrics()
    }

    private func delete(_ workout: Workout) {
        // Destroying a session is the weightiest row action here, yet it was the one
        // commit in the app with no tactile confirmation. Match the gym-delete's weight.
        Haptics.medium()
        // Route through the store so the workout's child exercises + sets are tombstoned
        // too (not left live under a deleted parent).
        services.session.deleteWorkout(workout)
        refreshSamples()
    }
}

