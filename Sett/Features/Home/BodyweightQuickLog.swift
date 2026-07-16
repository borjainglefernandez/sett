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

// MARK: - Log sheet

/// One-thumb quick logger: big numeral, − / + steppers, save. No typing, no
/// dragging. With `editing` set it rewrites that entry's weight in place
/// (loggedAt untouched) instead of inserting a new one.
struct BodyweightLogSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let latest: BodyweightEntry?
    /// Non-nil = edit mode: prefill from this entry and mutate it on save.
    var editing: BodyweightEntry? = nil

    @State private var grams = 79_000

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 56

    private var unit: WeightUnit { services.settings.unit }

    /// 0.1 kg or 0.1 lb per tap, expressed in grams.
    private var stepGrams: Int { unit == .kg ? 100 : 45 }

    var body: some View {
        ChamberSheet(title: "Bodyweight", commitLabel: editing == nil ? "LOG" : "SAVE", onCommit: save) {
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
                            .foregroundStyle(SettColor.ash)
                    }
                    if let deltaText {
                        // Neutral on purpose — bodyweight direction isn't good or bad.
                        Text(deltaText)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.ash)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(SettColor.cardNested, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                stepperButton(systemName: "plus", delta: stepGrams)
            }
            .padding(.top, 10)
        }
        .presentationDetents([.height(280)])
        .onAppear {
            grams = editing?.weightGrams ?? latest?.weightGrams ?? 79_000
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
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 56, height: 56)
                .background {
                    Circle().fill(SettColor.cardNested)
                    Circle().strokeBorder(SettColor.heroCyan.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Decrease weight" : "Increase weight")
    }

    private func save() {
        if let editing {
            // Correcting a past weigh-in — the entry keeps its original loggedAt.
            editing.weightGrams = grams
            editing.updatedAt = .now
            editing.needsPush = true
        } else {
            modelContext.insert(BodyweightEntry(weightGrams: grams))
        }
        try? modelContext.save()
        Haptics.success()
    }
}
