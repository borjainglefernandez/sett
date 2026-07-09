import SwiftUI
import SettCore

// MARK: - Between-exercise transition (no rest — recap + motivation)

/// Everything the transition needs: the exercise just finished, its sets, the top
/// power reading, the context-aware motivational line, and where you're headed.
struct ExerciseSummaryData: Identifiable, Equatable {
    let id = UUID()
    let exerciseName: String
    let sets: [SetLine]
    let topPower: Int      // best working-set e1RM, in lb (unit-consistent)
    let quote: String
    let nextLabel: String  // next exercise name, or "" when this was the last
    let isFinal: Bool

    struct SetLine: Identifiable, Equatable {
        let id = UUID()
        let weightGrams: Int
        let reps: Int
        let isWarmup: Bool
    }
}

/// Shown INSTEAD of a rest countdown when you finish an exercise and the next set
/// belongs to a different one: a quick recap of the sets you just did, the top
/// power reading, and a motivational line tuned to how the session is going —
/// then a tap moves you straight on. No rest between exercises.
struct ExerciseTransitionView: View {
    let data: ExerciseSummaryData
    let unit: WeightUnit
    let tier: AuraTier
    let onContinue: () -> Void

    @State private var materialized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            card
            Spacer(minLength: 12)
            PlayerSlab(title: data.isFinal ? "END READING" : "NEXT · \(data.nextLabel)",
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
            VStack(spacing: 6) {
                Text("EXERCISE COMPLETE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(tier.color)
                Text(data.exerciseName.uppercased())
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .kerning(1)
                    .foregroundStyle(SettColor.bone)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            setChips

            HStack(spacing: 6) {
                SettSigil(size: 13, color: tier.color)
                Text("\(workingCount) \(workingCount == 1 ? "SET" : "SETS") · TOP PWR \(data.topPower)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(tier.color)
            }

            Rectangle().fill(tier.color.opacity(0.25)).frame(height: 1).padding(.horizontal, 8)

            Text(data.quote)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .shadow(color: .black.opacity(0.6), radius: 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            shape.fill(TimeChamber.void.opacity(0.82))
            shape.strokeBorder(tier.color.opacity(0.5), lineWidth: 1.5)
                .shadow(color: tier.color.opacity(0.4), radius: 9)
            CornerTicksShape(length: 7, inset: 7)
                .stroke(tier.color.opacity(0.55), lineWidth: 1)
        }
    }

    private var workingCount: Int { data.sets.filter { !$0.isWarmup }.count }

    private var setChips: some View {
        FlowRow(spacing: 8) {
            ForEach(data.sets) { set in
                Text(chipText(set))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(set.isWarmup ? SettColor.iron : SettColor.bone)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule().strokeBorder(
                            set.isWarmup ? SettColor.cardBorder : tier.color.opacity(0.4),
                            lineWidth: 1
                        )
                    }
            }
        }
    }

    private func chipText(_ set: ExerciseSummaryData.SetLine) -> String {
        let weight = WeightFormat.compactWithUnit(grams: set.weightGrams, unit: unit)
        let base = "\(weight) × \(set.reps)"
        return set.isWarmup ? "\(base) · W" : base
    }
}

// MARK: - Simple wrapping row (chips flow onto multiple lines)

/// Minimal flow layout so set chips wrap instead of clipping — no external deps.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0, maxRowWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth)
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
