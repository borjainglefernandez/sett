import ActivityKit
import Foundation

/// Shared between the app (which starts / updates / ends the Activity) and the
/// widget extension (which renders it). The rest countdown on the Dynamic Island +
/// lock screen — tenet 1 ("rest runs itself") taken past the app boundary, stage 2.
public struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// When rest ends — the widget renders a self-updating countdown to this.
        public var endsAt: Date
        /// The exercise the next set belongs to, shown as "Next: …".
        public var nextUp: String?

        public init(endsAt: Date, nextUp: String?) {
            self.endsAt = endsAt
            self.nextUp = nextUp
        }
    }

    public var workoutTitle: String

    public init(workoutTitle: String) {
        self.workoutTitle = workoutTitle
    }
}
