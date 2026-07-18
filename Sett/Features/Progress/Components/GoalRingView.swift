import SwiftUI
import SettCore

/// Activity-style goal ring (Flow 4): 12 pt round-cap trim stroke in the
/// `Aura.cyan` gradient (gold once complete, with a checkmark), current/target
/// centered inside, caption title below.
struct GoalRingView: View {
    let progress: GoalProgress
    let title: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the on-appear sweep from zero to the real fraction.
    @State private var sweep = false
    /// Near-complete only: a slow cyan halo breathe that starts once the sweep lands.
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(SettColor.cardNested, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: sweep ? progress.fraction : 0)
                    .stroke(ringStyle, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: progress.fraction)
                // Within striking distance: a soft cyan halo breathes on the ring to
                // pull the eye. Cyan = action, not the gold reserved for the finish.
                if isAlmostThere && !reduceMotion {
                    Circle()
                        .stroke(SettColor.heroCyan, lineWidth: 12)
                        .opacity(pulse ? 0 : 0.4)
                        .scaleEffect(pulse ? 1.1 : 1)
                }
                VStack(spacing: 2) {
                    if progress.isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(SettColor.saiyanGold)
                    }
                    Text("\(compact(progress.currentValue))/\(compact(progress.targetValue))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SettColor.bone)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 16)
            }
            .frame(width: 88, height: 88)
            Text(title)
                .font(.caption)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 100)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            if reduceMotion {
                sweep = true
            } else {
                withAnimation(.snappy(duration: 0.5)) { sweep = true }
                // Almost done? Breathe the halo forever, delayed until the sweep settles.
                if isAlmostThere {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(0.5)) {
                        pulse = true
                    }
                }
            }
        }
    }

    private var ringStyle: AnyShapeStyle {
        progress.isComplete ? AnyShapeStyle(Aura.gold) : AnyShapeStyle(Aura.cyan)
    }

    /// Within striking distance but not done — earns the attention pulse.
    private var isAlmostThere: Bool {
        progress.fraction >= 0.85 && !progress.isComplete
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
