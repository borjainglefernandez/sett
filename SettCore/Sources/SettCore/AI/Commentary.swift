import Foundation

/// Structured facts only — never raw user text (no prompt injection, no embarrassing echo).
public struct CommentaryFacts: Sendable {
    public let title: String
    public let netReps: Int
    public let netVolumeGrams: Int
    public let netIsNew: Bool
    public let newBadgeCount: Int
    public let powerLevelDelta: Int
    /// "Off the record" workout — no numbers to celebrate, just the training itself.
    public let isCasual: Bool
    /// The phase this session was logged under — reframes a down or flat reading so a
    /// cut dip reads as the toll for leaning out and a maintain hold reads as a win,
    /// never as an off day or complacency. Defaults to `.maintaining` (steady is fine).
    public let phase: TrainingPhase

    public init(title: String, netReps: Int, netVolumeGrams: Int, netIsNew: Bool,
                newBadgeCount: Int, powerLevelDelta: Int, isCasual: Bool = false,
                phase: TrainingPhase = .maintaining) {
        self.title = title
        self.netReps = netReps
        self.netVolumeGrams = netVolumeGrams
        self.netIsNew = netIsNew
        self.newBadgeCount = newBadgeCount
        self.powerLevelDelta = powerLevelDelta
        self.isCasual = isCasual
        self.phase = phase
    }
}

/// Deterministic template engine in Vego's voice — the guaranteed path.
/// On-device Foundation Models upgrades this when available; the screen looks
/// identical either way, only `InsightSource` differs.
public enum CommentaryFallback {
    /// Terse Vego lines for an "off the record" workout — celebrate training for its
    /// own sake, zero numbers. Chosen deterministically so recompute is idempotent.
    static let casualLines = [
        "Off the record. Even a prince trains for the joy of it. Occasionally.",
        "The Scanner looked away. The work still happened.",
        "No numbers today. Just iron, and the quiet. Don't make a habit of it."
    ]

    public static func generate(facts: CommentaryFacts) -> (String, InsightSource) {
        if facts.isCasual {
            let raw = facts.netReps &+ facts.powerLevelDelta
            let index = ((raw % casualLines.count) + casualLines.count) % casualLines.count
            return (casualLines[index], .fallbackTemplate)
        }

        var lines: [String] = []

        if facts.netIsNew {
            lines.append("New territory. The Scanner has no baseline for you — yet.")
        } else if facts.netVolumeGrams > 0 {
            let lb = Int(Units.pounds(fromGrams: facts.netVolumeGrams).rounded())
            lines.append("+\(lb) lb over last time. Adequate.")
        } else if facts.netVolumeGrams < 0 {
            switch facts.phase {
            case .cutting:
                lines.append("Lighter tank, ceiling held. That counts double.")
            case .maintaining:
                lines.append("Dipped a touch. At altitude the line wavers — you're still holding it.")
            case .bulking:
                lines.append("Down from last time. Even I have off days. Few.")
            }
        } else {
            switch facts.phase {
            case .cutting:
                lines.append("Even, on less fuel. Holding the line in a deficit is a win.")
            case .maintaining:
                lines.append("Held the line. At altitude, steady IS the climb.")
            case .bulking:
                lines.append("Identical to last time. Consistency — or complacency.")
            }
        }

        if facts.powerLevelDelta > 0 {
            lines.append("Power level up \(facts.powerLevelDelta). Again soon. The chamber stays warm.")
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
        You are Vego, the Ember Prince — a proud rival in a cosmic warrior-themed fitness app. \
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
        Training phase: \(facts.phase.rawValue) — in a cut a dip is the toll for leaning out (praise retention); maintaining, steady is a win; bulking, push for more. Never frame a down or flat reading as failure.
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
