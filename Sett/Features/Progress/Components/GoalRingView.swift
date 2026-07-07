import SwiftUI
import SettCore

/// Activity-style goal ring (Flow 4): 12 pt round-cap trim stroke in the
/// `Aura.cyan` gradient (gold once complete, with a checkmark), current/target
/// centered inside, caption title below.
struct GoalRingView: View {
    let progress: GoalProgress
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(SettColor.cardNested, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(ringStyle, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: progress.fraction)
                VStack(spacing: 2) {
                    if progress.isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(SettColor.saiyanGold)
                    }
                    Text("\(compact(progress.currentValue))/\(compact(progress.targetValue))")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 16)
            }
            .frame(width: 88, height: 88)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 100)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var ringStyle: AnyShapeStyle {
        progress.isComplete ? AnyShapeStyle(Aura.gold) : AnyShapeStyle(Aura.cyan)
    }

    private var accessibilityText: String {
        let status = progress.isComplete ? ", complete" : ""
        return "\(title): \(progress.currentValue) of \(progress.targetValue)\(status)"
    }

    /// 12,400 → "12.4k" so PR/volume targets fit inside the ring.
    private func compact(_ value: Int) -> String {
        guard abs(value) >= 10_000 else { return "\(value)" }
        let thousands = Double(value) / 1000.0
        return thousands >= 100
            ? String(format: "%.0fk", thousands)
            : String(format: "%.1fk", thousands)
    }
}
