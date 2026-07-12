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
        case duration = "Duration"
        case rating = "Rating"
        var id: String { rawValue }
    }

    @State private var sort: HistorySort = .date
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
                            Text(monthTitle(group.key))
                            Spacer()
                            Text("\(group.workouts.count) workout\(group.workouts.count == 1 ? "" : "s")")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
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
        .overlay {
            if workouts.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Your history writes itself.")
                )
            } else if displayedWorkouts.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
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
        switch sort {
        case .date:
            return result // already startedAt desc from the query
        case .rating:
            return result.sorted { ($0.ratingHalfStars ?? -1) > ($1.ratingHalfStars ?? -1) }
        case .duration:
            return result.sorted { $0.durationSeconds > $1.durationSeconds }
        case .volume:
            return result.sorted { workoutVolumeGrams($0) > workoutVolumeGrams($1) }
        case .power:
            return result.sorted { workoutTopE1RM($0) > workoutTopE1RM($1) }
        case .sets:
            return result.sorted { workoutSetCount($0) > workoutSetCount($1) }
        }
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
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
    }

    // MARK: Rows

    private func row(_ workout: Workout) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                    Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let rating = workout.ratingHalfStars, rating > 0 {
                        // Gold audit: a rating is effort, not power/reward — ki cyan.
                        CyanStarRatingRow(halfStars: rating)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(WorkoutFormat.duration(workout.durationSeconds))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if !samples.isEmpty {
                        netChip(ProgressEngine.workoutNet(samples: samples, workoutID: workout.id),
                                phase: workout.phase)
                    }
                    if let count = badgeCounts[workout.id], count > 0 {
                        Label("\(count)", systemImage: "medal.fill")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.saiyanGold)
                            .accessibilityLabel("\(count) badges earned")
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

    /// Net vs previous same-exercise sessions: green up, red down, cyan NEW. On a cut
    /// workout a lighter session is expected — neutral ash, never red (the tenet).
    private func netChip(_ net: NetSummary, phase: TrainingPhase) -> some View {
        Group {
            if net.isNew {
                Text("NEW")
                    .foregroundStyle(SettColor.heroCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SettColor.heroCyan.opacity(0.15), in: Capsule())
            } else {
                let negativeColor = phase == .cutting ? SettColor.ash : SettColor.negative
                let color = net.volumeGrams >= 0 ? SettColor.positive : negativeColor
                Text("\(net.volumeGrams >= 0 ? "+" : "")\(netDisplayValue(net.volumeGrams)) \(services.settings.unit.symbol)")
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
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

// MARK: - Ki-cyan half-star display (gold audit: gold stays the power level's)

/// Same geometry as `StarRatingRow` (WorkoutFormat.swift) but in hero cyan —
/// history ratings are energy spent, not a reward, so they don't wear gold.
private struct CyanStarRatingRow: View {
    let halfStars: Int
    var starSize: CGFloat = 9

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(star))
            }
        }
        .font(.system(size: starSize))
        .foregroundStyle(SettColor.heroCyan)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", Double(halfStars) / 2)) stars")
    }

    private func symbol(_ star: Int) -> String {
        if halfStars >= star * 2 {
            "star.fill"
        } else if halfStars == star * 2 - 1 {
            "star.leadinghalf.filled"
        } else {
            "star"
        }
    }
}
