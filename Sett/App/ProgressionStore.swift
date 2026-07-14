import Foundation
import SwiftData
import SwiftUI
import SettCore

/// Thin observable wrapper around the ProgressionEngine: recomputes the derived
/// snapshot (PL, XP, badges, tiers) from raw data and reconciles BadgeAward rows.
@MainActor
@Observable
public final class ProgressionStore {
    public private(set) var snapshot: ProgressionSnapshot?
    public private(set) var config: ProgressionConfig?

    public var snapshotPowerLevel: Int { snapshot?.powerLevel ?? 0 }

    public init() {
        self.config = try? ProgressionConfig.load()
    }

    public func recompute(context: ModelContext) {
        guard let config else { return }
        snapshot = try? ProgressionReconciler.reconcile(context: context, config: config)
        recordWeeklyPLSample()
        checkRivalRebirth()
    }

    public func tier(for character: CharacterKey) -> TransformationTier {
        snapshot?.tiers[character] ?? .base
    }

    public func level(for character: CharacterKey) -> Int {
        snapshot?.characterLevels[character] ?? 1
    }

    public func xp(for character: CharacterKey) -> Int {
        snapshot?.characterXP[character] ?? 0
    }

    // MARK: - Rival Rebirth (the endless race)
    //
    // Cycle 1 is the engine's scripted Vexeth. Beating his FINAL form triggers a
    // rebirth: he returns 10% above the user's PL with growth adapted to the user's
    // own trailing pace — clamped so the race stays winnable but never trivial.
    // State is app-side (UserDefaults): the engine stays a pure function of history.

    private enum RivalKeys {
        static let cycle = "sett.rival.cycle"
        static let startPL = "sett.rival.startPL"
        static let weeklyGrowth = "sett.rival.weeklyGrowth"
        static let cycleStart = "sett.rival.cycleStart"
        static let announce = "sett.rival.announce"
        static let plHistory = "sett.plHistory"   // [isoWeekKey: PL], trailing 8
    }

    public var rivalCycle: Int { max(1, UserDefaults.standard.integer(forKey: RivalKeys.cycle)) }

    /// True right after a rebirth until the UI acknowledges it.
    public var rivalRebirthAnnounce: Bool {
        UserDefaults.standard.bool(forKey: RivalKeys.announce)
    }

    public func acknowledgeRivalRebirth() {
        UserDefaults.standard.set(false, forKey: RivalKeys.announce)
        bumpRivalStateVersion()
    }

    /// Effective rival after rebirth cycles — cycle 1 defers to the engine.
    public var effectiveRival: (pl: Int, form: Int) {
        _ = rivalStateVersion   // observation hook
        guard let snapshot else { return (0, 1) }
        let defaults = UserDefaults.standard
        guard rivalCycle > 1,
              let cycleStart = defaults.object(forKey: RivalKeys.cycleStart) as? Date else {
            return (snapshot.rivalPL, snapshot.rivalForm)
        }
        let startPL = defaults.integer(forKey: RivalKeys.startPL)
        let growth = defaults.integer(forKey: RivalKeys.weeklyGrowth)
        let weeks = max(0, Calendar.current.dateComponents([.day], from: cycleStart, to: .now).day ?? 0) / 7
        let pl = startPL + growth * weeks
        let leadPL = (config?.rival["formRevealLeadPL"] as? Int) ?? 500
        let form = min(3, 1
                       + (snapshot.powerLevel > pl ? 1 : 0)
                       + (snapshot.allTimePeakPL > pl + leadPL ? 1 : 0))
        return (pl, form)
    }

    /// Tracked so @Observable views refresh when UserDefaults-backed rival state moves.
    private var rivalStateVersion = 0
    private func bumpRivalStateVersion() { rivalStateVersion += 1 }

    /// One PL sample per ISO week (overwritten within the week), trailing 8 kept —
    /// enough for the pace math without storing a real time series.
    private func recordWeeklyPLSample() {
        guard let snapshot else { return }
        let defaults = UserDefaults.standard
        var history = defaults.dictionary(forKey: RivalKeys.plHistory) as? [String: Int] ?? [:]
        history[Self.isoWeekKey(.now)] = snapshot.powerLevel
        if history.count > 8 {
            let sorted = history.keys.sorted()
            for key in sorted.prefix(history.count - 8) { history.removeValue(forKey: key) }
        }
        defaults.set(history, forKey: RivalKeys.plHistory)
    }

    /// Mean weekly ΔPL over the trailing samples (0 when flat or insufficient data).
    public var trailingWeeklyPace: Int {
        let history = UserDefaults.standard.dictionary(forKey: RivalKeys.plHistory) as? [String: Int] ?? [:]
        let ordered = history.keys.sorted().suffix(5).compactMap { history[$0] }
        guard ordered.count >= 2 else { return 0 }
        let deltas = zip(ordered.dropFirst(), ordered).map { $0 - $1 }
        return max(0, deltas.reduce(0, +) / deltas.count)
    }

    private func checkRivalRebirth() {
        guard let snapshot else { return }
        let rival = effectiveRival
        // Rebirth fires only when the FINAL form has been beaten.
        guard rival.form >= 3, snapshot.powerLevel > rival.pl else { return }
        let defaults = UserDefaults.standard
        let newStart = Int((Double(snapshot.powerLevel) * 1.10 / 100).rounded(.up)) * 100
        let pace = trailingWeeklyPace
        let configGrowth = (config?.rival["weeklyGrowth"] as? Int) ?? 350
        // Adaptive growth: 1.15× the user's own pace, floored at 50 so a slow rival
        // still moves, ceilinged at 2× pace (or the scripted growth when pace is 0)
        // so he never becomes uncatchable.
        let newGrowth = pace > 0
            ? min(max(Int(Double(pace) * 1.15), 50), pace * 2)
            : min(configGrowth, max(50, snapshot.powerLevel / 40))
        defaults.set(rivalCycle + 1, forKey: RivalKeys.cycle)
        defaults.set(newStart, forKey: RivalKeys.startPL)
        defaults.set(newGrowth, forKey: RivalKeys.weeklyGrowth)
        defaults.set(Date.now, forKey: RivalKeys.cycleStart)
        defaults.set(true, forKey: RivalKeys.announce)
        bumpRivalStateVersion()
    }

    static func isoWeekKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }

    /// The rival's CURRENT weekly growth (scripted for cycle 1, adaptive after).
    public var effectiveRivalGrowth: Int {
        if rivalCycle > 1 {
            return UserDefaults.standard.integer(forKey: RivalKeys.weeklyGrowth)
        }
        return (config?.rival["weeklyGrowth"] as? Int) ?? 350
    }

    /// Last completed week's ΔPL (last week's sample minus the week before's) —
    /// the Weekly Power Reading's headline. nil until two weekly samples exist.
    public var weeklyReadingDelta: Int? {
        let history = UserDefaults.standard.dictionary(forKey: RivalKeys.plHistory) as? [String: Int] ?? [:]
        let cal = Calendar.current
        let lastWeek = Self.isoWeekKey(cal.date(byAdding: .day, value: -7, to: .now) ?? .now)
        let weekBefore = Self.isoWeekKey(cal.date(byAdding: .day, value: -14, to: .now) ?? .now)
        guard let a = history[lastWeek], let b = history[weekBefore] else { return nil }
        return a - b
    }

    /// This week's ΔPL so far (nil until last week has a sample) — the Weekly
    /// Power Reading's headline.
    public var plDeltaThisWeek: Int? {
        let history = UserDefaults.standard.dictionary(forKey: RivalKeys.plHistory) as? [String: Int] ?? [:]
        guard let snapshot else { return nil }
        let lastWeekKey = Self.isoWeekKey(Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now)
        guard let lastWeekPL = history[lastWeekKey] else { return nil }
        return snapshot.powerLevel - lastWeekPL
    }
}


/// Progression-redesign switches (audit: "one spine number"). Legacy per-character
/// XP/levels stay computed by the engine until Phase 3 deletes them; this flag only
/// controls whether any UI still renders them.
enum ProgressionUIFlags {
    static let legacyXPVisible = false
}
