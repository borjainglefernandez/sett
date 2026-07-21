import SwiftUI
import SettCore

/// The ONE match rule for the exercise pickers, so the visible list and each sheet's
/// "no match → Create" overlay can never disagree about whether a search found anything.
enum ExerciseNameFilter {
    static func apply(_ exercises: [Exercise], query: String) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedStandardContains(query) }
    }
}

// MARK: - The app's ONE muscle-picker vocabulary (assign grids, filter chips, sections)

extension Muscle {
    /// The groups a user can ASSIGN or FILTER by: the ten landmark groups plus the
    /// `.other` catch-all. Legacy `.legs` is deliberately absent — the bucket split
    /// into glutes/hamstrings/quadriceps/calves, so existing legs-tagged lifts keep
    /// working but nobody can forge a new one.
    static let pickable: [Muscle] = volumeGroups + [.other]

    /// Section/group ordering for lists that show EXISTING data — the pickable order
    /// with the legacy bucket slotted before the catch-all, so stray legs-tagged
    /// customs still get a home instead of vanishing.
    static let displayOrder: [Muscle] = volumeGroups + [.legs, .other]
}

// MARK: - Muscle-grouped exercise picker (collapsed groups, tap to expand)

/// The condensed body of both "add exercise" sheets. Instead of one long flat list
/// of every lift, it opens as collapsed muscle-group rows (emblem + name + count);
/// tapping a group reveals its exercises in place. Searching flattens to a
/// filtered result list (grouping would hide matches behind collapsed headers).
///
/// Each host sheet supplies its own trailing row via `row` — a single-tap add for the
/// session, a multi-select checkmark for the routine editor — so the grouping/expansion
/// logic lives in exactly one place.
struct MuscleGroupedPicker<Row: View, Footer: View>: View {
    /// Pre-filtered (non-archived, deleted-excluded), name-sorted exercises.
    let exercises: [Exercise]
    let searchText: String
    @ViewBuilder let row: (Exercise) -> Row
    /// The "Create custom exercise" affordance, pinned below the groups.
    @ViewBuilder let footer: () -> Footer

    @State private var expanded: Set<Muscle> = []
    /// Header art/text grow with Dynamic Type in step with the exercise rows below them.
    @ScaledMetric(relativeTo: .headline) private var emblemSize: CGFloat = 40

    private var isSearching: Bool { !searchText.isEmpty }

    private var filtered: [Exercise] {
        ExerciseNameFilter.apply(exercises, query: searchText)
    }

    private var grouped: [Muscle: [Exercise]] {
        Dictionary(grouping: filtered, by: \.muscle)
    }

    private var orderedMuscles: [Muscle] {
        Muscle.displayOrder.filter { !(grouped[$0]?.isEmpty ?? true) }
    }

    var body: some View {
        List {
            // One section for all groups — inset-grouped gives every Section its own card
            // with a big gap, which is the opposite of condensed. Contiguous rows in a
            // single card keep the groups tight.
            Section {
                if isSearching {
                    // Flat matches — no headers to hide behind while filtering.
                    ForEach(filtered) { row($0) }
                } else {
                    ForEach(orderedMuscles, id: \.self) { muscle in
                        groupHeader(muscle, count: grouped[muscle]?.count ?? 0)
                        if expanded.contains(muscle) {
                            ForEach(grouped[muscle] ?? []) { exercise in
                                row(exercise)
                                    .padding(.leading, 4)
                                    .listRowBackground(SettColor.cardNested)
                            }
                        }
                    }
                }
            }
            .listRowBackground(SettColor.card)
            // Hide the "Create custom exercise" footer on a search miss, where the host
            // sheet already shows an EmptyChamber "Forge" button — no double affordance.
            if !(isSearching && filtered.isEmpty) {
                Section { footer() }
                    .listRowBackground(SettColor.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(.snappy(duration: 0.22), value: expanded)
        .animation(.snappy(duration: 0.2), value: searchText)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["SETT_DEBUG_EXPAND"] != nil {
                expanded = Set(orderedMuscles.prefix(1))
            }
        }
        #endif
    }

    // MARK: Group header — emblem + name + count, the whole row toggles the group.

    private func groupHeader(_ muscle: Muscle, count: Int) -> some View {
        Button {
            if expanded.contains(muscle) { expanded.remove(muscle) }
            else { expanded.insert(muscle) }
            Haptics.selection()
        } label: {
            HStack(spacing: 12) {
                ExerciseIcon(name: "", equipment: .bodyweight, muscle: muscle,
                             size: emblemSize, color: SettColor.heroCyan)
                Text(muscle.displayName.uppercased())
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.bone)
                Spacer()
                Text("\(count)")
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.ash)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
                    .rotationEffect(.degrees(expanded.contains(muscle) ? 0 : -90))
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(muscle.displayName), \(count) exercise\(count == 1 ? "" : "s")")
        .accessibilityValue(expanded.contains(muscle) ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded.contains(muscle) ? "Hides this group's exercises"
                                                     : "Shows this group's exercises")
    }
}
