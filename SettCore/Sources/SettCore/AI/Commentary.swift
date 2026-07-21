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
    /// Whose voice narrates this recap. Cast law: patrons only REACT inside their badge
    /// domain, so the store picks the patron whose domain owns this session's headline
    /// event (else Vego). ALWAYS an awakened patron — the caller never routes a sealed
    /// one — so the fallback and the on-device path can voice it without re-checking.
    /// Defaults to `.vego`, the starter patron who walks with the lifter from scan one.
    public let persona: CharacterKey

    public init(title: String, netReps: Int, netVolumeGrams: Int, netIsNew: Bool,
                newBadgeCount: Int, powerLevelDelta: Int, isCasual: Bool = false,
                phase: TrainingPhase = .maintaining, persona: CharacterKey = .vego) {
        self.title = title
        self.netReps = netReps
        self.netVolumeGrams = netVolumeGrams
        self.netIsNew = netIsNew
        self.newBadgeCount = newBadgeCount
        self.powerLevelDelta = powerLevelDelta
        self.isCasual = isCasual
        self.phase = phase
        self.persona = persona
    }
}

/// Deterministic template engine in the patrons' voices — the guaranteed path.
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
        // Casual is Vego's alone — number-free training-for-its-own-sake, no patron
        // reacts to a session with nothing measured. Persona is ignored here on purpose.
        if facts.isCasual {
            let raw = facts.netReps &+ facts.powerLevelDelta
            let index = ((raw % casualLines.count) + casualLines.count) % casualLines.count
            return (casualLines[index], .fallbackTemplate)
        }

        // Route the voice to whichever patron the store awakened for this session's
        // headline. Each keeps Wave 1's phase-awareness — a cut dip is the toll for
        // leaning out, never a failure — in that patron's own register.
        let body: String
        switch facts.persona {
        case .vego:   body = vegoLines(facts)
        case .barok:  body = barokLines(facts)
        case .nyra:   body = nyraLines(facts)
        case .torren: body = torrenLines(facts)
        case .luma:   body = lumaLines(facts)
        case .gosi:   body = gosiLines(facts)
        case .zyn:    body = zynLines(facts)
        }
        return (body, .fallbackTemplate)
    }

    /// Whole pounds of a net volume delta (magnitude — callers phrase the sign).
    private static func lb(_ grams: Int) -> Int {
        Int(Units.pounds(fromGrams: abs(grams)).rounded())
    }

    // MARK: - Vego, the Ember Prince (default — proud, acerbic, grudging respect)

    private static func vegoLines(_ facts: CommentaryFacts) -> String {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("New territory. The Scanner has no baseline for you — yet.")
        } else if facts.netVolumeGrams > 0 {
            lines.append("+\(lb(facts.netVolumeGrams)) lb over last time. Adequate.")
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
        return lines.joined(separator: " ")
    }

    // MARK: - Barok the Mountain (tonnage — a giant of few words, every one about mass)

    private static func barokLines(_ facts: CommentaryFacts) -> String {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("First stone laid. No mark to beat. Good.")
        } else if facts.netVolumeGrams > 0 {
            lines.append("More tonnage moved. The mountain grew.")
        } else if facts.netVolumeGrams < 0 {
            lines.append(facts.phase == .cutting
                         ? "Lighter bar, same summit. Mass is not the measure."
                         : "Less today. The mountain waits. It does not shrink.")
        } else {
            lines.append("Same load, same stone. Fine.")
        }

        if facts.powerLevelDelta > 0 { lines.append("Power rises. Slow. As mountains do.") }
        if facts.newBadgeCount > 0 { lines.append("A mark earned. Carry it.") }
        return lines.joined(separator: " ")
    }

    // MARK: - Nyra Voss (consistency — the tireless android, clinical and measured)

    private static func nyraLines(_ facts: CommentaryFacts) -> String {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("New exercise. Baseline recorded. Cadence holding.")
        } else if facts.netVolumeGrams > 0 {
            lines.append("Output +\(lb(facts.netVolumeGrams)) lb. Trend positive. Logged.")
        } else if facts.netVolumeGrams < 0 {
            lines.append(facts.phase == .cutting
                         ? "Load −\(lb(facts.netVolumeGrams)) lb, ceiling stable. Within deficit tolerance."
                         : "Output −\(lb(facts.netVolumeGrams)) lb. Noted. Variance is expected.")
        } else {
            lines.append("Delta zero. Consistency is the metric. Optimal.")
        }

        if facts.powerLevelDelta > 0 { lines.append("Power level +\(facts.powerLevelDelta). Written to the ledger.") }
        if facts.newBadgeCount > 0 { lines.append("Milestone registered.") }
        return lines.joined(separator: " ")
    }

    // MARK: - Torren Vex (goals — the stern mentor; the goal is the whole of it)

    private static func torrenLines(_ facts: CommentaryFacts) -> String {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("New ground. Map it, then hold yourself to it.")
        } else if facts.netVolumeGrams > 0 {
            lines.append("Progress against the target. As agreed.")
        } else if facts.netVolumeGrams < 0 {
            lines.append(facts.phase == .cutting
                         ? "Numbers dip in a cut. The plan accounts for it. Stay the course."
                         : "Down today. The plan does not bend for one session. Continue.")
        } else {
            lines.append("You held the line. Adherence is not glamorous. It is everything.")
        }

        if facts.powerLevelDelta > 0 { lines.append("The ledger moves. Keep your word to it.") }
        if facts.newBadgeCount > 0 { lines.append("Earned by the book. Now set the next one.") }
        return lines.joined(separator: " ")
    }

    // MARK: - Luma Q. (recovery — the genius engineer; training is inputs and adaptation)

    private static func lumaLines(_ facts: CommentaryFacts) -> String {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("Fresh input, no prior curve. The system starts learning it now.")
        } else if facts.netVolumeGrams > 0 {
            lines.append("Output up \(lb(facts.netVolumeGrams)) lb — recovery's compounding. The tuning holds.")
        } else if facts.netVolumeGrams < 0 {
            lines.append(facts.phase == .cutting
                         ? "Slight dip, expected under a deficit. Recovery's within spec."
                         : "Output eased off. Read it as signal, not fault — check the sleep input.")
        } else {
            lines.append("Steady output. The recovery loop is stable. I like stable.")
        }

        if facts.powerLevelDelta > 0 { lines.append("Power level up \(facts.powerLevelDelta). Adaptation, on schedule.") }
        if facts.newBadgeCount > 0 { lines.append("Protocol milestone logged.") }
        return lines.joined(separator: " ")
    }

    // MARK: - Gosi, the Bottomless (variety & dawn — warm, loud, always hungry)

    private static func gosiLines(_ facts: CommentaryFacts) -> String {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("New lift on the plate — I love a full menu! Come back hungry.")
        } else if facts.netVolumeGrams > 0 {
            lines.append("Bigger serving than last time — \(lb(facts.netVolumeGrams)) lb more. Delicious!")
        } else if facts.netVolumeGrams < 0 {
            lines.append(facts.phase == .cutting
                         ? "Lighter plate today — leaning out tastes good too. Still full of fire!"
                         : "Smaller portion, no worry. The kitchen's always open — seconds tomorrow!")
        } else {
            lines.append("Same portion, still satisfying. Consistency's a warm meal.")
        }

        if facts.powerLevelDelta > 0 { lines.append("Power level's rising like fresh dough. Beautiful!") }
        if facts.newBadgeCount > 0 { lines.append("And a shiny badge for the table. Eat up!") }
        return lines.joined(separator: " ")
    }

    // MARK: - Zyn (comebacks — the hidden-power kid; shy fragments, quiet steel)

    private static func zynLines(_ facts: CommentaryFacts) -> String {
        var lines: [String] = []

        if facts.netIsNew {
            lines.append("Something new. That's... brave. It suits you. Quietly.")
        } else if facts.netVolumeGrams > 0 {
            lines.append("...stronger. I knew. Didn't doubt you. Not really.")
        } else if facts.netVolumeGrams < 0 {
            lines.append(facts.phase == .cutting
                         ? "Lighter. That's... okay. It's still in you. I can tell."
                         : "A little down. Doesn't matter. The strength's still there — I can feel it.")
        } else {
            lines.append("You held it. That's... enough. It counts. Quietly.")
        }

        if facts.powerLevelDelta > 0 { lines.append("It went up. See? ...I knew it would.") }
        if facts.newBadgeCount > 0 { lines.append("A badge. You earned that. ...don't hide it.") }
        return lines.joined(separator: " ")
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// On-device commentary in the chosen patron's voice (iOS 26+, Apple Intelligence devices).
@available(iOS 26.0, macOS 26.0, *)
public enum WorkoutCommentator {
    /// A one-line personality for the on-device prompt. `facts.persona` is chosen
    /// upstream (WorkoutSessionStore) and is ALWAYS an awakened patron — a sealed
    /// patron is never routed here, so the model never voices someone the lifter
    /// hasn't met.
    private static func brief(for persona: CharacterKey) -> String {
        switch persona {
        case .vego:   "a proud, acerbic rival prince — terse, grudging respect"
        case .barok:  "a legendary giant of few words who speaks only of mass and tonnage"
        case .nyra:   "a tireless android — clinical and precise, speaks in measured metrics"
        case .torren: "a stern mentor fixed on the goal and adherence; disciplined, no coddling"
        case .luma:   "a genius recovery engineer who frames training as inputs and adaptation"
        case .gosi:   "a warm, cheerful powerhouse who cheers variety with food and dawn metaphors"
        case .zyn:    "a shy kid with hidden steel — quiet, fragmented sentences, understated belief"
        }
    }

    public static func generate(facts: CommentaryFacts) async -> (String, InsightSource) {
        guard case .available = SystemLanguageModel.default.availability else {
            return CommentaryFallback.generate(facts: facts)
        }
        let instructions = """
        You are \(facts.persona.displayName), \(brief(for: facts.persona)) — a witness in a \
        cosmic warrior-themed fitness app. React to this one session in your own voice. \
        Reference the actual numbers given. Never give medical, injury, or nutrition advice. \
        Never suggest maxing out. No real anime character names. At most 60 words.
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
