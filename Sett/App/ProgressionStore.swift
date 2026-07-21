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
        advanceRival()
        recordHighestSeenRivalForm()
        seedFormBaselineIfNeeded()
    }

    /// The USER's transformation frame (cast collapse: per-character tiers are gone;
    /// the avatar wears the user's own form, a pure function of PL).
    public var userFormTier: TransformationTier {
        TransformationTier(rawValue: min(UserForm.form(forPL: snapshotPowerLevel).index, 4)) ?? .base
    }

    // MARK: - Rival state machine (the endless race)
    //
    // "He never trains, he responds." The engine hands us an absence-frozen, pace-aware
    // BASELINE (snapshot.rivalPL) and the qualifying day-starts; the STORE owns the
    // per-cycle form machine — a real three-climb race — persisted in UserDefaults:
    //   • Each form has a base PL (formStartPL) and a growth clock (formStartDate). His
    //     effective PL creeps up daily, but only across weeks the user actually trained.
    //   • Out-climb the current form and Vexeth SURGES: his base leaps ~6% clear of the
    //     user and the NEXT form is revealed (pendingRivalFormReveal). So Star -> Nova ->
    //     Singularity are three distinct fights — the Singularity can't be revealed and
    //     beaten in one tick.
    //   • Out-climb the surged Form 3 and rebirth fires (checkRivalRebirth): a new cycle,
    //     Form 1 at ~10% above the user. Growth is always capped near the user's own pace
    //     so the race is winnable for anyone; a zero-session week never advances him.
    // The engine stays a pure function of history; all persisted state lives here.

    /// Floor on Vexeth's weekly growth — he still creeps while the user climbs, but the
    /// pace-aware cap keeps him from ever out-running a consistent trainer.
    private static let rivalGrowthFloor = 50

    private enum RivalKeys {
        static let cycle = "sett.rival.cycle"
        static let currentForm = "sett.rival.currentForm"   // this cycle's form, 1...3
        static let formStartPL = "sett.rival.formStartPL"   // current form's base (surge base)
        static let formStartDate = "sett.rival.formStartDate" // current form's growth clock
        static let formReveal = "sett.rival.formReveal"     // 2/3 when a form just revealed
        static let announce = "sett.rival.announce"         // rebirth just fired
        static let highestSeenForm = "sett.rival.highestSeenForm"
        static let plHistory = "sett.plHistory"             // [isoWeekKey: PL], trailing 8
        // Legacy keys (pre form-machine) — read only to migrate an in-flight cycle.
        static let startPL = "sett.rival.startPL"
        static let weeklyGrowth = "sett.rival.weeklyGrowth"
        static let cycleStart = "sett.rival.cycleStart"
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

    /// Vexeth's live PL and current form — the app-side authority for every rival
    /// surface. His PL is his form's base plus growth accrued over ACTIVE weeks since the
    /// form began, pro-rated by day so he creeps a little each day (never on a week the
    /// user skipped). Before the machine is seeded (no training yet) it defers to the
    /// engine baseline. Side-effect free — the surge/rebirth transitions run in
    /// `advanceRival()` during recompute.
    public var effectiveRival: (pl: Int, form: Int) {
        _ = rivalStateVersion   // observation hook
        let defaults = UserDefaults.standard
        let startPL = (config?.rival["startPL"] as? Int) ?? 0
        guard let snapshot else { return (startPL, 1) }
        guard defaults.object(forKey: RivalKeys.formStartPL) != nil,
              let formStartDate = defaults.object(forKey: RivalKeys.formStartDate) as? Date else {
            return (snapshot.rivalPL, snapshot.rivalForm)
        }
        let base = defaults.integer(forKey: RivalKeys.formStartPL)
        let form = max(1, defaults.integer(forKey: RivalKeys.currentForm))
        let weeks = ProgressionEngine.rivalEffectiveWeeks(
            qualifyingDayStarts: snapshot.qualifyingDayStarts,
            clockStart: formStartDate, asOf: .now,
            calendar: Self.isoWeekCalendar, proRateCurrentWeek: true)
        let pl = ProgressionEngine.rivalEffectivePL(
            base: base, weeklyGrowth: effectiveRivalGrowth, weeks: weeks)
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

    /// True once there are >= 2 weekly PL samples — enough to read a pace. Before that
    /// Vexeth runs his scripted opening menace instead of the pace-aware cap.
    private var rivalHasTrend: Bool {
        let history = UserDefaults.standard.dictionary(forKey: RivalKeys.plHistory) as? [String: Int] ?? [:]
        return history.count >= 2
    }

    /// Seed the form-machine state the first time the user has trained (or migrate an
    /// in-flight legacy rebirth cycle into it). Idempotent — guarded on formStartPL.
    private func seedRivalStateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: RivalKeys.formStartPL) == nil else { return }
        guard let first = snapshot?.qualifyingDayStarts.first else { return }
        if rivalCycle > 1,
           let legacyStart = defaults.object(forKey: RivalKeys.startPL) as? Int,
           let legacyStartDate = defaults.object(forKey: RivalKeys.cycleStart) as? Date {
            defaults.set(legacyStart, forKey: RivalKeys.formStartPL)
            defaults.set(legacyStartDate, forKey: RivalKeys.formStartDate)
            defaults.set(1, forKey: RivalKeys.currentForm)
        } else {
            let startPL = (config?.rival["startPL"] as? Int) ?? 3000
            defaults.set(startPL, forKey: RivalKeys.formStartPL)
            defaults.set(first, forKey: RivalKeys.formStartDate)
            defaults.set(1, forKey: RivalKeys.currentForm)
        }
    }

    /// One tick of the form machine: seed if needed, then let the engine's pure step
    /// decide. Out-climbing a form makes Vexeth SURGE (base leaps clear of the user,
    /// next form revealed); out-climbing the final form triggers rebirth. At most one
    /// transition per recompute — the surge immediately re-takes the lead.
    private func advanceRival() {
        guard let snapshot else { return }
        seedRivalStateIfNeeded()
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: RivalKeys.formStartPL) != nil else { return }
        let eff = effectiveRival
        let surgeFactor = (config?.rival["surgeFactor"] as? Double) ?? 1.06
        let step = ProgressionEngine.rivalFormStep(
            currentForm: eff.form,
            currentBasePL: defaults.integer(forKey: RivalKeys.formStartPL),
            effectivePL: eff.pl, userPL: snapshot.powerLevel, surgeFactor: surgeFactor)
        if step.rebirth {
            checkRivalRebirth()
        } else if let revealed = step.revealed {
            defaults.set(step.form, forKey: RivalKeys.currentForm)
            defaults.set(step.formBasePL, forKey: RivalKeys.formStartPL)
            defaults.set(Date.now, forKey: RivalKeys.formStartDate)
            defaults.set(revealed, forKey: RivalKeys.formReveal)   // 2 or 3 -> reveal banner
            if step.form > defaults.integer(forKey: RivalKeys.highestSeenForm) {
                defaults.set(step.form, forKey: RivalKeys.highestSeenForm)
            }
            bumpRivalStateVersion()
        }
    }

    private func checkRivalRebirth() {
        guard let snapshot else { return }
        let rival = effectiveRival
        // Rebirth fires only when the FINAL (surged) form has been out-climbed.
        guard rival.form >= 3, snapshot.powerLevel > rival.pl else { return }
        let defaults = UserDefaults.standard
        // The user just BEAT form 3 — stamp the high-water mark before the new cycle
        // resets him to form 1, or the witness record would lose it.
        defaults.set(3, forKey: RivalKeys.highestSeenForm)
        // He returns ~10% above the user, rounded to a clean hundred, as a fresh Form 1;
        // growth stays live-adaptive (effectiveRivalGrowth), so the new cycle is winnable.
        let newStart = Int((Double(snapshot.powerLevel) * 1.10 / 100).rounded(.up)) * 100
        defaults.set(rivalCycle + 1, forKey: RivalKeys.cycle)
        defaults.set(1, forKey: RivalKeys.currentForm)
        defaults.set(newStart, forKey: RivalKeys.formStartPL)
        defaults.set(Date.now, forKey: RivalKeys.formStartDate)
        defaults.removeObject(forKey: RivalKeys.formReveal)   // rebirth has its own banner
        defaults.set(true, forKey: RivalKeys.announce)
        bumpRivalStateVersion()
    }

    // MARK: - Rival form reveal (S2 plays the transform, then acks)

    /// 2 or 3 when Vexeth has just transformed and the UI hasn't acknowledged the reveal
    /// yet; nil otherwise. Mirrors the engine step's `revealed`. (Mirrors the
    /// rivalRebirthAnnounce template.)
    public var pendingRivalFormReveal: Int? {
        _ = rivalStateVersion   // observation hook
        let value = UserDefaults.standard.integer(forKey: RivalKeys.formReveal)
        return (value == 2 || value == 3) ? value : nil
    }

    /// The UI has played the reveal — clear it so it won't fire again until the next form.
    public func acknowledgeRivalFormReveal() {
        UserDefaults.standard.removeObject(forKey: RivalKeys.formReveal)
        bumpRivalStateVersion()
    }

    /// A single crimson-voiced line keyed to the current gap state — deterministic
    /// (week-stable, never random flicker), terse, and NEVER guilt: an absent user is
    /// met with patience. Data-driven, picked from a per-state bank.
    public var rivalTaunt: String {
        _ = rivalStateVersion   // observation hook
        let eff = effectiveRival
        let userPL = snapshotPowerLevel
        let pace = trailingWeeklyPace
        let growth = effectiveRivalGrowth
        // Stable within a week, varied across weeks/forms/cycles — no per-render flicker.
        let weekOrdinal = Calendar.current.component(.weekOfYear, from: .now)
        let seed = abs(rivalCycle &* 31 &+ eff.form &+ weekOrdinal)

        let bank: [String]
        if rivalRebirthAnnounce {
            bank = ["Again. Higher.",
                    "You thought that was my ceiling? Cute.",
                    "The climb resets. I do not."]
        } else if pendingRivalFormReveal != nil {
            bank = ["This is not my final form.",
                    "You've forced my hand.",
                    "Deeper, then. Follow if you can."]
        } else if userPL > eff.pl {
            bank = ["You've forced my hand.",
                    "A lead. Enjoy it while it lasts."]
        } else if pace > growth {
            bank = ["Your pace climbs. I feel it.",
                    "You gain. I notice.",
                    "Closer. I do not slow for it."]
        } else {
            bank = ["The gap holds. For now.",
                    "Still the climb. Take your time.",
                    "I am here when you are ready."]
        }
        return bank[seed % bank.count]
    }

    /// The weekly race: your PL (from the trajectory) against Vexeth's scripted PL at each
    /// ISO week over the trailing `weeks`. bone = you, crimson = Vexeth. Empty if there
    /// are fewer than two weeks to plot.
    public func rivalRaceLines(weeks: Int) -> [(weekStart: Date, you: Int, rival: Int)] {
        let you = powerLevelWeeklyChanges(weeks: weeks)
        guard you.count >= 2, let snapshot else { return [] }
        let defaults = UserDefaults.standard
        let base = defaults.object(forKey: RivalKeys.formStartPL) != nil
            ? defaults.integer(forKey: RivalKeys.formStartPL)
            : ((config?.rival["startPL"] as? Int) ?? 0)
        let clockStart = (defaults.object(forKey: RivalKeys.formStartDate) as? Date)
            ?? snapshot.qualifyingDayStarts.first ?? you[0].weekStart
        let growth = effectiveRivalGrowth
        let cal = Self.isoWeekCalendar
        return you.map { week in
            let weekEnd = cal.date(byAdding: .weekOfYear, value: 1, to: week.weekStart) ?? week.weekStart
            let asOfWeek = min(weekEnd, .now)
            let w = ProgressionEngine.rivalEffectiveWeeks(
                qualifyingDayStarts: snapshot.qualifyingDayStarts,
                clockStart: clockStart, asOf: asOfWeek, calendar: cal, proRateCurrentWeek: false)
            let rivalPL = ProgressionEngine.rivalEffectivePL(base: base, weeklyGrowth: growth, weeks: w)
            return (weekStart: week.weekStart, you: week.endPL, rival: rivalPL)
        }
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

    /// The rival's CURRENT weekly growth — always capped near the user's own trailing
    /// pace so the race stays winnable (never outruns a consistent trainer, freezes on a
    /// plateau), and floored so he still creeps. Falls back to the scripted growth only
    /// while there's no pace trend yet (a brand-new user's opening menace).
    public var effectiveRivalGrowth: Int {
        let configGrowth = (config?.rival["weeklyGrowth"] as? Int) ?? 350
        return ProgressionEngine.rivalAdaptiveGrowth(
            configGrowth: configGrowth, trailingWeeklyPace: trailingWeeklyPace,
            floor: Self.rivalGrowthFloor, hasTrend: rivalHasTrend)
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

