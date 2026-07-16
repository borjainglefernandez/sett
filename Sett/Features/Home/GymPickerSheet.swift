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
    @State private var newSymbol = "mappin.and.ellipse"
    @FocusState private var newNameFocused: Bool

    /// The icon palette a new gym can wear.
    private static let gymSymbols = [
        "mappin.and.ellipse", "house.fill", "dumbbell.fill", "building.2.fill",
        "figure.strengthtraining.traditional", "tree.fill", "bolt.fill", "flame.fill", "star.fill",
    ]

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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Self.gymSymbols, id: \.self) { symbol in
                                Button {
                                    newSymbol = symbol
                                    Haptics.selection()
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 15))
                                        .foregroundStyle(newSymbol == symbol ? SettColor.etch : SettColor.heroCyan)
                                        .frame(width: 38, height: 38)
                                        .background(newSymbol == symbol ? SettColor.heroCyan : SettColor.cardNested,
                                                    in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Gym icon")
                                .accessibilityAddTraits(newSymbol == symbol ? [.isSelected] : [])
                            }
                        }
                        .padding(.vertical, 2)
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
        let gym = Gym(name: name, latitude: 0, longitude: 0, symbolName: newSymbol)
        modelContext.insert(gym)
        try? modelContext.save()
        Haptics.success()
        onPick(gym)
        dismiss()
    }
}
