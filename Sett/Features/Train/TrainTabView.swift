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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    ForEach(Segment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch segment {
                case .routines:
                    RoutineListView()
                case .exercises:
                    ExerciseLibraryView()
                }
            }
            .dungeonBackground()
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: segment) {
                Haptics.selection()
            }
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

    static func isSet(_ mask: Int, day: Int) -> Bool {
        (mask >> day) & 1 == 1
    }
}
