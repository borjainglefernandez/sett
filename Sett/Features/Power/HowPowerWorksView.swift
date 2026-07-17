import SwiftUI
import SettCore

/// The Scouter Manual: how the ONE number works. Post-collapse there is a single
/// spine — Power Level — with exactly three levers (strength, volume, streak), an
/// endless Forms ladder above it, and Vexeth pacing the race. Every number shown is
/// read from progression_config.json via ProgressionStore, so the prose can never
/// drift from the engine — only structure and flavor text live here. Reached from
/// the Power tab's info button.
struct HowPowerWorksView: View {
    @Environment(ProgressionStore.self) private var progression
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    powerLevelCard
                    whatCountsCard
                    formsCard
                    surgeCard
                    rivalCard
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

    private var config: ProgressionConfig? { progression.config }

    // MARK: The spine — PL and its three levers

    private var powerLevelCard: some View {
        let pl = config?.powerLevel
        let strengthDays = pl?.strengthWindowDays ?? 90
        let volumeDays = pl?.volumeWindowDays ?? 28
        let weeklyPercent = Int(((pl?.consistencyPerWeek ?? 0.05) * 100).rounded())
        let maxWeeks = pl?.consistencyMaxWeeks ?? 10
        return VStack(alignment: .leading, spacing: 10) {
            Label("The one number", systemImage: "bolt.fill")
                .font(.headline)
            bullet("""
                Three things move your power level: how strong you are, how much \
                you've been lifting, and how often you show up. Nothing else.
                """)
            bullet("Strength — your best verified lift in each muscle group over the last \(strengthDays) days.")
            bullet("Volume — how much you've lifted over the last \(volumeDays) days. Returns taper off, so twice the work isn't twice the power.")
            bullet("Streak — each week you stay consistent adds \(weeklyPercent)% to the total, up to \(maxWeeks) weeks (\(String(format: "×%.1f", 1 + Double(weeklyPercent) / 100 * Double(maxWeeks)))).")
            footnote("""
                All three windows keep rolling, so the number reflects recent \
                training. Take a long break and it slips; come back and it builds \
                again fast.
                """)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: What counts (anti-cheese, unchanged rules)

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
            Label("What counts", systemImage: "checkmark.seal")
                .font(.headline)
            bullet("A set counts when it's between \(minReps) and \(maxReps) reps.")
            bullet("""
                Each set is scored by its estimated one-rep max. Rep credit stops \
                at \(ProgressEngine.e1rmRepCap), since a 20-rep burnout set says \
                little about your max — but every rep still adds to your volume.
                """)
            bullet("""
                Once a lift has some history, a set has to reach at least \
                \(minFraction)% of your best estimated one-rep max to count.
                """)
            bullet("The first \(perExercise) sets of an exercise count, up to \(perWorkout) in a workout.")
            bullet("A workout qualifies once it has \(minSets) or more counting sets and runs at least \(minMinutes) minutes.")
            bullet("A surprise personal best stays provisional until a later session backs it up.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: The Forms ladder (endless)

    private var formsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Transformation forms", systemImage: "flame.fill")
                .font(.headline)
            ForEach(Array(UserForm.namedThresholds.dropFirst()), id: \.floor) { entry in
                valueRow(entry.title, "\(entry.floor.formatted()) PL")
            }
            valueRow("ZENITH II, III, …", "every \(UserForm.zenithStep.formatted()) PL after")
            footnote("The ladder has no top. There's always another form ahead.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: The surge (rest-day respect, post-XP)

    private var surgeCard: some View {
        let multiplier = config?.powerLevel.restedSurgeMultiplier ?? 1.25
        return VStack(alignment: .leading, spacing: 10) {
            Label("Rest days count too", systemImage: "moon.zzz.fill")
                .font(.headline)
            bullet("""
                Take a full rest day and your next qualifying session gets a surge — \
                its volume counts ×\(multiplier.formatted()) in the scanner window.
                """)
            bullet("You'll see it on the post-workout summary as a rested bonus.")
            bullet("Resting never breaks your weekly streak — only a missed session can, and your shields cover those.")
            footnote("Recovery is part of the work.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: The rival (endless race)

    private var rivalCard: some View {
        let growth = (config?.rival["weeklyGrowth"] as? Int) ?? 350
        return VStack(alignment: .leading, spacing: 10) {
            Label("Emperor Vexeth", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(SettColor.villainCrimson)
            bullet("Vexeth gains about \(growth) PL a week and reveals stronger forms as you close in.")
            bullet("Beat his final form and he's reborn above you — how far ahead depends on how fast you've been moving lately.")
            footnote("There's no finish line. The race just keeps going.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: Row helpers

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.bone)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.heroCyan)
        }
        .accessibilityElement(children: .combine)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·")
                .font(.headline)
                .foregroundStyle(SettColor.heroCyan)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SettColor.bone)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(SettColor.ash)
    }
}
