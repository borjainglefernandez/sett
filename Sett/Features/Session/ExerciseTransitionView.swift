import SwiftUI
import SettCore

// MARK: - Between-exercise transition (no rest — recap + insight + motivation)

/// Everything the transition needs: the exercise just finished, a per-working-set
/// breakdown with the power reading and how it compares to last week, the headline
/// numbers, a context-aware motivational line, and where you're headed next.
struct ExerciseSummaryData: Identifiable, Equatable {
    let id = UUID()
    let exerciseName: String
    let equipmentSymbol: String
    let rows: [SetRow]          // working sets only (warmups counted separately)
    let warmupCount: Int
    let topPower: Int           // best working-set e1RM, lb (unit-consistent)
    let bestDelta: Int?         // best set's Δ PWR vs last week (nil = no reference)
    let hasReference: Bool
    let phase: TrainingPhase
    let retentionPct: Int?      // top set as % of last week's (for the cut header)
    let quote: String
    let nextLabel: String       // next exercise name, or "" when this was the last
    let isFinal: Bool

    struct SetRow: Identifiable, Equatable {
        let id = UUID()
        let number: Int
        let weightGrams: Int
        let reps: Int
        let power: Int          // this set's e1RM, lb
        let delta: Int?         // vs last week's set at the same slot (lb)
        /// This set held or beat the phase's success band (so a dip inside the cut
        /// band is NOT drawn as a red loss).
        let inBand: Bool
    }
}

/// Shown INSTEAD of a rest countdown when you finish an exercise and the next set
/// belongs to a different one: a per-set recap with the power reading and last-week
/// comparison, a headline, and a motivational line — then a tap moves you on.
struct ExerciseTransitionView: View {
    let data: ExerciseSummaryData
    let unit: WeightUnit
    let tier: AuraTier
    let onContinue: () -> Void

    @State private var materialized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            card
            Spacer(minLength: 8)
            PlayerSlab(title: data.isFinal ? "END READING" : "NEXT · \(data.nextLabel.uppercased())",
                       accent: tier.color) {
                onContinue()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TimeChamber.void.opacity(0.6).ignoresSafeArea())
        .opacity(materialized ? 1 : 0)
        .blur(radius: materialized || reduceMotion ? 0 : 6)
        .onAppear {
            if reduceMotion { materialized = true }
            else { withAnimation(.easeOut(duration: 0.3)) { materialized = true } }
            Haptics.medium()
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            header
            headline
            setTable
            if data.warmupCount > 0 {
                Text("+ \(data.warmupCount) WARM-UP")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.iron)
            }
            Rectangle().fill(tier.color.opacity(0.25)).frame(height: 1).padding(.horizontal, 4)
            Text(data.quote)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.6), radius: 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape.fill(TimeChamber.void.opacity(0.85))
            shape.strokeBorder(tier.color.opacity(0.5), lineWidth: 1.5)
                .shadow(color: tier.color.opacity(0.4), radius: 9)
            CornerTicksShape(length: 7, inset: 7)
                .stroke(tier.color.opacity(0.55), lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("EXERCISE COMPLETE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(tier.color)
            HStack(spacing: 9) {
                Image(systemName: data.equipmentSymbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tier.color)
                Text(data.exerciseName.uppercased())
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .kerning(1)
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    /// Top power reading + a phase-appropriate comparison to last week (retention
    /// on a cut; best-set improvement otherwise).
    private var headline: some View {
        HStack(spacing: 8) {
            SettSigil(size: 13, color: tier.color)
            Text("TOP PWR \(data.topPower)")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tier.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if data.phase == .cutting, let pct = data.retentionPct {
                Text("· \(pct)% CEILING DEFENDED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(pct >= 94 ? SettColor.positive : tier.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if let best = data.bestDelta {
                Text("· \(deltaLabel(best, inBand: false)) VS LAST WEEK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(deltaColor(best, inBand: false))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 3)
    }

    /// Per-set table: number, the lift, its power, and how it moved vs last week.
    private var setTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 7) {
            GridRow {
                cell("SET", .iron, leading: true)
                cell("LIFT", .iron, leading: true)
                cell("PWR", .iron)
                cell("VS LAST", .iron)
            }
            ForEach(data.rows) { row in
                GridRow {
                    cell("\(row.number)", .ash, leading: true)
                    cell(liftText(row), .bone, leading: true)
                    cell("\(row.power)", .bone)
                    if let delta = row.delta {
                        cell(deltaLabel(delta, inBand: row.inBand), nil,
                             color: deltaColor(delta, inBand: row.inBand))
                    } else {
                        cell("—", .iron)
                    }
                }
            }
        }
    }

    private enum Ink { case iron, ash, bone }

    private func cell(_ text: String, _ ink: Ink?, leading: Bool = false, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 12, weight: leading ? .semibold : .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color ?? inkColor(ink ?? .bone))
            .gridColumnAlignment(leading ? .leading : .trailing)
    }

    private func inkColor(_ ink: Ink) -> Color {
        switch ink {
        case .iron: SettColor.iron
        case .ash: SettColor.ash
        case .bone: SettColor.bone
        }
    }

    private func liftText(_ row: ExerciseSummaryData.SetRow) -> String {
        "\(WeightFormat.compactWithUnit(grams: row.weightGrams, unit: unit)) × \(row.reps)"
    }

    private func deltaLabel(_ delta: Int, inBand: Bool) -> String {
        if delta > 0 { return "▲ +\(delta)" }
        if delta == 0 { return "= 0" }
        // A dip that stayed inside the phase's success band is "held", not a loss.
        return inBand ? "◇ held" : "▼ \(delta)"
    }

    private func deltaColor(_ delta: Int, inBand: Bool) -> Color {
        if delta > 0 { return SettColor.positive }
        if delta == 0 { return SettColor.ash }
        return inBand ? TimeChamber.teal : SettColor.negative
    }
}
