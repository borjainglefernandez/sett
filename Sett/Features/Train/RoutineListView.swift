import SwiftUI
import SwiftData
import SettCore
import UniformTypeIdentifiers

private extension View {
    /// Apply drag-reorder modifiers only while the rotation split is being ordered.
    @ViewBuilder
    func ifRotation<Content: View>(_ active: Bool, _ transform: (Self) -> Content) -> some View {
        if active { transform(self) } else { self }
    }
}

/// Routine cards: name, scheduled-day chips, exercise count, and a play button
/// that starts the routine immediately. Tap a card to edit; swipe to soft-delete.
struct RoutineListView: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query private var routines: [Routine]
    @Query private var archivedRoutines: [Routine]

    init() {
        let routineFilter = #Predicate<Routine> { $0.deletedAt == nil && !$0.isArchived }
        _routines = Query(filter: routineFilter, sort: [SortDescriptor(\Routine.orderIndex)])
        let archivedFilter = #Predicate<Routine> { $0.deletedAt == nil && $0.isArchived }
        _archivedRoutines = Query(filter: archivedFilter, sort: [SortDescriptor(\Routine.name)])
    }

    /// The lifted routine card during a rotation-order drag.
    @State private var draggingRoutine: Routine?
    @State private var isArchiveExpanded = false

    var body: some View {
        @Bindable var settings = services.settings
        return Group {
            if routines.isEmpty && archivedRoutines.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow("SCHEDULING")
                            ChamberSegments(selection: $settings.scheduleMode,
                                            options: ScheduleMode.allCases.map { ($0, $0.title) })
                            Text(isRotation
                                 ? "ROTATION — your split in order. Finish the next-up routine and the cycle advances; the day doesn't matter."
                                 : "WEEKDAY — each routine runs on the days you assign it. Today's routine is the one that's up.")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(SettColor.ash)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .hudCard()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                    }
                    ForEach(routines) { routine in
                        row(routine)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .opacity(draggingRoutine?.id == routine.id ? 0.35 : 1)
                            .ifRotation(isRotation) { view in
                                view
                                    .onDrag {
                                        draggingRoutine = routine
                                        return NSItemProvider(object: routine.id.uuidString as NSString)
                                    }
                                    .onDrop(of: [.text], delegate: ReorderDropDelegate(
                                        target: routine, items: Scheduling.orderedActive(routines),
                                        dragging: $draggingRoutine, move: moveRoutine))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    softDelete(routine)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    duplicate(routine)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                Button {
                                    setArchived(routine, true)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                    }
                    if !archivedRoutines.isEmpty {
                        archivedSection
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.snappy, value: isRotation)
                // A drag released over empty space / the header clears the lift so the
                // card never stays stuck at 0.35 opacity.
                .onDrop(of: [.text], isTargeted: nil) { _ in draggingRoutine = nil; return false }
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

            RealmDoorwayCard(asset: domainAsset(routine), emphasized: false, height: 118) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(routine.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    if isRotation {
                        rotationInfo(routine)
                    } else {
                        dayChips(mask: routine.daysOfWeekMask)
                    }
                    Text(exerciseCountText(routine))
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            } accessory: {
                playButton(routine)
            }
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

    // MARK: Rotation ordering

    private var isRotation: Bool { services.settings.scheduleMode == .rotation }
    private var nextUpID: UUID? { Scheduling.nextRoutine(routines, settings: services.settings)?.id }

    /// The split position + a NEXT-UP badge, in place of weekday chips.
    @ViewBuilder
    private func rotationInfo(_ routine: Routine) -> some View {
        let order = Scheduling.orderedActive(routines)
        let pos = (order.firstIndex { $0.id == routine.id } ?? 0) + 1
        HStack(spacing: 8) {
            Text("#\(pos)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            if routine.id == nextUpID {
                StatusChip("NEXT UP", tint: SettColor.heroCyan, filled: true)
            } else {
                Text("in the cycle")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    /// Reorder the split (rotation order = `orderIndex`), densifying + stamping.
    private func moveRoutine(from source: IndexSet, to destination: Int) {
        var ordered = Scheduling.orderedActive(routines)
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, r) in ordered.enumerated() where r.orderIndex != i {
            r.orderIndex = i
            r.updatedAt = .now
            r.needsPush = true
        }
        try? modelContext.save()
        Haptics.selection()
    }

    private func playButton(_ routine: Routine) -> some View {
        Button {
            session.start(routine: routine)
        } label: {
            Image(systemName: "play.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(SettColor.etch)
                .frame(width: 52, height: 52)
                .background(SettColor.heroCyan, in: Circle())
                .shadow(color: SettColor.heroCyan.opacity(0.45), radius: 6)
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityLabel("Start \(routine.name)")
    }

    // MARK: Archive (quiet parking lot — hidden from scheduling, one tap back)

    /// A collapsed row at the list bottom; expanding lists archived routines by
    /// name with an unarchive action. No realm art — these are out of rotation.
    private var archivedSection: some View {
        DisclosureGroup(isExpanded: $isArchiveExpanded) {
            ForEach(archivedRoutines) { routine in
                HStack(spacing: 12) {
                    Text(routine.name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(SettColor.ash)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        setArchived(routine, false)
                    } label: {
                        Text("UNARCHIVE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .kerning(1)
                            .foregroundStyle(SettColor.heroCyan)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .background {
                                Capsule().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Unarchive \(routine.name)")
                }
                .padding(.vertical, 6)
            }
        } label: {
            Eyebrow("ARCHIVED (\(archivedRoutines.count))")
        }
        .tint(SettColor.iron)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 12, trailing: 20))
    }

    /// Flip the archive flag (queries filter it everywhere; history untouched).
    private func setArchived(_ routine: Routine, _ archived: Bool) {
        routine.isArchived = archived
        routine.updatedAt = .now
        routine.needsPush = true
        try? modelContext.save()
        Haptics.light()
    }

    // MARK: Duplicate (Push A → Push B without rebuilding)

    /// Clone a routine and its exercises. The copy starts UNSCHEDULED (days cleared)
    /// so two routines never fight over "today"; the user assigns days when ready.
    private func duplicate(_ routine: Routine) {
        let now = Date.now
        let nextOrder = (routines.map(\.orderIndex).max() ?? -1) + 1
        let copy = Routine(name: "\(routine.name) copy", daysOfWeekMask: 0,
                           orderIndex: nextOrder, now: now)
        copy.domainRaw = routine.domainRaw
        copy.notes = routine.notes
        modelContext.insert(copy)
        for source in routine.orderedExercises {
            guard let exercise = catalogExercise(id: source.exerciseID) else { continue }
            let re = RoutineExercise(orderIndex: source.orderIndex, exercise: exercise,
                                     setCount: source.plannedSetCount, now: now)
            re.restSeconds = source.restSeconds
            re.routine = copy
            modelContext.insert(re)
        }
        try? modelContext.save()
        Haptics.success()
    }

    private func catalogExercise(id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
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
        VStack {
            Spacer()
            EmptyChamber(title: "No routines yet",
                         message: "Build a routine, or Quick Start from Home to train without a plan.") {
                NavigationLink {
                    RoutineEditorView(routine: nil)
                } label: {
                    Text("CREATE ROUTINE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.etch)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(SettColor.heroCyan, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}
