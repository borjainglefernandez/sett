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
}


/// Progression-redesign switches (audit: "one spine number"). Legacy per-character
/// XP/levels stay computed by the engine until Phase 3 deletes them; this flag only
/// controls whether any UI still renders them.
enum ProgressionUIFlags {
    static let legacyXPVisible = false
}
