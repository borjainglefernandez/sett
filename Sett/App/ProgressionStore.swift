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

    /// The power-level trajectory (one point per training day, oldest → now).
    /// Derived fresh every recompute — no persisted time series, so it stays a
    /// pure function of history and backfills retroactively.
    public var powerLevelHistory: [PLPoint] { snapshot?.powerLevelHistory ?? [] }

    /// What the CURRENT power level is made of — its strength / volume / streak-bonus
    /// pieces. nil until there's a real PL to decompose (or before config loads).
    public var powerLevelComposition: PLComposition? {
        guard let snapshot, snapshot.powerLevel > 0, let config else { return nil }
        return PowerLevelBreakdown.composition(
            strengthScore: snapshot.strengthScore,
            weeklyVolumeLb: snapshot.weeklyVolumeLb,
            consistencyMultiplier: snapshot.consistencyMultiplier,
            config: config)
    }

    /// What MOVED the power level over the trailing `days` window — a signed split
    /// across strength / volume / consistency that sums exactly to the delta. The
    /// baseline is the last trajectory point at or before the window's start (else the
    /// earliest point we have); nil until two distinct-day points exist, or when the
    /// baseline is already the latest point (nothing to attribute).
    public func powerLevelAttribution(overDays days: Int) -> PLAttribution? {
        guard let config else { return nil }
        let history = powerLevelHistory
        guard history.count >= 2, let latest = history.last else { return nil }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now)) ?? .now
        let baseline = history.last { $0.date <= cutoff } ?? history[0]
        guard baseline.date != latest.date else { return nil }
        return PowerLevelBreakdown.attribution(from: baseline, to: latest, config: config)
    }

    /// ISO calendar (Monday weeks) so the weekly buckets match the streak engine.
    private static let isoWeekCalendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal
    }()

    /// The PL change per ISO week over the trailing `weeks` — the week-by-week rhythm
    /// of the climb (rest weeks read as a flat 0). Derived from powerLevelHistory, so
    /// it stays retroactive and needs no stored series.
    public func powerLevelWeeklyChanges(weeks: Int = 12) -> [WeeklyPLChange] {
        PowerLevelBreakdown.weeklyChanges(history: powerLevelHistory,
                                          calendar: Self.isoWeekCalendar, weeks: weeks)
    }

    public init() {
        self.config = try? ProgressionConfig.load()
    }

    public func recompute(context: ModelContext) {
        guard let config else { return }
        snapshot = try? ProgressionReconciler.reconcile(context: context, config: config)
        refreshUnlockedPatrons(context: context)
        recordWeeklyPLSample()
        checkRivalRebirth()
        recordHighestSeenRivalForm()
        seedFormBaselineIfNeeded()
    }

    /// The USER's transformation frame (cast collapse: per-character tiers are gone;
    /// the avatar wears the user's own form, a pure function of PL).
    public var userFormTier: TransformationTier {
        TransformationTier(rawValue: min(UserForm.form(forPL: snapshotPowerLevel).index, 4)) ?? .base
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
        static let highestSeenForm = "sett.rival.highestSeenForm"
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
        // The user just BEAT form 3 — stamp the high-water mark before the new
        // cycle resets him to form 1, or the witness record would lose it.
        defaults.set(3, forKey: RivalKeys.highestSeenForm)
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

    /// The deepest Vexeth form the user has ever witnessed (1…3) — a high-water
    /// mark, so a rebirth resetting him to form 1 never re-hides a form that has
    /// already been revealed. Bumps happen only in the recompute/rebirth paths;
    /// this getter is side-effect free.
    public var highestSeenRivalForm: Int {
        _ = rivalStateVersion   // observation hook
        return max(1, UserDefaults.standard.integer(forKey: RivalKeys.highestSeenForm))
    }

    /// Raise the high-water mark to the rival's current form (never regresses).
    private func recordHighestSeenRivalForm() {
        let defaults = UserDefaults.standard
        let form = effectiveRival.form
        if form > defaults.integer(forKey: RivalKeys.highestSeenForm) {
            defaults.set(form, forKey: RivalKeys.highestSeenForm)
            bumpRivalStateVersion()
        }
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

    // MARK: - Form ascension surfacing (level-up banner + Power-tab odometer)
    //
    // The USER's form is a pure function of PL (UserForm — the endless Forms ladder).
    // Two app-side flags let the UI CELEBRATE a crossing OUTSIDE the finish screen —
    // the level-up should always get its beat, whether it happened on a triggering set,
    // via a recompute, or just by re-opening the app:
    //   • lastSeenFormIndex — the highest form rung the user has acknowledged; a higher
    //     current index means an unacknowledged ascension → the persistent banner shows.
    //   • lastViewedPL — the PL the Power tab last rolled its odometer to; the roll's
    //     START value on the next appearance, so re-opening after a gain animates from
    //     where you left off instead of snapping.
    // Both live in UserDefaults (mirroring the Rival-announce template) so the engine
    // stays a pure function of history. Reads are made @Observable-safe via a version bump.

    private enum FormKeys {
        static let lastSeenFormIndex = "sett.form.lastSeenIndex"
        static let lastViewedPL = "sett.power.lastViewedPL"
    }

    /// The user's current form on the endless ladder (pure function of PL). Unlike
    /// `userFormTier`, this is NOT clamped to 0…4 — it reads Zenith II, III, … so a
    /// crossing past Zenith is still detected.
    public var userForm: UserForm { UserForm.form(forPL: snapshotPowerLevel) }

    /// Progress through the current form, 0…1 — the Ki gauge's fill fraction.
    public var formProgress: Double { userForm.progress(snapshotPowerLevel) }

    /// Bumped when the ascension baseline is acknowledged, so @Observable views
    /// re-read the UserDefaults-backed pending state.
    private var formStateVersion = 0
    private func bumpFormStateVersion() { formStateVersion += 1 }

    /// Seed the ascension/odometer baselines to the CURRENT state the first time we
    /// ever compute — so an existing install (already at, say, RADIANT) doesn't fire a
    /// false "ascended" banner on first launch after this feature ships. Real crossings
    /// after the baseline is set still fire.
    private func seedFormBaselineIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: FormKeys.lastSeenFormIndex) == nil {
            defaults.set(userForm.index, forKey: FormKeys.lastSeenFormIndex)
        }
        if defaults.object(forKey: FormKeys.lastViewedPL) == nil {
            defaults.set(snapshotPowerLevel, forKey: FormKeys.lastViewedPL)
        }
    }

    /// The form to celebrate if the user has crossed a threshold since last
    /// acknowledged — nil once acknowledged (or before the baseline is seeded).
    public var pendingAscension: UserForm? {
        _ = formStateVersion   // observation hook
        guard let lastSeen = UserDefaults.standard.object(forKey: FormKeys.lastSeenFormIndex) as? Int
        else { return nil }
        return userForm.index > lastSeen ? userForm : nil
    }

    /// The user has seen the ascension banner — bank the current form so it won't
    /// show again until the next crossing.
    public func acknowledgeAscension() {
        UserDefaults.standard.set(userForm.index, forKey: FormKeys.lastSeenFormIndex)
        bumpFormStateVersion()
    }

    /// The PL the Power tab last rolled the odometer to — the roll's START value on the
    /// next appearance. Defaults to the current PL (so a first-ever view doesn't roll
    /// from a stale/zero value).
    public var lastViewedPowerLevel: Int {
        UserDefaults.standard.object(forKey: FormKeys.lastViewedPL) as? Int ?? snapshotPowerLevel
    }

    /// Bank the current PL as "seen" on the Power tab (called once the roll kicks off).
    public func markPowerLevelViewed() {
        UserDefaults.standard.set(snapshotPowerLevel, forKey: FormKeys.lastViewedPL)
    }

    // MARK: - Patron awakenings (the cast assembles)
    //
    // Patrons are voices, not parallel ladders: each awakens when the user earns
    // their FIRST badge in that patron's domain (Vego, the starter, was always
    // here). Unlocks are DERIVED from the live BadgeAward ledger on every
    // recompute — no new SwiftData model, fully retroactive, self-healing when
    // history changes. Acks are app-side (UserDefaults), mirroring the
    // Rival-announce template, and deliberately sticky: if the earning badge is
    // later hard-deleted the patron may re-lock, but replaying the awakening
    // ceremony on a re-earn would cheapen it — so the ack set is never pruned.

    private enum PatronKeys {
        static let acknowledged = "sett.patrons.acknowledged"   // [CharacterKey rawValue]
    }

    /// Patrons whose voices have awakened — refreshed from the badge ledger
    /// inside recompute(). Always contains Vego.
    public private(set) var unlockedPatrons: Set<CharacterKey> = [.vego]

    /// Bumped when an awakening is acknowledged so @Observable views re-read the
    /// UserDefaults-backed pending state.
    private var patronStateVersion = 0
    private func bumpPatronStateVersion() { patronStateVersion += 1 }

    #if DEBUG
    /// Settings → DEBUG: force a specific patron's awakening ceremony on next
    /// appearance without earning the badge. Cleared by acknowledging it.
    public var debugForcedAwakening: CharacterKey?
    #endif

    /// Re-derive the unlocked set from the freshly reconciled badge ledger —
    /// same fetch-then-filter shape ProgressionReconciler uses for the same rows.
    private func refreshUnlockedPatrons(context: ModelContext) {
        let awards = (try? context.fetch(FetchDescriptor<BadgeAward>())) ?? []
        let liveKeys = awards.lazy.filter { $0.deletedAt == nil }.map(\.badgeKey)
        unlockedPatrons = PatronUnlocks.unlockedPatrons(badgeKeys: liveKeys)
    }

    /// The awakening to celebrate, if any: the first patron in cast order that is
    /// unlocked but not yet acknowledged. Vego never announces — he starts unlocked.
    public var pendingPatronAwakening: CharacterKey? {
        _ = patronStateVersion   // observation hook
        #if DEBUG
        if let forced = debugForcedAwakening { return forced }
        #endif
        let acknowledged = Set(UserDefaults.standard.stringArray(forKey: PatronKeys.acknowledged) ?? [])
        return CharacterKey.allCases.first {
            $0 != .vego && unlockedPatrons.contains($0) && !acknowledged.contains($0.rawValue)
        }
    }

    /// The user has seen the awakening — bank it so it never announces again.
    public func acknowledgePatronAwakening() {
        #if DEBUG
        if debugForcedAwakening != nil {
            debugForcedAwakening = nil
            return
        }
        #endif
        guard let pending = pendingPatronAwakening else { return }
        var acknowledged = UserDefaults.standard.stringArray(forKey: PatronKeys.acknowledged) ?? []
        if !acknowledged.contains(pending.rawValue) { acknowledged.append(pending.rawValue) }
        UserDefaults.standard.set(acknowledged, forKey: PatronKeys.acknowledged)
        bumpPatronStateVersion()
    }

    #if DEBUG
    /// Force the next Home/Power appearance to show the ascension banner (Settings →
    /// DEBUG): roll the acknowledged index back one rung so the current form reads as a
    /// fresh crossing. No-op at BASE (nothing below to cross from).
    public func debugForcePendingAscension() {
        UserDefaults.standard.set(max(0, userForm.index - 1), forKey: FormKeys.lastSeenFormIndex)
        bumpFormStateVersion()
    }

    /// Force the Power tab's odometer to roll on next appearance by pretending the last
    /// viewed PL was 200 below the current one.
    public func debugRewindLastViewedPowerLevel() {
        UserDefaults.standard.set(max(0, snapshotPowerLevel - 200), forKey: FormKeys.lastViewedPL)
    }
    #endif
}

