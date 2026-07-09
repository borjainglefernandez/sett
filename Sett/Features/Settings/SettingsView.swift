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
                    Stepper(value: $settings.defaultRestSeconds, in: 30...300, step: 15) {
                        LabeledContent("Default rest", value: restText)
                    }
                } header: {
                    sectionHeader("UNITS")
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ChamberBackground.allCases) { bg in
                                backgroundThumb(bg, selected: settings.chamberBackground == bg.rawValue)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                } header: {
                    sectionHeader("TIME CHAMBER")
                } footer: {
                    Text("Your training realm for the logging scanner.")
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

                Section {
                    ShareLink(item: inviteMessage) {
                        Label("Invite a Friend", systemImage: "person.badge.plus")
                    }
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

    /// One selectable Time Chamber backdrop thumbnail.
    private func backgroundThumb(_ bg: ChamberBackground, selected: Bool) -> some View {
        Button {
            services.settings.chamberBackground = bg.rawValue
            Haptics.selection()
        } label: {
            VStack(spacing: 6) {
                Image(bg.assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 76, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? SettColor.heroCyan : SettColor.cardBorder,
                                          lineWidth: selected ? 2.5 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(SettColor.heroCyan)
                                .padding(5)
                                .background(Circle().fill(Color.black.opacity(0.4)).padding(3))
                        }
                    }
                Text(bg.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? SettColor.bone : SettColor.ash)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bg.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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

    private var inviteMessage: String {
        "Join me on sett — my invite code is SAIYAN-XXXXXX"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
