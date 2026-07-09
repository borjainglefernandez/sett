import SwiftUI
import SettCore

/// REST state (v3.1): after logging, the countdown takes the whole screen — giant
/// mono numerals (bone, no glow) inside a 2 pt iron progress ring on pure black.
/// Beneath: the NEXT preview (ash; tapping it jumps early) and the quiet
/// `−15 · skip · +15` row. The remaining time derives from `session.restEndsAt`
/// wall clock via TimelineView every second — never tick-accumulated — so
/// backgrounding never drifts it. At zero: exactly one success haptic (guarded by
/// @State), the rest clears, and the shell advances the cursor via `onAdvance`.
struct RestOverlayView: View {
    /// e.g. `NEXT · 157.5 lb × 12 · SET 3/4` or `NEXT · BENCH PRESS · SET 1/4`.
    let nextLabel: String
    /// Shell callback: advance the queue cursor to the next open slot.
    let onAdvance: () -> Void

    @Environment(WorkoutSessionStore.self) private var session
    @Environment(AppServices.self) private var services

    @State private var firedCompletion = false
    @State private var lastTickSecond = Int.max

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 72

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            content(remaining: remainingSeconds(at: context.date),
                    fraction: remainingFraction(at: context.date))
                .onChange(of: remainingSeconds(at: context.date)) { _, newValue in
                    handleTick(newValue)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Translucent scrim only — the shell's cosmic Time Chamber shows through so
        // rest still reads as "floating in the void," not a black cutaway.
        .background(TimeChamber.void.opacity(0.45).ignoresSafeArea())
        // onChange never fires when the overlay MOUNTS already at zero (e.g. the
        // hold-for-gold-flash delay outliving a very short rest) — sweep once.
        .onAppear { handleTick(remainingSeconds(at: .now)) }
    }

    // MARK: Wall-clock derivation (restEndsAt-based, never accumulated)

    private func remainingSeconds(at date: Date) -> Int {
        guard let ends = session.restEndsAt else { return 0 }
        return max(0, Int(ends.timeIntervalSince(date).rounded(.up)))
    }

    private func remainingFraction(at date: Date) -> Double {
        guard let ends = session.restEndsAt, session.restTotalSeconds > 0 else { return 0 }
        let remaining = max(0, ends.timeIntervalSince(date))
        return min(1, remaining / Double(session.restTotalSeconds))
    }

    private func handleTick(_ remaining: Int) {
        if remaining <= 0 {
            guard !firedCompletion else { return }
            firedCompletion = true
            Haptics.success()
            session.skipRest()
            onAdvance()
        } else if remaining <= 3 && remaining < lastTickSecond {
            lastTickSecond = remaining
            Haptics.light()
        }
    }

    // MARK: Content

    private func content(remaining: Int, fraction: Double) -> some View {
        VStack(spacing: 0) {
            if let readback = session.lastReadback {
                ReadbackBlock(payload: readback, unit: services.settings.unit)
                    .padding(.top, 16)
            }
            Spacer()
            VStack(spacing: 36) {
                VStack(spacing: 12) {
                    Text("RECALIBRATING")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(3)
                        .foregroundStyle(SettColor.iron)
                        .accessibilityHidden(true)
                    ring(remaining: remaining, fraction: fraction)
                }
                VStack(spacing: 24) {
                    nextPreview
                    quietRow
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func ring(remaining: Int, fraction: Double) -> some View {
        ZStack {
            Circle()
                .stroke(SettColor.iron.opacity(0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(SettColor.iron, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(timeText(remaining))
                .font(.system(size: numeralSize, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(28)
        }
        .frame(width: 264, height: 264)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest, \(timeText(remaining)) remaining")
    }

    /// Tapping the NEXT preview jumps early: skip the rest, advance the cursor.
    private var nextPreview: some View {
        Button {
            Haptics.light()
            session.skipRest()
            onAdvance()
        } label: {
            Text(nextLabel)
                .font(.system(.footnote, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Skips the rest and jumps to this set")
    }

    private var quietRow: some View {
        HStack(spacing: 8) {
            quietButton("−15") { session.adjustRest(by: -15) }
            quietButton("skip") {
                session.skipRest()
                onAdvance()
            }
            quietButton("+15") { session.adjustRest(by: 15) }
        }
    }

    private func quietButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SettColor.ash)
                .frame(minWidth: 64, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "skip" ? "Skip rest" : "\(label) seconds")
    }

    private func timeText(_ remaining: Int) -> String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
