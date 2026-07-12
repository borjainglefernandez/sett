import SwiftUI
import SwiftData
import SettCore

/// Sheet from the Home gear (design-ux §2): units, weight increment, default
/// rest, integrations, invite a friend, about. Account rows arrive with sync.
/// Native controls (segmented, steppers, share) re-housed in the Dark Chamber:
/// dungeon backdrop, mono ash section headers, rows on the card slab.
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
                Section {
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
                    Stepper(value: $settings.defaultRestSeconds, in: 30...300, step: 5) {
                        LabeledContent("Default rest", value: restText)
                    }
                    Picker("Workout view", selection: $settings.startsInList) {
                        Text("Scanner").tag(false)
                        Text("List").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    sectionHeader("UNITS")
                } footer: {
                    Text("Scanner is the full-screen scouter; List is the overview of every set.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettColor.iron)
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                Section {
                    Picker("Phase", selection: phaseBinding) {
                        ForEach(TrainingPhase.allCases) { phase in
                            Text(phase.title).tag(phase)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        Image(systemName: settings.phase.symbolName)
                            .foregroundStyle(SettColor.heroCyan)
                        Text(settings.phase.creed)
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .foregroundStyle(SettColor.bone)
                    }
                } header: {
                    sectionHeader("TRAINING PHASE")
                } footer: {
                    Text(phaseFooter)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettColor.iron)
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                Section {
                    ChamberDomainStrip(selection: Binding(
                        get: { settings.chamberBackground },
                        set: { if let value = $0 { settings.chamberBackground = value } }
                    ))
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                } header: {
                    sectionHeader("DEFAULT REALM")
                } footer: {
                    Text("Your default training realm. Routines can override it.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettColor.iron)
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                Section {
                    LabeledContent {
                        Text("coming with sync")
                            .font(.footnote)
                    } label: {
                        Label("Connect Oura", systemImage: "bed.double.fill")
                    }
                    .foregroundStyle(SettColor.ash)
                } header: {
                    sectionHeader("INTEGRATIONS")
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                // Invite codes are issued by the (not-yet-wired) backend; sharing a fake
                // CHAMBER-XXXXXX on an invite-only app is worse than nothing, so the row
                // stays hidden until real codes exist. Re-enable by restoring
                // ShareLink(item: inviteMessage) here once the backend issues codes.
                Section {
                    Label("Invites arrive with sync", systemImage: "person.badge.plus")
                        .foregroundStyle(SettColor.ash)
                } header: {
                    sectionHeader("FRIENDS")
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                #if DEBUG
                Section {
                    Button("Seed demo data") {
                        DemoData.seedIfRequested(context: modelContext)
                        services.progression.recompute(context: modelContext)
                        Haptics.success()
                    }
                } header: {
                    sectionHeader("DEBUG")
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)
                #endif

                Section {
                    LabeledContent("Version", value: versionText)
                        .foregroundStyle(SettColor.bone)
                } header: {
                    sectionHeader("ABOUT")
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)
            }
            .scrollContentBackground(.hidden)
            .dungeonBackground()
            .tint(SettColor.heroCyan)
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

    /// The mono small-caps ash convention (NET THIS WEEK, THIS WEEK, …).
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .kerning(1.5)
            .foregroundStyle(SettColor.ash)
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

    private var phaseBinding: Binding<TrainingPhase> {
        Binding(
            get: { services.settings.phase },
            set: {
                services.settings.trainingPhase = $0.rawValue
                services.settings.hasChosenPhase = true
                Haptics.selection()
            }
        )
    }

    private var phaseFooter: String {
        switch services.settings.phase {
        case .cutting: "On a cut, holding your ceiling IS the win — a small dip is the toll for getting lean, not a failure. We track pound-for-pound so relative power can still climb."
        case .bulking: "Fueled to grow — every session pushes for more. A flat set is a nudge to add a rep, not a loss."
        case .maintaining: "Holding at altitude — steady strength is the target, and the flat line is a win."
        }
    }

    private var inviteMessage: String {
        "Join me on sett — my invite code is CHAMBER-XXXXXX"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
