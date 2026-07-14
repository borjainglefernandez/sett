import SwiftUI
import SwiftData
import SettCore

// MARK: - Gym picker (workout location — active session AND finished-workout edit)

/// Pick, forge, or clear the gym a workout belongs to. Both the active session's
/// overview and the finished-workout editor present this same sheet, so location
/// finally has one consistent home (it used to render only on demo data).
struct GymPickerSheet: View {
    /// The workout's current gym, if any — shows the check.
    let currentID: UUID?
    /// nil ⇒ user chose "No location".
    let onPick: (Gym?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var gyms: [Gym]
    @State private var newName = ""
    @FocusState private var newNameFocused: Bool

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
                        onPick(nil)
                        dismiss()
                    }
                    ForEach(gyms) { gym in
                        row(title: gym.name,
                            icon: gym.isHome ? "house.fill" : "mappin.and.ellipse",
                            isOn: gym.id == currentID) {
                            onPick(gym)
                            dismiss()
                        }
                    }
                }
                Section {
                    HStack(spacing: 10) {
                        TextField("Gym name", text: $newName)
                            .focused($newNameFocused)
                            .textInputAutocapitalization(.words)
                            .onSubmit(createGym)
                        Button("Add") { createGym() }
                            .fontWeight(.semibold)
                            .disabled(trimmedNewName.isEmpty)
                    }
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
                    .foregroundStyle(.primary)
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
        let gym = Gym(name: name, latitude: 0, longitude: 0)
        modelContext.insert(gym)
        try? modelContext.save()
        Haptics.success()
        onPick(gym)
        dismiss()
    }
}
