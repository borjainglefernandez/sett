import Foundation
import SwiftData

/// SwiftData bridge for the pure ProgressionEngine: extracts value samples,
/// computes the derived snapshot, reconciles `BadgeAward` rows (insert newly
/// earned, soft-delete revoked), refreshes the `SaiyanState` display cache,
/// and saves. Derived state is never source of truth — every call recomputes
/// everything from raw data, so the operation is idempotent.
@MainActor
public enum ProgressionReconciler {

    @discardableResult
    public static func reconcile(context: ModelContext, config: ProgressionConfig) throws -> ProgressionSnapshot {
        let now = Date.now
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        let workouts = SampleExtractor.workoutSamples(context: context)
        let state = context.saiyanState()

        let input = ProgressionInput(
            sets: SampleExtractor.setSamples(context: context),
            workouts: workouts,
            sleep: SampleExtractor.sleepSamples(context: context),
            goals: SampleExtractor.goalSamples(context: context),
            previousPeakPL: state.allTimePeakPL,
            firstWorkoutDate: workouts.map(\.startedAt).min()
        )
        let snapshot = ProgressionEngine.compute(input: input, config: config,
                                                 calendar: calendar, asOf: now)

        try reconcileBadgeAwards(context: context, snapshot: snapshot, now: now)

        // SaiyanState display cache.
        state.powerLevel = snapshot.powerLevel
        state.allTimePeakPL = snapshot.allTimePeakPL
        // Cast collapse: per-character tiers/XP are gone — the avatar's frame now
        // follows the USER's transformation form (a pure function of PL). The
        // legacy XP JSON cache is cleared but the column stays for sync stability.
        let formIndex = UserForm.form(forPL: snapshot.powerLevel).index
        state.transformationTier = TransformationTier(rawValue: min(formIndex, 4)) ?? .base
        state.characterXPJSON = "{}"
        state.updatedAt = now
        state.needsPush = true

        try context.save()
        return snapshot
    }

    // MARK: - Badge ledger reconciliation

    private static func reconcileBadgeAwards(context: ModelContext,
                                             snapshot: ProgressionSnapshot, now: Date) throws {
        let awards = try context.fetch(FetchDescriptor<BadgeAward>())
        let live = awards.filter { $0.deletedAt == nil }
        var liveByKey: [String: BadgeAward] = [:]
        for award in live where liveByKey[award.badgeKey] == nil {
            liveByKey[award.badgeKey] = award
        }
        var grantsByKey: [String: BadgeGrant] = [:]
        for grant in snapshot.badges where grantsByKey[grant.key] == nil {
            grantsByKey[grant.key] = grant
        }

        // Insert newly earned badges.
        for grant in snapshot.badges where liveByKey[grant.key] == nil {
            let award = BadgeAward(badgeKey: grant.key, earnedAt: grant.earnedAt,
                                   workoutID: grant.workoutID, exerciseID: grant.exerciseID,
                                   valueSnapshot: grant.valueSnapshot, now: now)
            context.insert(award)
        }

        // Soft-delete revoked badges (their evidence was edited or deleted).
        for award in live where grantsByKey[award.badgeKey] == nil {
            award.deletedAt = now
            award.updatedAt = now
            award.needsPush = true
        }

        // Refresh drifted grant fields on rows that stay earned (edits can move
        // the earliest satisfying moment).
        for award in live {
            guard let grant = grantsByKey[award.badgeKey] else { continue }
            if award.earnedAt != grant.earnedAt
                || award.valueSnapshot != grant.valueSnapshot
                || award.workoutID != grant.workoutID
                || award.exerciseID != grant.exerciseID {
                award.earnedAt = grant.earnedAt
                award.valueSnapshot = grant.valueSnapshot
                award.workoutID = grant.workoutID
                award.exerciseID = grant.exerciseID
                award.updatedAt = now
                award.needsPush = true
            }
        }
    }
}
