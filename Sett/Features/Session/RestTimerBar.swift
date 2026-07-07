import SwiftUI
import SettCore

/// Rest countdown capsule pinned above the bottom edge (tenet 1: rest runs itself).
/// The remaining time derives from `session.restEndsAt` wall clock via `TimelineView`,
/// so backgrounding never drifts it. Ticks light haptics on the last 3 seconds and
/// fires exactly one success haptic at zero (guarded by @State), then clears the rest.
struct RestTimerBar: View {
    @Environment(WorkoutSessionStore.self) private var session

    @State private var firedCompletion = false
    @State private var lastTickSecond = Int.max

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = remainingSeconds(at: context.date)
            content(remaining: remaining)
                .onChange(of: remaining) { _, newValue in
                    handleTick(newValue)
                }
        }
    }

    private func remainingSeconds(at date: Date) -> Int {
        guard let ends = session.restEndsAt else { return 0 }
        return max(0, Int(ends.timeIntervalSince(date).rounded(.up)))
    }

    private func handleTick(_ remaining: Int) {
        if remaining <= 0 {
            guard !firedCompletion else { return }
            firedCompletion = true
            Haptics.success()
            session.skipRest()
        } else if remaining <= 3 && remaining < lastTickSecond {
            lastTickSecond = remaining
            Haptics.light()
        }
    }

    // MARK: Capsule content

    private func content(remaining: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(SettColor.heroCyan)
            Text(timeText(remaining))
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .leading)
            Spacer(minLength: 0)
            adjustButton("−15s") { session.adjustRest(by: -15) }
            adjustButton("+15s") { session.adjustRest(by: 15) }
            Button {
                session.skipRest()
            } label: {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip rest")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(SettColor.card, in: Capsule())
        .shadow(color: SettColor.heroCyan.opacity(0.25), radius: 8)
    }

    private func adjustButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SettColor.heroCyan)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeText(_ remaining: Int) -> String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
