import SwiftUI
import SwiftData
import Charts
import SettCore

/// Bodyweight card — last 90 days of standalone entries as a monotone cyan line,
/// latest value as the headline, min/max in the footnote. Tap to open the full
/// entry list (edit or delete individual weigh-ins).
struct BodyweightCard: View {
    let entries: [BodyweightEntry]
    let unit: WeightUnit

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One-time on-appear grow: the line plots at zero until this flips.
    @State private var revealed = false
    @State private var isShowingEntries = false

    /// Last 90 days, oldest first (chart order).
    private var recent: [BodyweightEntry] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) else { return [] }
        return entries
            .filter { $0.deletedAt == nil && $0.loggedAt >= cutoff }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    var body: some View {
        let recent = recent
        Button {
            isShowingEntries = true
        } label: {
            cardBody(recent)
        }
        .buttonStyle(PressableSlabStyle(haptic: .light))
        .accessibilityHint("Opens the bodyweight entry list")
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.snappy) { revealed = true }
            }
        }
        .sheet(isPresented: $isShowingEntries) {
            BodyweightEntriesSheet(unit: unit)
        }
    }

    private func cardBody(_ recent: [BodyweightEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle("Bodyweight")
                Eyebrow("LAST 90 DAYS")
            }
            if let latest = recent.last {
                Text(BodyweightFormat.valueWithUnit(grams: latest.weightGrams, unit: unit))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                Chart(recent) { entry in
                    LineMark(x: .value("Date", entry.loggedAt),
                             y: .value("Weight", displayValue(entry.weightGrams) * (revealed ? 1 : 0)))
                        .foregroundStyle(SettColor.heroCyan)
                        .interpolationMethod(.monotone)
                        .symbol(.circle)
                        .symbolSize(16)
                }
                .chartYScale(domain: yDomain(recent))
                .frame(height: 140)
                .scouterChart()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bodyweight, last 90 days")
                .accessibilityValue(accessibilitySummary(recent, latest: latest))
                if let footnote = minMaxFootnote(recent) {
                    Text(footnote)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(SettColor.ash)
                }
            } else {
                Text("Log your bodyweight from Home")
                    .font(.subheadline)
                    .foregroundStyle(SettColor.ash)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
        .contentShape(Rectangle())
    }

    /// Spoken chart summary — latest weight + net change over the window (Charts give
    /// VoiceOver nothing on their own).
    private func accessibilitySummary(_ entries: [BodyweightEntry], latest: BodyweightEntry) -> String {
        let now = BodyweightFormat.valueWithUnit(grams: latest.weightGrams, unit: unit)
        guard let first = entries.first, first.id != latest.id else { return "\(now), one entry" }
        let deltaGrams = latest.weightGrams - first.weightGrams
        let dir = deltaGrams > 0 ? "up" : (deltaGrams < 0 ? "down" : "no change")
        let deltaText = BodyweightFormat.value(grams: abs(deltaGrams), unit: unit)
        return deltaGrams == 0 ? "\(now), \(dir) over 90 days"
            : "\(now), \(dir) \(deltaText) \(unit.symbol) over 90 days"
    }

    private func displayValue(_ grams: Int) -> Double {
        Double(grams) / unit.gramsPerUnit
    }

    private func yDomain(_ entries: [BodyweightEntry]) -> ClosedRange<Double> {
        let values = entries.map { displayValue($0.weightGrams) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(0.5, (high - low) * 0.15)
        return (low - pad)...(high + pad)
    }

    private func minMaxFootnote(_ entries: [BodyweightEntry]) -> String? {
        let values = entries.map(\.weightGrams)
        guard let low = values.min(), let high = values.max() else { return nil }
        let lowText = BodyweightFormat.value(grams: low, unit: unit)
        let highText = BodyweightFormat.value(grams: high, unit: unit)
        return "min \(lowText) · max \(highText) \(unit.symbol)"
    }
}

// MARK: - Entries sheet (every weigh-in, editable)

/// The full bodyweight ledger: newest-first rows ("182.4 lb · Jul 12"),
/// swipe-left soft-deletes, tap re-opens the quick logger prefilled for editing.
/// Queries its own entries so deletes and edits refresh the list live.
private struct BodyweightEntriesSheet: View {
    let unit: WeightUnit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var entries: [BodyweightEntry]
    @State private var editingEntry: BodyweightEntry?

    init(unit: WeightUnit) {
        self.unit = unit
        let filter = #Predicate<BodyweightEntry> { $0.deletedAt == nil }
        _entries = Query(filter: filter,
                         sort: [SortDescriptor(\BodyweightEntry.loggedAt, order: .reverse)])
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    row(entry)
                        .listRowBackground(SettColor.card)
                }
                .onDelete(perform: delete)
            }
            .scrollContentBackground(.hidden)
            .dungeonBackground()
            .navigationTitle("Bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingEntry) { entry in
                BodyweightLogSheet(latest: nil, editing: entry)
            }
        }
    }

    private func row(_ entry: BodyweightEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            HStack {
                Text(BodyweightFormat.valueWithUnit(grams: entry.weightGrams, unit: unit))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
                Text("· \(entry.loggedAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .foregroundStyle(SettColor.ash)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.iron)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits this entry")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let entry = entries[index]
            entry.deletedAt = .now
            entry.updatedAt = .now
            entry.needsPush = true
        }
        try? modelContext.save()
        Haptics.light()
    }
}
