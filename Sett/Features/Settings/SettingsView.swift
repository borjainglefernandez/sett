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

    /// DEBUG ceremony preview — presents a WorkoutSummaryView with a tailored mock.
    @State private var demoCeremony: WorkoutSummaryData?

    /// 1.25 lb / 2.5 lb / 5 lb expressed in canonical grams.
    private static let standardIncrementsGrams = [567, 1134, 2268]

    var body: some View {
        @Bindable var settings = services.settings
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("WEIGHT UNIT")
                        ChamberSegments(selection: $settings.unit,
                                        options: [(WeightUnit.lb, "lb"), (WeightUnit.kg, "kg")],
                                        compact: true)
                    }
                    .padding(.vertical, 4)
                    Picker("Weight increment", selection: $settings.incrementGrams) {
                        ForEach(incrementOptions, id: \.self) { grams in
                            Text(settings.displayWeight(grams)).tag(grams)
                        }
                    }
                    .foregroundStyle(SettColor.bone)
                    HStack {
                        Text("Default rest")
                            .foregroundStyle(SettColor.bone)
                        Spacer()
                        ChamberStepControl(
                            text: restText,
                            onDecrement: {
                                settings.defaultRestSeconds = max(RestTuning.range.lowerBound,
                                                                  settings.defaultRestSeconds - RestTuning.step)
                            },
                            onIncrement: {
                                settings.defaultRestSeconds = min(RestTuning.range.upperBound,
                                                                  settings.defaultRestSeconds + RestTuning.step)
                            })
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("WORKOUT VIEW")
                        ChamberSegments(selection: $settings.startsInList,
                                        options: [(false, "Scanner"), (true, "List")],
                                        compact: true)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Eyebrow("UNITS")
                } footer: {
                    Text("Scanner is the full-screen scouter; List is the overview of every set.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("PHASE")
                        ChamberSegments(selection: phaseBinding,
                                        options: TrainingPhase.allCases.map { ($0, $0.title) },
                                        compact: true)
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 8) {
                        Image(systemName: settings.phase.symbolName)
                            .foregroundStyle(SettColor.heroCyan)
                        Text(settings.phase.creed)
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .foregroundStyle(SettColor.bone)
                    }
                } header: {
                    Eyebrow("TRAINING PHASE")
                } footer: {
                    Text(phaseFooter)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
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
                    Eyebrow("DEFAULT REALM")
                } footer: {
                    Text("Your default training realm. Routines can override it.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
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
                    Eyebrow("INTEGRATIONS")
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
                    Eyebrow("FRIENDS")
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
                    Eyebrow("DEBUG")
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)

                // Fire the ceremonies that only happen at rare moments (form ascension,
                // big-reward finishes) or on a fixed day (the weekly reading), so they
                // can be seen on demand without waiting for the real trigger.
                Section {
                    Button("Power gain") { demoCeremony = .debugMock }
                    Button("Form ascension (ceiling break)") { demoCeremony = .debugMockAscension }
                    Button("Badges + goal complete") { demoCeremony = .debugMockRewards }
                    Toggle("Force weekly reading on Home", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "sett.debug.forceReading") },
                        set: { UserDefaults.standard.set($0, forKey: "sett.debug.forceReading") }))
                } header: {
                    Eyebrow("DEBUG — CEREMONIES")
                } footer: {
                    Text("Weekly reading shows on Home once toggled on. Tap a ceremony to preview it; Done returns here.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                }
                .listRowBackground(SettColor.card)
                .listRowSeparatorTint(SettColor.cardBorder)
                #endif

                Section {
                    LabeledContent("Version", value: versionText)
                        .foregroundStyle(SettColor.bone)
                } header: {
                    Eyebrow("ABOUT")
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
                // ChamberSegments already fires the selection haptic on tap.
                settings.incrementGrams = newUnit.defaultIncrementGrams
            }
            .sheet(item: $demoCeremony) { WorkoutSummaryView(summary: $0) }
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

    private var phaseBinding: Binding<TrainingPhase> {
        Binding(
            get: { services.settings.phase },
            set: {
                // ChamberSegments already fires the selection haptic on tap.
                services.settings.trainingPhase = $0.rawValue
                services.settings.hasChosenPhase = true
                services.session.syncActiveWorkoutPhase()
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

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
