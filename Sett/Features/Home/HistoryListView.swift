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
        case rating = "Rating"
        case duration = "Duration"
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
                    Section(monthTitle(group.key)) {
                        ForEach(group.workouts) { workout in
                            row(workout)
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
        }
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
                        StarRatingRow(halfStars: rating)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(WorkoutFormat.duration(workout.durationSeconds))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if !samples.isEmpty {
                        netChip(ProgressEngine.workoutNet(samples: samples, workoutID: workout.id))
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

    /// Net vs previous same-exercise sessions: green up, red down, cyan NEW.
    private func netChip(_ net: NetSummary) -> some View {
        Group {
            if net.isNew {
                Text("NEW")
                    .foregroundStyle(SettColor.heroCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SettColor.heroCyan.opacity(0.15), in: Capsule())
            } else {
                let color = net.volumeGrams >= 0 ? SettColor.positive : SettColor.negative
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
        workout.deletedAt = .now
        workout.updatedAt = .now
        workout.needsPush = true
        try? modelContext.save()
        refreshSamples()
        Haptics.rigid()
    }
}
