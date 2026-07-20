import SwiftUI
import SwiftData
import SettCore

/// Manual lab reading: last night's sleep, logged by hand — the no-ring path.
/// Writes the same SleepDay rows the Oura sync will own later, so the engine,
/// the Sleep × Lifts chart, and Luma's recovery badges make no distinction
/// between a synced night and an honest hand-logged one.
struct SleepLogSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    /// Which night is being logged: 0 = the night that ended this morning,
    /// 1 = the night before, … capped so backfill stays a correction tool,
    /// not a badge-farming lever.
    @State private var nightOffset = 0
    /// Slept time in seconds — 15-minute steps, defaults to 7 h 30 m.
    @State private var sleepSeconds = 27_000
    /// Self-scored rest quality 0–100 (Oura's scale, so synced and manual
    /// nights share one axis on the Sleep × Lifts chart).
    @State private var restedScore = 75

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 52

    private let calendar = Calendar.current
    private static let maxBackfillNights = 13

    var body: some View {
        ChamberSheet(title: "Sleep reading", commitLabel: "LOG", onCommit: save) {
            VStack(spacing: 18) {
                // Night picker — chevrons walk mornings, newest on the right.
                HStack {
                    Eyebrow("NIGHT")
                    Spacer()
                    ChamberStepControl(
                        text: nightLabel,
                        onDecrement: { bumpNight(+1) },   // older
                        onIncrement: { bumpNight(-1) })   // newer
                }
                HStack(spacing: 16) {
                    stepperButton(systemName: "minus", delta: -900)
                    VStack(spacing: 4) {
                        Text(durationText)
                            .font(PowerFont.xl(numeralSize))
                            .monospacedDigit()
                            .foregroundStyle(SettColor.heroCyan)
                            .contentTransition(.numericText(value: Double(sleepSeconds)))
                        Text("slept")
                            .font(.caption)
                            .foregroundStyle(SettColor.ash)
                    }
                    .frame(maxWidth: .infinity)
                    stepperButton(systemName: "plus", delta: 900)
                }
                HStack {
                    Eyebrow("RESTED SCORE")
                    Spacer()
                    ChamberStepControl(
                        text: "\(restedScore)",
                        onDecrement: { bumpScore(-5) },
                        onIncrement: { bumpScore(+5) })
                }
            }
            .padding(.top, 6)
        }
        .presentationDetents([.height(340)])
        .onAppear { prefill() }
        .onChange(of: nightOffset) { prefill() }
    }

    // MARK: Night selection

    private var nightMorning: Date {
        calendar.date(byAdding: .day, value: -nightOffset, to: .now) ?? .now
    }

    /// The engine pairs a night with the day it ENDED (the workout morning),
    /// so the row's dateKey is the morning's day.
    private var nightDateKey: Int {
        calendar.dateKey(for: nightMorning)
    }

    private var nightLabel: String {
        nightOffset == 0
            ? "Last night"
            : nightMorning.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func bumpNight(_ delta: Int) {
        nightOffset = min(Self.maxBackfillNights, max(0, nightOffset + delta))
    }

    // MARK: Duration + score

    private var durationText: String {
        let hours = sleepSeconds / 3600
        let minutes = (sleepSeconds % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private func bumpScore(_ delta: Int) {
        restedScore = min(100, max(0, restedScore + delta))
    }

    private func stepperButton(systemName: String, delta: Int) -> some View {
        Button {
            withAnimation(.snappy) {
                sleepSeconds = min(14 * 3600, max(0, sleepSeconds + delta))
            }
            Haptics.light()
        } label: {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 52, height: 52)
                .background {
                    Circle().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Fifteen minutes less" : "Fifteen minutes more")
    }

    // MARK: Prefill + save

    /// Editing an already-logged night starts from what it says now.
    private func prefill() {
        guard let existing = existingRow() else { return }
        if let seconds = existing.totalSleepSeconds { sleepSeconds = seconds }
        if let score = existing.sleepScore { restedScore = score }
    }

    private func existingRow() -> SleepDay? {
        let key = nightDateKey
        let descriptor = FetchDescriptor<SleepDay>(predicate: #Predicate { $0.dateKey == key })
        return try? modelContext.fetch(descriptor).first
    }

    /// Upsert by dateKey (unique) — a later Oura sync simply overwrites the
    /// hand reading with the measured one.
    private func save() {
        if let existing = existingRow() {
            existing.totalSleepSeconds = sleepSeconds
            existing.sleepScore = restedScore
            existing.fetchedAt = .now
        } else {
            modelContext.insert(SleepDay(dateKey: nightDateKey,
                                         sleepScore: restedScore,
                                         totalSleepSeconds: sleepSeconds))
        }
        try? modelContext.save()
        // Sleep feeds recovery badges — recompute now so a night that completes
        // Recovery Protocol wakes Luma without waiting for the next scan.
        services.progression.recompute(context: modelContext)
    }
}
