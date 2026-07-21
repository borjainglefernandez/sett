import Foundation

/// The Home-screen design concepts — five parallel, production-quality takes on
/// the app's front door, switchable live from Settings so they can be judged in
/// the hand, not in mockups. `classic` is the shipping stack-of-cards Home.
enum HomeConcept: String, CaseIterable, Identifiable {
    case classic, briefing, corridor, chamber, ledger, saga

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:  return "Classic"
        case .briefing: return "Briefing"
        case .corridor: return "Corridor"
        case .chamber:  return "Chamber"
        case .ledger:   return "Ledger"
        case .saga:     return "Saga"
        }
    }

    /// One-line pitch shown under the picker.
    var pitch: String {
        switch self {
        case .classic:  return "The shipping stack — doorway, week, directives."
        case .briefing: return "Scouter telemetry — a dense HUD that boots in."
        case .corridor: return "Your arc as a path — Vexeth stands on the road."
        case .chamber:  return "The realm is the interface — enter the door."
        case .ledger:   return "One number, one sentence, one action."
        case .saga:     return "Today as a hand of cards — swipe the saga."
        }
    }

    static let storageKey = "sett.home.concept"

    /// The selected concept, honoring the screenshot harness override.
    static var selected: HomeConcept {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SETT_DEBUG_HOMECONCEPT"],
           let forced = HomeConcept(rawValue: raw) {
            return forced
        }
        #endif
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return HomeConcept(rawValue: raw) ?? .classic
    }
}
