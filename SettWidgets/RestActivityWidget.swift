import ActivityKit
import WidgetKit
import SwiftUI

/// The widget-extension entry point. Only the rest-timer Live Activity for now.
@main
struct SettWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestActivityWidget()
    }
}

/// The rest countdown as a Live Activity: a running timer on the lock screen and in
/// the Dynamic Island. `Text(timerInterval:)` self-updates, so the app never has to
/// push per-second updates — it only starts/adjusts/ends the Activity.
struct RestActivityWidget: Widget {
    // The session accent lives in the app; the widget is its own bundle, so a local
    // cyan keeps it on-brand without cross-target colour imports.
    private static let accent = Color(red: 0.39, green: 0.82, blue: 0.90)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("REST", systemImage: "timer")
                        .font(.caption.bold())
                        .foregroundStyle(Self.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.state.endsAt, countsDown: true)
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .frame(width: 74)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let next = context.state.nextUp {
                        Text("Next: \(next)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(Self.accent)
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.endsAt, countsDown: true)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(Self.accent)
            }
        }
    }
}

struct RestLockScreenView: View {
    let context: ActivityViewContext<RestActivityAttributes>
    private static let accent = Color(red: 0.39, green: 0.82, blue: 0.90)

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("REST")
                    .font(.caption.weight(.bold))
                    .kerning(2)
                    .foregroundStyle(Self.accent)
                if let next = context.state.nextUp {
                    Text("Next: \(next)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(context.attributes.workoutTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(timerInterval: Date.now...context.state.endsAt, countsDown: true)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}
