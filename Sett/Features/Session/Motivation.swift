import Foundation

// MARK: - Motivation (context-aware quotes between exercises)

/// The situation the lifter is in right now — chosen from sleep, layoff, and how
/// this session is actually going. Drives which pool a between-exercise quote is
/// pulled from.
enum MotivationContext {
    case push       // default — keep pushing, break limits
    case lowSleep   // ran on little sleep
    case offDay     // readiness down, or this session is underperforming
    case comeback   // first session back after a long layoff
}

/// Deterministic quote pools (never `.random` — selection is seeded so the same
/// transition always shows the same line). Voice matches the app: terse, all-caps
/// punches mixed with sharper aphorisms; DBZ-flavoured but originally phrased.
enum MotivationQuotes {
    static let push: [String] = [
        "PROGRESS OVER PERFECTION.",
        "There's one thing a Saiyan always keeps… THEIR PRIDE.",
        "Shatter your limits. Push into the domain of the gods.",
        "Comfort is the killer of joy, achievement, and fulfillment.",
        "Giving up is a betrayal of your own potential.",
        "Power comes in response to a need. So create the need.",
        "The set you fear is the set that forges you.",
        "You don't find your limit. You break it.",
        "Chase the version of you that scares the old you.",
        "One more rep is one more reason they remember your name.",
    ]

    static let lowSleep: [String] = [
        "Ran on empty? Showing up IS the win today.",
        "A champion is someone who gets up when they can't.",
        "Half-charged still moves mountains. One honest set.",
        "Tired is a feeling. The iron doesn't care. Move.",
        "Low battery, same warrior. Don't stop — just start.",
        "You're here on no fuel. That isn't weakness. It's will.",
    ]

    static let offDay: [String] = [
        "Off day? Answer it with one honest rep.",
        "Bad days build the foundation. Stay in the fight.",
        "Defeat is temporary. Quitting makes it permanent.",
        "The days you don't feel it are the days that count double.",
        "Not every scan is a record. Showing up still wins.",
        "Grind through the fog. The Chamber rewards the stubborn.",
    ]

    static let comeback: [String] = [
        "Back in the Chamber. The iron missed you.",
        "The comeback is always stronger than the setback.",
        "First session back is the hardest rep — and it's done.",
        "Rust is temporary. The rebuild starts NOW.",
        "You returned. Everything from here is momentum.",
        "Welcome back, warrior. Reclaim what's yours.",
    ]

    private static func pool(for context: MotivationContext) -> [String] {
        switch context {
        case .push: push
        case .lowSleep: lowSleep
        case .offDay: offDay
        case .comeback: comeback
        }
    }

    /// A stable, seeded pick — recompute-safe, never `.random`.
    static func line(for context: MotivationContext, seed: Int) -> String {
        let pool = pool(for: context)
        guard !pool.isEmpty else { return "KEEP PUSHING." }
        return pool[((seed % pool.count) + pool.count) % pool.count]
    }
}
