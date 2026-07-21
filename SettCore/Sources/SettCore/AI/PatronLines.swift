import Foundation

/// The patron's own words when one of THEIR badges premieres in the workout summary.
///
/// Cast law: a badge belongs to exactly one patron (see `PatronUnlocks.domains`), so
/// the line that greets a fresh medallion is spoken in that owning patron's voice and
/// no one else's — Barok weighs tonnage, Nyra keeps the streak, Torren marks the goal,
/// Luma reads the recovery, Gosi cheers the breadth, Zyn welcomes the comeback, and
/// Vego (the starter) presides over PRs and ceilings. Lines are terse, in-world, and
/// never taunt; a patron speaks only inside their own domain.
///
/// Pure and static — a plain key→line lookup with no state, so the summary can ask for
/// a line the instant a medallion lands. Unknown keys return nil (the summary simply
/// renders no line), so a config/app-version skew never trips this.
public enum PatronLines {

    /// The one-liner a patron speaks over their freshly-earned badge, or nil when the
    /// key has no line (unknown key, or a badge with no assigned voice).
    public static func line(forBadgeKey key: String) -> String? {
        lines[key]
    }

    /// badgeKey → the owning patron's line. Covers the full badge catalog in
    /// `PatronUnlocks.domains`, including keys retired from the live config, so a
    /// historical medallion still speaks. Voices, by domain:
    ///   vego = PRs & ceilings, barok = tonnage, nyra = streaks, torren = goals,
    ///   luma = sleep/recovery, gosi = breadth/dawn, zyn = comebacks.
    private static let lines: [String: String] = [
        // Vego — the Ember Prince: proud, terse, grudging respect.
        "new_ceiling":       "A new ceiling. I expected nothing less.",
        "limit_break":       "Ten times past your limit. It was never the ceiling holding you back. It was you.",
        "walking_legend":    "Fifty ceilings broken. Even I have to look up now. Slightly.",
        "triple_threat":     "Records on three fronts in one week. Show-off. Continue.",
        "perfect_form":      "Every lift forward, not one wasted. That is how a prince trains.",
        "scanner_breaker":   "Past nine thousand. The scanner called that impossible. The scanner was wrong.",

        // Barok — the Mountain: calm, earthbound, weighs everything in tonnage.
        "twenty_ton_day":    "That is real tonnage. The mountain nods.",
        "hundred_grand":     "A hundred thousand pounds moved. The ground remembers every one.",
        "million_pound_club":"A million pounds, carried piece by piece. You have moved a mountain.",
        "ten_million":       "Ten million. There is no weight left that fears you.",

        // Nyra Voss — the Tireless Android: precise, keeps the record of your streaks.
        "ignition":          "First scan logged. The record starts here. I will keep it.",
        "steady_flame":      "Four weeks held steady. Consistency is not luck. It is engineering.",
        "chamber_regular":   "Three days a week, four weeks running. The pattern holds.",
        "chamber_resident":  "Twelve weeks unbroken. You do not visit the chamber. You live here.",
        "unbroken_year":     "Fifty-two weeks, not one missed. A full orbit of discipline.",

        // Torren Vex — the Stern Mentor: goals and adherence, spare with praise.
        "goal_getter":       "You set a mark and met it. That is the whole discipline.",
        "marksman":          "Target called, target hit. No luck in that — only intent.",
        "serial_achiever":   "Ten goals closed out. You finish what you start. Rare.",
        "by_the_book":       "Twelve sessions, each on its planned day. By the book. Good.",
        "planners_pride":    "Every planned day, four weeks straight. The plan held because you did.",

        // Luma Q. — the Genius Engineer: reads recovery as data, warmly nerdy.
        "lab_partner":       "Seven nights of data. Now I can actually read you. Fascinating.",
        "well_rested":       "Rested, then strong. Recovery isn't idle time — it's the experiment working.",
        "recovery_protocol": "A full week of real sleep, and you still trained. Textbook.",

        // Gosi — the Bottomless: cheerful, hungry for variety and the dawn.
        "explorer":          "Twenty different lifts! I do love a full plate. What's next?",
        "full_arsenal":      "Every muscle inside a week — the whole buffet. That's my kind of appetite.",
        "dawn_patrol":       "Ten sunrises, ten sessions. The early iron tastes best, doesn't it?",

        // Zyn — the Hidden-Power Kid: quiet, shy strength, welcomes you back.
        "momentum":          "Five in a row, all forward. …you're rolling now. Don't stop.",
        "midnight_oil":      "Ten late nights in the chamber. …the quiet hours are ours.",
        "return_to_form":    "Three sessions after the long dark. …you found your way back.",
        "reforged":          "…you came back. Good.",
    ]
}
