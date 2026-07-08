import SwiftUI
import SettCore

/// The XP transparency sheet: a scrollable, config-driven explainer of how XP is
/// earned and how it differs from Power Level. Every number shown is read from
/// progression_config.json via ProgressionStore, so the prose can never drift
/// from the engine — only structure and flavor text live here. Reached from the
/// Power tab's info button and the Power Scan's "How XP works" footnote.
struct HowPowerWorksView: View {
    @Environment(ProgressionStore.self) private var progression
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    workoutXPCard
                    whatCountsCard
                    restDayCard
                    badgesCard
                    goalsCard
                    powerLevelCard
                }
                .padding(16)
            }
            .dungeonBackground()
            .navigationTitle("How Power Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Config lookups (fallbacks mirror the shipped progression_config.json)

    private var config: ProgressionConfig? { progression.config }

    private func xpInt(_ key: String, _ fallback: Int) -> Int {
        config?.xp[key] as? Int ?? fallback
    }

    private func xpPercent(_ key: String, _ fallback: Double) -> Int {
        Int(((config?.xp[key] as? Double ?? fallback) * 100).rounded())
    }

    private func goalXP(_ key: String, _ fallback: Int) -> Int {
        (config?.xp["goalCompletionXP"] as? [String: Int])?[key] ?? fallback
    }

    private func badgeXP(_ rarity: BadgeRarity) -> Int {
        if let config, config.badgeXP(rarity: rarity) > 0 {
            return config.badgeXP(rarity: rarity)
        }
        switch rarity {
        case .bronze: return 100
        case .silver: return 250
        case .gold: return 600
        case .legendary: return 1500
        }
    }

    // MARK: Sections

    private var workoutXPCard: some View {
        let setCap = xpInt("perEffectiveSetCap", 60)
        let prCap = xpInt("verifiedPRCapPerWorkout", 3)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Workout XP", systemImage: "bolt.fill")
                .font(.headline)
            valueRow("Finish a qualifying workout", "+\(xpInt("workoutBase", 50)) XP")
            valueRow("Each effective set (up to +\(setCap))", "+\(xpInt("perEffectiveSet", 2)) XP")
            valueRow("Beat your last session (positive net)", "+\(xpInt("positiveNetBonus", 25)) XP")
            valueRow("Each verified PR (max \(prCap))", "+\(xpInt("perVerifiedPR", 10)) XP")
            footnote("""
                Workout XP levels Vego, the Ember Prince. The rest of the roster earns XP \
                from their own domains — tonnage, streaks, goals, sleep, variety, comebacks.
                """)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var whatCountsCard: some View {
        let effective = config?.effectiveSet
        let qualifying = config?.qualifyingWorkout
        let minReps = effective?.minReps ?? 1
        let maxReps = effective?.maxReps ?? 30
        let minFraction = Int(((effective?.minFractionOfBestE1RM ?? 0.4) * 100).rounded())
        let perExercise = effective?.maxSetsPerExercisePerWorkout ?? 6
        let perWorkout = effective?.maxSetsPerWorkout ?? 30
        let minSets = qualifying?.minEffectiveSets ?? 3
        let minMinutes = qualifying?.minDurationMinutes ?? 10
        return VStack(alignment: .leading, spacing: 10) {
            Label("What Counts", systemImage: "checkmark.seal")
                .font(.headline)
            bullet("An effective set lands between \(minReps) and \(maxReps) reps.")
            bullet("""
                Once a lift has history, a set must reach at least \(minFraction)% \
                of your best estimated one-rep max.
                """)
            bullet("The first \(perExercise) sets per exercise count, up to \(perWorkout) per workout.")
            bullet("A qualifying workout has \(minSets)+ effective sets and runs at least \(minMinutes) minutes.")
            bullet("Only your first qualifying workout of the day earns full XP.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var restDayCard: some View {
        let restedPercent = Int((((config?.xp["restedBonusMultiplier"] as? Double ?? 1.25) - 1.0) * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            Label("Rest-Day Respect", systemImage: "moon.zzz.fill")
                .font(.headline)
            valueRow("2nd workout in a day", "\(xpPercent("secondWorkoutSameDayFraction", 0.25))% XP")
            valueRow("3rd+ workout in a day", "\(xpPercent("thirdWorkoutSameDayFraction", 0.0))% XP")
            valueRow("XP days per rolling 7", "max \(xpInt("maxXPDaysPerRolling7", 6))")
            valueRow("Daily workout XP cap", "\(xpInt("dailyWorkoutXPCap", 300)) XP")
            valueRow("Rested bonus", "+\(restedPercent)% workout XP")
            footnote("""
                +\(restedPercent)% workout XP the day after a true rest day — recovery is a resource. \
                Grinding all seven days doesn't out-earn training smart. Rest is part of the program.
                """)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var badgesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Badges", systemImage: "medal.fill")
                .font(.headline)
            ForEach(BadgeRarity.allCases, id: \.self) { rarity in
                valueRow(rarity.rawValue.capitalized, "+\(badgeXP(rarity)) XP")
            }
            footnote("Badge XP goes to the character who owns the badge — the Badge Case shows who claims what.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Goals", systemImage: "target")
                .font(.headline)
            valueRow("Weekly frequency goal, each week hit", "+\(goalXP("frequency_week", 40)) XP")
            valueRow("Frequency goal finished", "+\(goalXP("frequency_finish", 100)) XP")
            valueRow("PR target reached", "+\(goalXP("pr_target", 150)) XP")
            valueRow("Volume target reached", "+\(goalXP("volume_target", 100)) XP")
            footnote("""
                Every goal completion also echoes +\(xpInt("goalTorrenEcho", 25)) XP \
                to Torren Vex, the Stern Mentor.
                """)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    private var powerLevelCard: some View {
        let power = config?.powerLevel
        let strengthWeight = Int(power?.strengthWeight ?? 4)
        let volumeWeight = Int(power?.volumeWeight ?? 8)
        let strengthDays = power?.strengthWindowDays ?? 90
        let volumeDays = power?.volumeWindowDays ?? 28
        let weeklyPercent = Int(((power?.consistencyPerWeek ?? 0.05) * 100).rounded())
        let maxWeeks = power?.consistencyMaxWeeks ?? 10
        return VStack(alignment: .leading, spacing: 10) {
            Label("Power Level ≠ XP", systemImage: "speedometer")
                .font(.headline)
            Text("PL = (\(strengthWeight) × Strength + \(volumeWeight) × √Volume) × Consistency")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            bullet("""
                Strength reads your best lifts from the last \(strengthDays) days; \
                volume reads the last \(volumeDays).
                """)
            bullet("Consistency multiplies the total — +\(weeklyPercent)% per consistent week, up to \(maxWeeks) weeks.")
            bullet("""
                Power Level is recomputed from your training data on every scan, so it can dip \
                when you ease off. XP never goes down — it accumulates and levels each character \
                toward their next transformation.
                """)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: Row helpers

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SettColor.saiyanGold)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }
}
