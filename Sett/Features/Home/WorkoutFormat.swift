import SwiftUI
import SettCore

// MARK: - Shared display formatting for workout rows and headers

enum WorkoutFormat {
    /// "45 min" under an hour, "1 h 12 min" above.
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        guard minutes >= 60 else { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

extension Workout {
    /// Elapsed wall-clock time minus pauses; live while the workout is ongoing.
    var durationSeconds: Int {
        let end = endedAt ?? .now
        return max(0, Int(end.timeIntervalSince(startedAt)) - pausedSeconds)
    }
}

// MARK: - Compact gold half-star display (0…10 half stars over 5 stars)

struct StarRatingRow: View {
    let halfStars: Int
    var starSize: CGFloat = 9

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(star))
            }
        }
        .font(.system(size: starSize))
        .foregroundStyle(SettColor.saiyanGold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(String(format: "%.1f", Double(halfStars) / 2)) stars")
    }

    private func symbol(_ star: Int) -> String {
        if halfStars >= star * 2 {
            "star.fill"
        } else if halfStars == star * 2 - 1 {
            "star.leadinghalf.filled"
        } else {
            "star"
        }
    }
}
