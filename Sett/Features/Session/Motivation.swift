import Foundation

extension UUID {
    /// A deterministic seed from the UUID's bytes — STABLE across process launches,
    /// unlike `hashValue` (which Swift randomizes per process). Use for any seeded
    /// visual chrome that must recompute identically every launch.
    var stableSeed: Int {
        withUnsafeBytes(of: uuid) { raw in raw.reduce(0) { ($0 &* 31) &+ Int($1) } }
    }
    /// FNV-1a fold of the UUID bytes — a stable 64-bit seed for the LCG generators.
    var stableSeed64: UInt64 {
        withUnsafeBytes(of: uuid) { raw in
            raw.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        }
    }
}

// MARK: - Motivation (context-aware quotes between exercises)

/// The situation the lifter is in right now — chosen from sleep, layoff, and how
/// this session is actually going. Drives which pool a between-exercise quote is
/// pulled from.
enum MotivationContext {
    case push       // default — keep pushing, break limits
    case lowSleep   // ran on little sleep
    case offDay     // readiness down, or this session is underperforming
    case comeback   // first session back after a long layoff
    case cutting    // training in a deficit — celebrate retention, not just growth
}

/// Deterministic quote pools (never `.random` — selection is seeded so the same
/// transition always shows the same line). Voice matches the app: terse, all-caps
/// punches mixed with sharper aphorisms; DBZ-flavoured but originally phrased.
enum MotivationQuotes {
    static let push: [String] = [
        "PROGRESS OVER PERFECTION.",
        "There's one thing a warrior always keeps… THEIR PRIDE.",
        "Shatter your limits. Push into the domain of the gods.",
        "Comfort is the killer of joy, achievement, and fulfillment.",
        "Every limit is a door. Kick it off the hinges.",
        "BREAK YOUR OWN RECORD. The old you was only a warm-up.",
        "Strength is what remains after you refuse to stop.",
        "ONE MORE REP. That's where the old you dies.",
        "Pride is earned in the reps nobody clapped for.",
        "The ceiling you fear is just today's floor. CLIMB PAST IT.",
        "Talent naps while you train — every rep steals its crown.",
        "Push until the weight forgets it was ever heavier than you.",
    ]

    static let lowSleep: [String] = [
        "No sleep, still here. That isn't weakness. That is WILL.",
        "Energy runs out. Resolve doesn't. You brought the one that matters.",
        "The exhausted who show up outrank the rested who don't.",
        "YOUR BODY BEGGED TO STAY DOWN — YOU STOOD UP ANYWAY.",
        "Sleep is fuel. Heart is the engine. Yours is running.",
        "Tired is a feeling. SHOWING UP is a decision.",
        "Drained and dangerous — heart carries what the body cannot.",
        "Willpower doesn't check how you slept before it answers.",
    ]

    static let offDay: [String] = [
        "You don't rise on your best days. You rise on THESE.",
        "The base is poured on bad days. Add more concrete.",
        "Anyone trains when strong; champions train when it hurts.",
        "Show up flat, leave forged — dull days sharpen the blade.",
        "You won't set records today — set STANDARDS instead.",
        "Losing to the weight today? Return and collect the debt.",
        "Slow is still forward. Ugly is still work. CONTINUE.",
        "The weight didn't get heavier — you got humble. Lift anyway.",
    ]

    static let comeback: [String] = [
        "Welcome back. The rust burns off faster than you fear.",
        "You didn't lose it. You set it down. PICK IT BACK UP.",
        "Momentum forgives the pause. Move once and it comes home.",
        "The comeback starts quiet. One session, then the fire remembers.",
        "You're not starting over. You're starting stronger, wiser, hungrier.",
        "The layoff ends the second you touch the bar again.",
        "Every legend has a return chapter. Write yours today.",
        "You're not behind — you're reloading. Rebuild the streak.",
    ]

    /// Training in a deficit — hold the ceiling, climb pound-for-pound. A dip is
    /// the toll for getting lean, never a failure.
    static let cutting: [String] = [
        "LIGHTER FRAME, SAME FIRE. The Scanner still flags you as a threat.",
        "You held the ceiling on an empty tank. That reading counts double.",
        "Mass fell, power didn't — pound-for-pound, you just ascended.",
        "A dip in the cut is toll paid on the road to lean, not ground lost.",
        "Fuel runs low; output holds. THAT is discipline wearing a number.",
        "Defend the line. Steel doesn't rust because the plates got lighter.",
        "The bar stayed put while your bodyweight walked off. Math favors you.",
        "Every held rep in a deficit is armor you keep when the tanks refill.",
    ]

    private static func pool(for context: MotivationContext) -> [String] {
        switch context {
        case .push: push
        case .lowSleep: lowSleep
        case .offDay: offDay
        case .comeback: comeback
        case .cutting: cutting
        }
    }

    /// A stable, seeded pick — recompute-safe, never `.random`.
    static func line(for context: MotivationContext, seed: Int) -> String {
        let pool = pool(for: context)
        guard !pool.isEmpty else { return "KEEP PUSHING." }
        return pool[((seed % pool.count) + pool.count) % pool.count]
    }
}
