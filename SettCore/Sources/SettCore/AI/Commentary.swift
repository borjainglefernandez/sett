import Foundation

/// Structured facts only — never raw user text (no prompt injection, no embarrassing echo).
public struct CommentaryFacts: Sendable {
    public let title: String
    public let netReps: Int
    public let netVolumeGrams: Int
    public let netIsNew: Bool
    public let newBadgeCount: Int
    public let powerLevelDelta: Int

    public init(title: String, netReps: Int, netVolumeGrams: Int, netIsNew: Bool,
                newBadgeCount: Int, powerLevelDelta: Int) {
        self.title = title
        self.netReps = netReps
        self.netVolumeGrams = netVolumeGrams
        self.netIsNew = netIsNew
        self.newBadgeCount = newBadgeCount
        self.powerLevelDelta = powerLevelDelta
    }
}

/// Deterministic template engine in Vego's voice — the guaranteed path.
/// On-device Foundation Models upgrades this when available; the screen looks
/// identical either way, only `InsightSource` differs.
public enum CommentaryFallback {
    public static func generate(facts: CommentaryFacts) -> (String, InsightSource) {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("New territory. The Scanner has no baseline for you — yet.")
        } else if facts.netVolumeGrams > 0 {
            let lb = Int(Units.pounds(fromGrams: facts.netVolumeGrams).rounded())
            lines.append("+\(lb) lb over last time. Adequate.")
        } else if facts.netVolumeGrams < 0 {
            lines.append("Down from last time. Even I have off days. Few.")
        } else {
            lines.append("Identical to last time. Consistency — or complacency.")
        }

        if facts.powerLevelDelta > 0 {
            lines.append("Power level up \(facts.powerLevelDelta). Do it again Thursday.")
        }
        if facts.newBadgeCount > 0 {
            lines.append(facts.newBadgeCount == 1
                         ? "One new badge. Don't let it go to your head."
                         : "\(facts.newBadgeCount) new badges. Hmph. Not bad.")
        }
        return (lines.joined(separator: " "), .fallbackTemplate)
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// On-device commentary in Vego's voice (iOS 26+, Apple Intelligence devices).
@available(iOS 26.0, macOS 26.0, *)
public enum WorkoutCommentator {
    public static func generate(facts: CommentaryFacts) async -> (String, InsightSource) {
        guard case .available = SystemLanguageModel.default.availability else {
            return CommentaryFallback.generate(facts: facts)
        }
        let instructions = """
        You are Vego, the Ember Prince — a proud rival in a Saiyan-inspired fitness app. \
        Terse, acerbic, grudging respect. Reference the actual numbers given. \
        Never give medical, injury, or nutrition advice. Never suggest maxing out. \
        No real anime character names. At most 60 words.
        """
        let prompt = """
        Workout: \(facts.title)
        Net volume vs last time (grams): \(facts.netVolumeGrams) (first time: \(facts.netIsNew))
        Net reps: \(facts.netReps)
        New badges: \(facts.newBadgeCount)
        Power level delta: \(facts.powerLevelDelta)
        Write 2-3 sentences of post-workout commentary.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return (response.content, .onDevice)
        } catch {
            return CommentaryFallback.generate(facts: facts)
        }
    }
}
#endif
