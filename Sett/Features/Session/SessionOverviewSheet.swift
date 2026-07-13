import SwiftUI
import SettCore
import UniformTypeIdentifiers

/// Overview state (v3.1): the old exercise-card list survives as a sheet — the
/// toolbox, not the workspace. Add exercises, review every logged set, edit notes
/// and machine setups. Keeps the normal Dark Chamber styling; incognito rules apply
/// to the player behind it, not here.
struct SessionOverviewSheet: View {
    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingExercisePicker = false
    /// Reorder mode (Mode B): swaps the card ScrollView for a native reorderable List
    /// with a scope toggle — the one place `List`/`.onMove` shines (dedicated, un-nested).
    @State private var isReordering = false
    @State private var reorderScope: ReorderScope = .exercises
    /// The exercise card currently lifted for a long-press drag reorder.
    @State private var draggingExercise: WorkoutExercise?
    /// The sheet gets its own emitter so combat text from SetEntryRow commits rises
    /// over the sheet, not under it on the player root.
    @State private var combatText = CombatTextEmitter()

    private enum ReorderScope: Hashable { case exercises, sets }
    private var unit: WeightUnit { services.settings.unit }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = session.activeWorkout {
                    if isReordering { reorderList(workout) } else { list(workout) }
                } else {
                    Color.clear
                }
            }
            .dungeonBackground()
            // The rest clock lives full-screen in RestOverlayView BEHIND this sheet, so
            // it vanishes exactly when you open the toolbox — usually DURING rest. Pin a
            // slim rest strip up top so the one time-critical number is always here too.
            // While reordering, that slot holds the scope toggle instead.
            .safeAreaInset(edge: .top, spacing: 0) {
                if isReordering {
                    scopePicker
                } else if session.isResting {
                    restStrip
                }
            }
            .navigationTitle(isReordering ? "Reorder" : (session.activeWorkout?.title ?? "Workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingExercisePicker) {
                ExercisePickerSheet()
            }
            .onAppear {
                #if DEBUG
                if let scope = ProcessInfo.processInfo.environment["SETT_DEBUG_REORDER"] {
                    reorderScope = scope == "sets" ? .sets : .exercises
                    isReordering = true
                }
                #endif
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Toolbar — Reorder ⇄ Done

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isReordering {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { withAnimation { isReordering = false } }
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation { isReordering = true }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(session.activeWorkout?.orderedExercises.isEmpty ?? true)
                .accessibilityLabel("Reorder exercises and sets")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var scopePicker: some View {
        Picker("Reorder", selection: $reorderScope) {
            Text("Exercises").tag(ReorderScope.exercises)
            Text("Sets").tag(ReorderScope.sets)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(alignment: .bottom) {
            Rectangle().fill(TimeChamber.void.opacity(0.94)).ignoresSafeArea(edges: .top)
            Rectangle().fill(SettColor.heroCyan.opacity(0.25)).frame(height: 1)
        }
    }

    // MARK: Reorder list (Mode B) — native List + .onMove, dungeon showing through

    private func reorderList(_ workout: Workout) -> some View {
        List {
            switch reorderScope {
            case .exercises:
                ForEach(workout.orderedExercises, id: \.id) { we in
                    reorderExerciseRow(we)
                }
                .onMove { session.moveExercise(in: workout, from: $0, to: $1) }
            case .sets:
                ForEach(workout.orderedExercises.filter { !$0.orderedSets.isEmpty }, id: \.id) { we in
                    Section {
                        ForEach(we.orderedSets, id: \.id) { set in
                            reorderSetRow(set, in: we)
                        }
                        .onMove { session.moveSet(in: we, from: $0, to: $1) }
                    } header: {
                        Text(we.exerciseNameSnapshot.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .kerning(1.5)
                            .foregroundStyle(SettColor.ash)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    private func reorderExerciseRow(_ we: WorkoutExercise) -> some View {
        let count = we.orderedSets.filter { !$0.isWarmup }.count
        return HStack(spacing: 12) {
            ExerciseIcon(name: we.exerciseNameSnapshot, equipment: we.equipment,
                         muscle: we.muscle, size: 40, color: SettColor.heroCyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(we.exerciseNameSnapshot.uppercased())
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(count) SET\(count == 1 ? "" : "S")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(TimeChamber.void.opacity(0.72))
            shape.strokeBorder(SettColor.cardBorder.opacity(0.5), lineWidth: 1)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 8))
    }

    private func reorderSetRow(_ set: SetEntry, in we: WorkoutExercise) -> some View {
        HStack(spacing: 0) {
            Text(setBadge(for: set, in: we))
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(set.isWarmup ? SettColor.ash : SettColor.heroCyan)
                .frame(width: SetRowGrid.badge, height: SetRowGrid.badge)
                .background { Circle().strokeBorder(SettColor.iron.opacity(0.6), lineWidth: 1) }
            Spacer().frame(width: SetRowGrid.badgeGap)
            setValueColumns(weightText: WeightFormat.compactWithUnit(grams: set.weightGrams, unit: unit),
                            repsText: "\(set.reps)", valueColor: SettColor.bone, weight: .semibold)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SetRowGrid.hPad)
        .frame(height: SetRowGrid.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TimeChamber.void.opacity(0.5))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 8))
    }

    /// Working-set ordinal for the badge, or "W" for a warm-up.
    private func setBadge(for set: SetEntry, in we: WorkoutExercise) -> String {
        if set.isWarmup { return "W" }
        var n = 0
        for s in we.orderedSets where !s.isWarmup {
            n += 1
            if s.id == set.id { return "\(n)" }
        }
        return "\(n)"
    }

    // MARK: Rest strip — remaining time derived from restEndsAt (never accumulated)

    @ViewBuilder
    private var restStrip: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = restRemaining(at: context.date)
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TimeChamber.scouterGreen)
                Text("REST")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(SettColor.ash)
                Text(restTimeText(remaining))
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                Spacer(minLength: 8)
                restButton("−5") { session.adjustRest(by: -5) }
                restButton("SKIP") { session.skipRest() }
                restButton("+5") { session.adjustRest(by: 5) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(alignment: .bottom) {
                Rectangle().fill(TimeChamber.void.opacity(0.94)).ignoresSafeArea(edges: .top)
                Rectangle().fill(TimeChamber.scouterGreen.opacity(0.4)).frame(height: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest, \(restTimeText(remaining)) remaining")
        }
    }

    private func restButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(TimeChamber.scouterGreen)
                .frame(minWidth: 42, minHeight: 32)
                .background { Capsule().strokeBorder(TimeChamber.scouterGreen.opacity(0.4), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func restRemaining(at date: Date) -> Int {
        guard let ends = session.restEndsAt else { return 0 }
        return max(0, Int(ends.timeIntervalSince(date).rounded(.up)))
    }

    private func restTimeText(_ remaining: Int) -> String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func list(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(workout.orderedExercises) { workoutExercise in
                    ExerciseCard(workoutExercise: workoutExercise)
                        // Long-press to lift a card, drag to reorder exercises live.
                        .opacity(draggingExercise?.id == workoutExercise.id ? 0.35 : 1)
                        .onDrag {
                            draggingExercise = workoutExercise
                            return NSItemProvider(object: workoutExercise.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(
                            target: workoutExercise, items: workout.orderedExercises,
                            dragging: $draggingExercise,
                            move: { session.moveExercise(in: workout, from: $0, to: $1) }))
                }
                Button {
                    isShowingExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                if workout.orderedExercises.isEmpty {
                    // Quiet hint for the stark empty chamber — ash, not cyan.
                    VStack(spacing: 8) {
                        SettSigil(size: 28, color: SettColor.ash)
                        Text("The Scanner is waiting.")
                            .font(.footnote.monospaced())
                            .foregroundStyle(SettColor.ash)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
        }
        .combatTextEmitter(combatText)
        .environment(combatText)
    }
}
