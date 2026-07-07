import SwiftUI
import SwiftData
import SettCore

/// Routine cards: name, scheduled-day chips, exercise count, and a play button
/// that starts the routine immediately. Tap a card to edit; swipe to soft-delete.
struct RoutineListView: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived },
           sort: [SortDescriptor(\Routine.orderIndex)])
    private var routines: [Routine]

    var body: some View {
        Group {
            if routines.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(routines) { routine in
                        row(routine)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    softDelete(routine)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RoutineEditorView(routine: nil)
                } label: {
                    Label("New Routine", systemImage: "plus")
                }
                .accessibilityLabel("New Routine")
            }
        }
    }

    // MARK: Row

    private func row(_ routine: Routine) -> some View {
        NavigationLink {
            RoutineEditorView(routine: routine)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name)
                        .font(.headline)
                    dayChips(mask: routine.daysOfWeekMask)
                    Text(exerciseCountText(routine))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                playButton(routine)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func dayChips(mask: Int) -> some View {
        if mask == 0 {
            Text("No scheduled days")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { day in
                    if TrainDays.isSet(mask, day: day) {
                        Text(TrainDays.shortNames[day])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SettColor.heroCyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(SettColor.heroCyan.opacity(0.15), in: Capsule())
                            .accessibilityLabel(TrainDays.names[day])
                    }
                }
            }
        }
    }

    private func exerciseCountText(_ routine: Routine) -> String {
        let count = routine.orderedExercises.count
        return count == 1 ? "1 exercise" : "\(count) exercises"
    }

    private func playButton(_ routine: Routine) -> some View {
        Button {
            session.start(routine: routine)
        } label: {
            Image(systemName: "play.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(SettColor.heroCyan, in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Start \(routine.name)")
    }

    // MARK: Soft delete (tombstone; history is untouched — loose refs only)

    private func softDelete(_ routine: Routine) {
        let now = Date.now
        routine.deletedAt = now
        routine.updatedAt = now
        routine.needsPush = true
        for routineExercise in routine.exercises where routineExercise.deletedAt == nil {
            routineExercise.deletedAt = now
            routineExercise.updatedAt = now
            routineExercise.needsPush = true
            for plannedSet in routineExercise.plannedSets where plannedSet.deletedAt == nil {
                plannedSet.deletedAt = now
                plannedSet.updatedAt = now
                plannedSet.needsPush = true
            }
        }
        try? modelContext.save()
        Haptics.light()
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 40))
                .foregroundStyle(SettColor.heroCyan)
            Text("No routines yet")
                .font(.title3.bold())
            Text("Build one, or Quick Start and we'll remember it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink {
                RoutineEditorView(routine: nil)
            } label: {
                Text("Create Routine")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Aura.cyan, in: Capsule())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
