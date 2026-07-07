import SwiftUI
import SwiftData
import SettCore

// MARK: - Formatting (bodyweight always shows one decimal in the display unit)

enum BodyweightFormat {
    static func value(grams: Int, unit: WeightUnit) -> String {
        String(format: "%.1f", Double(grams) / unit.gramsPerUnit)
    }

    static func valueWithUnit(grams: Int, unit: WeightUnit) -> String {
        "\(value(grams: grams, unit: unit)) \(unit.symbol)"
    }

    static func relativeDay(_ date: Date, asOf now: Date = .now) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "1d ago"
        default: return "\(days)d ago"
        }
    }
}

// MARK: - Chip card (Home)

/// Compact Home card: latest bodyweight at a glance, one tap anywhere to log a new entry.
struct BodyweightChipCard: View {
    @Environment(AppServices.self) private var services

    let latest: BodyweightEntry?

    @State private var isLogging = false

    var body: some View {
        Button {
            isLogging = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "scalemass.fill")
                    .font(.title3)
                    .foregroundStyle(SettColor.heroCyan)
                if let latest {
                    Text("\(BodyweightFormat.valueWithUnit(grams: latest.weightGrams, unit: services.settings.unit)) · \(BodyweightFormat.relativeDay(latest.loggedAt))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("Log bodyweight")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(SettColor.heroCyan)
            }
            .settCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the bodyweight logger")
        .sheet(isPresented: $isLogging) {
            BodyweightLogSheet(latest: latest)
        }
    }

    private var accessibilityText: String {
        guard let latest else { return "Log bodyweight" }
        let value = BodyweightFormat.valueWithUnit(grams: latest.weightGrams, unit: services.settings.unit)
        return "Bodyweight \(value), logged \(BodyweightFormat.relativeDay(latest.loggedAt))"
    }
}

// MARK: - Log sheet

/// One-thumb quick logger: big numeral, − / + steppers, save. No typing, no dragging.
struct BodyweightLogSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let latest: BodyweightEntry?

    @State private var grams = 79_000

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 56

    private var unit: WeightUnit { services.settings.unit }

    /// 0.1 kg or 0.2 lb per tap, expressed in grams.
    private var stepGrams: Int { unit == .kg ? 100 : 91 }

    var body: some View {
        VStack(spacing: 20) {
            Text("Bodyweight")
                .font(.headline)
            HStack(spacing: 16) {
                stepperButton(systemName: "minus", delta: -stepGrams)
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(BodyweightFormat.value(grams: grams, unit: unit))
                            .font(PowerFont.xl(numeralSize))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.heroCyan)
                            .contentTransition(.numericText(value: Double(grams)))
                        Text(unit.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let deltaText {
                        // Neutral on purpose — bodyweight direction isn't good or bad.
                        Text(deltaText)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(SettColor.cardNested, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                stepperButton(systemName: "plus", delta: stepGrams)
            }
            Button {
                save()
            } label: {
                Text("Save")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Aura.cyan, in: Capsule())
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .presentationDetents([.height(280)])
        .onAppear {
            grams = latest?.weightGrams ?? 79_000
        }
    }

    private var deltaText: String? {
        guard let latest else { return nil }
        let delta = Double(grams - latest.weightGrams) / unit.gramsPerUnit
        return String(format: "%+.1f %@ vs last", delta, unit.symbol)
    }

    private func stepperButton(systemName: String, delta: Int) -> some View {
        Button {
            withAnimation(.snappy) {
                grams = min(300_000, max(20_000, grams + delta))
            }
            Haptics.light()
        } label: {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .background(SettColor.cardNested, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Decrease weight" : "Increase weight")
    }

    private func save() {
        let entry = BodyweightEntry(weightGrams: grams)
        modelContext.insert(entry)
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }
}
