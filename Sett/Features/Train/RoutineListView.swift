import SwiftUI
import SwiftData
import SettCore

/// Routine cards: name, scheduled-day chips, exercise count, and a play button
/// that starts the routine immediately. Tap a card to edit; swipe to soft-delete.
struct RoutineListView: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query private var routines: [Routine]

    init() {
        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])
    }

    var body: some View {
        Group {
            if routines.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(routines) { routine in
                        row(routine)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    softDelete(routine)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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

    // MARK: Row — a sleek realm card (the routine's domain as the backdrop; a
    // hidden NavigationLink drives edit-on-tap while the play button starts it)

    private func row(_ routine: Routine) -> some View {
        ZStack {
            NavigationLink {
                RoutineEditorView(routine: routine)
            } label: {
                EmptyView()
            }
            .opacity(0)
            .accessibilityLabel(routine.name)
            .accessibilityHint("Edits the routine")

            ZStack {
                Image(domainAsset(routine))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                // Legibility: darker on the left (text) easing to a lighter reveal
                // of the realm on the right behind the play button.
                LinearGradient(colors: [.black.opacity(0.82), .black.opacity(0.62), .black.opacity(0.3)],
                               startPoint: .leading, endPoint: .trailing)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(routine.name)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                        dayChips(mask: routine.daysOfWeekMask)
                        Text(exerciseCountText(routine))
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer(minLength: 8)
                    playButton(routine)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .frame(height: 118)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        }
    }

    /// The realm image behind a routine: its own domain, else the app default.
    private func domainAsset(_ routine: Routine) -> String {
        ChamberBackground.resolve(routine.domainRaw ?? services.settings.chamberBackground).assetName
    }

    @ViewBuilder
    private func dayChips(mask: Int) -> some View {
        if mask == 0 {
            Text("No scheduled days")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        } else {
            HStack(spacing: 5) {
                ForEach(TrainDays.sundayFirstOrder, id: \.self) { day in
                    if TrainDays.isSet(mask, day: day) {
                        Text(TrainDays.shortNames[day])
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.18), in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5) }
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
                .font(.title3.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 4)
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
