import SwiftUI
import SwiftData
import SettCore

// MARK: - 7-Slot Burst Row (Dark Chamber v3 — replaces the weekly goal ring)

/// Seven forged-medallion slots, one per day of the ISO week (Monday first).
/// Each trained day pops a small cyan sigil into its slot; today's slot wears a
/// subtle pulsing ring. Hitting the weekly goal MATERIALIZES a gold Burst
/// button that didn't exist before — firing it opens the week-seal ceremony
/// and marks the burst claimed for this ISO week. Claimed weeks show a quiet
/// mono `SEALED ✓` caption instead.
struct SevenSlotBurstRow: View {
    /// Trained days of the current ISO week: 0 = Monday … 6 = Sunday.
    let trainedDays: Set<Int>
    let goalTarget: Int
    /// Current streak (weeks) — the ceremony's "STREAK EXTENDED" hype line.
    let streakWeeks: Int

    @State private var isClaimed: Bool
    @State private var isShowingCeremony = false

    init(trainedDays: Set<Int>, goalTarget: Int, streakWeeks: Int = 0) {
        self.trainedDays = trainedDays
        self.goalTarget = goalTarget
        self.streakWeeks = streakWeeks
        _isClaimed = State(initialValue: UserDefaults.standard.bool(forKey: Self.claimKey))
    }

    /// Streaks and weekly goals use ISO weeks (Monday start), matching the engines.
    static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    /// One claim per ISO week: `sett.burstClaimed.<isoYear>-<isoWeek>`.
    private static var claimKey: String {
        let comps = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        return "sett.burstClaimed.\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
    }

    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    /// Today as 0 = Monday … 6 = Sunday.
    private var todayIndex: Int {
        let weekday = Self.isoCalendar.component(.weekday, from: .now) // 1 = Sunday … 7 = Saturday
        return (weekday + 5) % 7
    }

    private var isBurstReady: Bool {
        trainedDays.count >= goalTarget && !isClaimed
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("THIS WEEK")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(SettColor.ash)
                Spacer()
                Text("\(trainedDays.count)/\(goalTarget)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettColor.ash)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week: \(trainedDays.count) of \(goalTarget) workouts")

            HStack(spacing: 0) {
                // Sunday-first display; day indices keep 0 = Monday … 6 = Sunday.
                ForEach(TrainDays.sundayFirstOrder, id: \.self) { day in
                    VStack(spacing: 6) {
                        BurstSlot(isFilled: trainedDays.contains(day), isToday: day == todayIndex)
                        Text(Self.dayLetters[day])
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(day == todayIndex ? SettColor.ash : SettColor.iron)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(trainedDays.count) of 7 day slots filled")

            if isBurstReady {
                BurstReadyButton(action: fireBurst)
            } else if isClaimed {
                Text("SEALED ✓")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.ash)
                    .accessibilityLabel("Weekly burst sealed")
            }
        }
        .settCard()
        .sheet(isPresented: $isShowingCeremony) {
            BurstCeremonyView(streakWeeks: streakWeeks)
        }
    }

    /// Collect-7 payoff: claim the week, then run the ceremony.
    private func fireBurst() {
        UserDefaults.standard.set(true, forKey: Self.claimKey)
        isClaimed = true
        isShowingCeremony = true
    }
}

// MARK: - One forged-medallion slot

/// A day slot in the set-badge language the exercise cards taught: a trained day is a
/// CHARGED cyan disc (a logged set), today is the targeting reticle (the active row),
/// an untrained day is a solid ghost ring (a planned set). Days are the week's reps.
private struct BurstSlot: View {
    let isFilled: Bool
    let isToday: Bool

    @State private var sigilScale: CGFloat = 1
    @State private var ringPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isFilled {
                // Charged — SetIndexBadge's "earned" paint: solid disc, crisp rim,
                // the sigil punched out dark, a layout-free bloom below.
                Circle().fill(SettColor.heroCyan.opacity(0.85))
                Circle().strokeBorder(SettColor.heroCyan, lineWidth: 1.5)
                SettSigil(size: 17, color: SettColor.etch)
                    .scaleEffect(sigilScale)
            } else {
                // Ghost — faint mass + solid iron ring, the "unearned" paint.
                Circle().fill(TimeChamber.void.opacity(0.35))
                Circle().strokeBorder(SettColor.iron.opacity(0.5), lineWidth: 1.5)
            }
            if isToday {
                ReticleTicks(arm: 4)
                    .stroke(SettColor.heroCyan.opacity(0.9), lineWidth: 1)
            }
        }
        .frame(width: 36, height: 36)
        .compositingGroup()
        .shadow(color: isFilled ? SettColor.heroCyan.opacity(0.45) : .clear, radius: 3)
        .overlay {
            if isToday {
                Circle()
                    .strokeBorder(
                        SettColor.heroCyan.opacity(reduceMotion ? 0.45 : (ringPulse ? 0.6 : 0.2)),
                        lineWidth: 1.5
                    )
                    .padding(-3.5)
            }
        }
        .onAppear {
            if isFilled { popSigil() }
            if isToday, !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    ringPulse = true
                }
            }
        }
        .onChange(of: isFilled) { _, nowFilled in
            if nowFilled { popSigil() }
        }
        .accessibilityHidden(true)
    }

    private func popSigil() {
        guard !reduceMotion else {
            sigilScale = 1
            return
        }
        sigilScale = 0.2
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { sigilScale = 1 }
    }
}

// MARK: - The materializing Burst button

/// `WEEKLY BURST READY` — assembles from light like the System Voice (opacity,
/// blur, and scale over 0.3 s; plain fade under Reduce Motion). Gold here is a
/// sanctioned reward pulse.
private struct BurstReadyButton: View {
    let action: () -> Void

    @State private var materialized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text("WEEKLY BURST READY")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(SettColor.etch)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Aura.gold, in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(materialized ? 1 : 0)
        .blur(radius: materialized || reduceMotion ? 0 : 6)
        .scaleEffect(materialized || reduceMotion ? 1 : 1.04)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { materialized = true }
        }
        .accessibilityLabel("Weekly burst ready")
        .accessibilityHint("Opens the week seal ceremony")
    }
}

// MARK: - Burst ceremony (the weekly recap)

/// The week-seal ceremony: this week's tonnage rolls in as a sacred number
/// over an ember halo, mono stat rows beneath, `WEEK SEALED` in the system
/// voice. Level-up haptic on entry.
struct BurstCeremonyView: View {
    /// Streak length INCLUDING this week — the "STREAK EXTENDED" hype line.
    var streakWeeks: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @Query private var weekWorkouts: [Workout]
    @Query private var weekAwards: [BadgeAward]

    init(streakWeeks: Int = 0) {
        self.streakWeeks = streakWeeks
        let week = SevenSlotBurstRow.isoCalendar.dateInterval(of: .weekOfYear, for: .now)
        let start = week?.start ?? .now
        let end = week?.end ?? .now

        let workoutFilter = #Predicate<Workout> {
            $0.endedAt != nil && $0.deletedAt == nil
                && $0.startedAt >= start && $0.startedAt < end
        }
        _weekWorkouts = Query(filter: workoutFilter)

        // PRs this week ≈ badge awards earned inside the ISO week.
        let awardFilter = #Predicate<BadgeAward> {
            $0.deletedAt == nil && $0.earnedAt >= start && $0.earnedAt < end
        }
        _weekAwards = Query(filter: awardFilter)
    }

    /// Working (non-warmup) sets across the week's finished workouts — the
    /// same eligibility rule the engines use for volume.
    private var workingSets: [SetEntry] {
        weekWorkouts.flatMap { workout in
            workout.orderedExercises.flatMap { exercise in
                exercise.orderedSets.filter { !$0.isWarmup }
            }
        }
    }

    /// Week volume (weight × reps) in the user's display unit — kg users saw an LB
    /// number 2.2× too large on their most celebratory screen.
    private var unitSymbol: String { services.settings.unit.symbol.uppercased() }
    private var tonnageDisplay: Int {
        let grams = workingSets.reduce(0) { $0 + $1.weightGrams * $1.reps }
        return Int((Double(grams) / services.settings.unit.gramsPerUnit).rounded())
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                EmberHalo(intensity: 0.9)
                    .frame(width: 280, height: 190)
                VStack(spacing: 8) {
                    SacredNumberView(value: tonnageDisplay)
                    Text("\(unitSymbol) MOVED THIS WEEK")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(SettColor.ash)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tonnageDisplay) \(services.settings.unit.symbol) moved this week")

            statRows

            if streakWeeks > 1 {
                // The hype line: extending the fire is the headline, not a footnote.
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(SettColor.saiyanGold)
                    Text("STREAK EXTENDED — \(streakWeeks) WEEKS")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.saiyanGold)
                }
                .shadow(color: SettColor.saiyanGold.opacity(0.5), radius: 6)
                .accessibilityLabel("Streak extended to \(streakWeeks) weeks")
            }

            SystemMessageView(title: streakWeeks > 1 ? "THE FIRE GROWS" : "WEEK SEALED")

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Aura.cyan, in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dungeonBackground()
        .onAppear { Haptics.levelUp() }
    }

    private var statRows: some View {
        VStack(spacing: 10) {
            statRow("WORKOUTS", "\(weekWorkouts.count)")
            statRow("SETS", "\(workingSets.count)")
            statRow("TONNAGE", "\(tonnageDisplay) \(unitSymbol)")
            statRow("PRS THIS WEEK", "\(weekAwards.count)")
        }
        .settCard()
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(SettColor.ash)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(SettColor.bone)
        }
        .accessibilityElement(children: .combine)
    }
}
