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
            Label("The One Number", systemImage: "bolt.fill")
                .font(.headline)
            bullet("""
                Your Power Level has exactly three levers — STRENGTH, VOLUME, and \
                your STREAK. Nothing else moves it.
                """)
            bullet("STRENGTH: your best verified lift per muscle group over the last \(strengthDays) days.")
            bullet("VOLUME: the work you've moved over the last \(volumeDays) days (diminishing returns — double volume doesn't double power).")
            bullet("STREAK: each consistent week multiplies the total by +\(weeklyPercent)%, up to \(maxWeeks) weeks (\(String(format: "×%.1f", 1 + Double(weeklyPercent) / 100 * Double(maxWeeks)))).")
            footnote("""
                The windows roll, so power must be MAINTAINED — a long break lets it \
                fade, and coming back rebuilds it fast.
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
            Label("What Counts", systemImage: "checkmark.seal")
                .font(.headline)
            bullet("An effective set lands between \(minReps) and \(maxReps) reps.")
            bullet("""
                Once a lift has history, a set must reach at least \(minFraction)% \
                of your best estimated one-rep max.
                """)
            bullet("The first \(perExercise) sets per exercise count, up to \(perWorkout) per workout.")
            bullet("A qualifying workout has \(minSets)+ effective sets and runs at least \(minMinutes) minutes.")
            bullet("A surprise PR is provisional until a later session confirms it — no fat-finger power.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: The Forms ladder (endless)

    private var formsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Transformation Forms", systemImage: "flame.fill")
                .font(.headline)
            ForEach(Array(UserForm.namedThresholds.dropFirst()), id: \.floor) { entry in
                valueRow(entry.title, "\(entry.floor.formatted()) PL")
            }
            valueRow("ZENITH II, III, …", "every \(UserForm.zenithStep.formatted()) PL after")
            footnote("The ladder never ends — there is always a next form.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settCard()
    }

    // MARK: The surge (rest-day respect, post-XP)

    private var surgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Rest-Day Respect", systemImage: "moon.zzz.fill")
                .font(.headline)
            bullet("A full rest day arms the SURGE — you return sharper, and the scanner knows it.")
            bullet("Rest can't break your streak week: only missed sessions can, and shields absorb even those.")
            footnote("Recovery is training. The chamber counts it.")
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
            bullet("Vexeth climbs ~\(growth) PL a week and reveals stronger forms as you close in.")
            bullet("Beat his final form and he REBIRTHS above you — faster or slower depending on YOUR recent pace.")
            footnote("The race has no finish line. That's the point.")
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
