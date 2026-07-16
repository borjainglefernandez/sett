import SwiftUI
import SwiftData
import SettCore

// MARK: - Gym picker (workout location — active session AND finished-workout edit)

/// The icon palette a gym can wear — shared by the NEW GYM composer and the
/// change-icon sheet (file-scoped so both read one list).
private let gymSymbols = [
    "mappin.and.ellipse", "house.fill", "dumbbell.fill", "building.2.fill",
    "figure.strengthtraining.traditional", "tree.fill", "bolt.fill", "flame.fill", "star.fill",
]

/// Pick, forge, or clear the gym a workout belongs to. Both the active session's
/// overview and the finished-workout editor present this same sheet, so location
/// finally has one consistent home (it used to render only on demo data).
/// Long-press a gym for management: rename, change icon, delete.
struct GymPickerSheet: View {
    /// The workout's current gym, if any — shows the check.
    let currentID: UUID?
    /// nil ⇒ user chose "No location".
    let onPick: (Gym?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var gyms: [Gym]
    @State private var newName = ""
    @State private var newSymbol = "mappin.and.ellipse"
    @FocusState private var newNameFocused: Bool
    /// Gym under management (context menu targets).
    @State private var renamingGym: Gym?
    @State private var iconEditingGym: Gym?
    @State private var deletingGym: Gym?

    init(currentID: UUID?, onPick: @escaping (Gym?) -> Void) {
        self.currentID = currentID
        self.onPick = onPick
        let gymFilter = #Predicate<Gym> { $0.deletedAt == nil }
        _gyms = Query(filter: gymFilter, sort: [SortDescriptor(\Gym.name)])
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "No location", icon: "mappin.slash", isOn: currentID == nil) {
                        Haptics.selection()
                        onPick(nil)
                        dismiss()
                    }
                    ForEach(gyms) { gym in
                        row(title: gym.name,
                            icon: gym.symbolName,
                            isOn: gym.id == currentID) {
                            Haptics.selection()
                            onPick(gym)
                            dismiss()
                        }
                        .contextMenu {
                            Button { renamingGym = gym } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button { iconEditingGym = gym } label: {
                                Label("Change icon", systemImage: "circle.grid.2x2")
                            }
                            Button(role: .destructive) { deletingGym = gym } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: newSymbol)
                            .font(.subheadline)
                            .foregroundStyle(SettColor.heroCyan)
                            .frame(width: 24)
                        TextField("Gym name", text: $newName)
                            .focused($newNameFocused)
                            .textInputAutocapitalization(.words)
                            .onSubmit(createGym)
                        Button("Add") { createGym() }
                            .fontWeight(.semibold)
                            .disabled(trimmedNewName.isEmpty)
                    }
                    GymSymbolPaletteRow(selection: $newSymbol)
                } header: {
                    Eyebrow("NEW GYM")
                }
                .listRowBackground(SettColor.card)
            }
            .scrollContentBackground(.hidden)
            .dungeonBackground()
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $renamingGym) { gym in
            GymRenameSheet(initialName: gym.name) { name in
                rename(gym, to: name)
            }
        }
        .sheet(item: $iconEditingGym) { gym in
            GymIconSheet(initialSymbol: gym.symbolName) { symbol in
                setIcon(gym, symbol: symbol)
            }
        }
        .confirmationDialog("Delete this gym?",
                            isPresented: Binding(get: { deletingGym != nil },
                                                 set: { if !$0 { deletingGym = nil } }),
                            titleVisibility: .visible,
                            presenting: deletingGym) { gym in
            Button("Delete Gym", role: .destructive) { softDelete(gym) }
        } message: { _ in
            Text("Past workouts keep their location label.")
        }
    }

    private func row(title: String, icon: String, isOn: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(SettColor.heroCyan)
                    .frame(width: 24)
                Text(title)
                    .foregroundStyle(SettColor.bone)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SettColor.heroCyan)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(SettColor.card)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Manual gyms carry no coordinates (0,0) — the map fields exist for the future
    /// Chamber Log; a name is all a workout label needs.
    private func createGym() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }
        let gym = Gym(name: name, latitude: 0, longitude: 0, symbolName: newSymbol)
        modelContext.insert(gym)
        try? modelContext.save()
        Haptics.success()
        onPick(gym)
        dismiss()
    }

    // MARK: Gym management (rename / icon / delete)

    /// Rename ripples into the denormalized snapshots (matched by gymID) so history
    /// rows and routine defaults agree with the picker instead of showing stale names.
    private func rename(_ gym: Gym, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        gym.name = trimmed
        gym.updatedAt = .now
        gym.needsPush = true
        let gymID: UUID? = gym.id
        let workouts = (try? modelContext.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.gymID == gymID }))) ?? []
        for workout in workouts {
            workout.gymNameSnapshot = trimmed
            workout.updatedAt = .now
            workout.needsPush = true
        }
        let routines = (try? modelContext.fetch(FetchDescriptor<Routine>(
            predicate: #Predicate { $0.defaultGymID == gymID }))) ?? []
        for routine in routines {
            routine.defaultGymNameSnapshot = trimmed
            routine.updatedAt = .now
            routine.needsPush = true
        }
        try? modelContext.save()
        Haptics.selection()
    }

    private func setIcon(_ gym: Gym, symbol: String) {
        gym.symbolName = symbol
        gym.updatedAt = .now
        gym.needsPush = true
        try? modelContext.save()
        Haptics.selection()
    }

    /// Soft-delete only — workouts keep their gymNameSnapshot, so history still
    /// reads the place it happened; only the picker forgets it.
    private func softDelete(_ gym: Gym) {
        gym.deletedAt = .now
        gym.updatedAt = .now
        gym.needsPush = true
        try? modelContext.save()
        Haptics.medium()
    }
}

// MARK: - Icon palette row (shared: NEW GYM composer + change-icon sheet)

private struct GymSymbolPaletteRow: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(gymSymbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                        Haptics.selection()
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(selection == symbol ? SettColor.etch : SettColor.heroCyan)
                            .frame(width: 38, height: 38)
                            .background(selection == symbol ? SettColor.heroCyan : SettColor.cardNested,
                                        in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gym icon")
                    .accessibilityAddTraits(selection == symbol ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Rename sheet (one TextField in the shared shell)

private struct GymRenameSheet: View {
    let initialName: String
    let onSave: (String) -> Void

    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ChamberSheet(title: "Rename Gym",
                     canCommit: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                     onCommit: { onSave(name) }) {
            TextField("Gym name", text: $name)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(SettColor.bone)
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(12)
                .background(SettColor.cardNested, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .presentationDetents([.height(220)])
        .onAppear {
            name = initialName
            isFocused = true
        }
    }
}

// MARK: - Icon sheet (the same palette row, pointed at an existing gym)

private struct GymIconSheet: View {
    let initialSymbol: String
    let onSave: (String) -> Void

    @State private var symbol = "mappin.and.ellipse"

    var body: some View {
        ChamberSheet(title: "Gym Icon", onCommit: { onSave(symbol) }) {
            GymSymbolPaletteRow(selection: $symbol)
        }
        .presentationDetents([.height(200)])
        .onAppear { symbol = initialSymbol }
    }
}
