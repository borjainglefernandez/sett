import SwiftUI
import SwiftData
import SettCore

/// Sheet from the Home gear (design-ux §2): units, weight increment, default
/// rest, integrations, invite a friend, about. Account rows arrive with sync.
struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 1.25 lb / 2.5 lb / 5 lb expressed in canonical grams.
    private static let standardIncrementsGrams = [567, 1134, 2268]

    var body: some View {
        @Bindable var settings = services.settings
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Weight unit", selection: $settings.unit) {
                        Text("lb").tag(WeightUnit.lb)
                        Text("kg").tag(WeightUnit.kg)
                    }
                    .pickerStyle(.segmented)
                    Picker("Weight increment", selection: $settings.incrementGrams) {
                        ForEach(incrementOptions, id: \.self) { grams in
                            Text(settings.displayWeight(grams)).tag(grams)
                        }
                    }
                    Stepper(value: $settings.defaultRestSeconds, in: 30...300, step: 15) {
                        LabeledContent("Default rest", value: restText)
                    }
                }

                Section("Integrations") {
                    LabeledContent {
                        Text("coming with sync")
                            .font(.footnote)
                    } label: {
                        Label("Connect Oura", systemImage: "bed.double.fill")
                    }
                    .foregroundStyle(.secondary)
                }

                Section("Friends") {
                    ShareLink(item: inviteMessage) {
                        Label("Invite a Friend", systemImage: "person.badge.plus")
                    }
                }

                #if DEBUG
                Section("Debug") {
                    Button("Seed demo data") {
                        DemoData.seedIfRequested(context: modelContext)
                        services.progression.recompute(context: modelContext)
                        Haptics.success()
                    }
                }
                #endif

                Section("About") {
                    LabeledContent("Version", value: versionText)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: settings.unit) { _, newUnit in
                // Changing the unit resets the increment to that unit's default step.
                settings.incrementGrams = newUnit.defaultIncrementGrams
                Haptics.selection()
            }
        }
    }

    /// The standard steps, plus the current value if it isn't one of them
    /// (e.g. the 1250 g kg-default) so the picker always has a selected row.
    private var incrementOptions: [Int] {
        var options = Self.standardIncrementsGrams
        if !options.contains(services.settings.incrementGrams) {
            options.append(services.settings.incrementGrams)
            options.sort()
        }
        return options
    }

    private var restText: String {
        "\(services.settings.defaultRestSeconds) s"
    }

    private var inviteMessage: String {
        "Join me on sett — my invite code is SAIYAN-XXXXXX"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
