import SwiftUI
import SettCore

/// Tab 2 — the launch pad (design-ux §2, Train root): a segmented header
/// switching between the routine list and the exercise library.
struct TrainTabView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case routines = "Routines"
        case exercises = "Exercises"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .routines
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChamberSegments(selection: $segment,
                                options: Segment.allCases.map { ($0, $0.rawValue) })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                // The two panes cross-dissolve instead of hard-cutting — the segmented
                // pill already glides, so the content it drives shouldn't snap.
                ZStack {
                    switch segment {
                    case .routines:
                        RoutineListView().transition(.opacity)
                    case .exercises:
                        ExerciseLibraryView().transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: segment)
            }
            .dungeonBackground()
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Day-of-week labels shared by the Train feature.
/// `Routine.daysOfWeekMask` is a bitmask with bit 0 = Monday … bit 6 = Sunday.
enum TrainDays {
    static let letters = ["M", "T", "W", "T", "F", "S", "S"]
    static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday",
                        "Friday", "Saturday", "Sunday"]

    /// Weekday indices (0 = Mon … 6 = Sun) in Sunday-first DISPLAY order.
    /// Bit semantics of `daysOfWeekMask` are unchanged — only rendering order is.
    static let sundayFirstOrder = [6, 0, 1, 2, 3, 4, 5]

    static func isSet(_ mask: Int, day: Int) -> Bool {
        (mask >> day) & 1 == 1
    }
}
