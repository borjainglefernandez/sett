import SwiftUI
import SwiftData
import UIKit
import SettCore

// MARK: - This Week card (the ONE weekly card — slots + counters + net, merged)

/// The single weekly card. Top half: seven forged-medallion slots, one per day
/// of the ISO week (Monday first) — each trained day pops a cyan sigil, today
/// wears a pulsing reticle. Hitting the weekly goal MATERIALIZES a gold Burst
/// button (fires the week-seal ceremony, marks the burst claimed for this ISO
/// week); a claimed week reads a quiet cyan `WEEK SEALED`. Bottom half (below a
/// divider, only when the week has work): the counters + net-vs-last-week strip
/// that used to be a second, always-adjacent card answering the same "how is my
/// week going?" question.
///
/// Week-sealed micro-beat: the moment the trained-day count first reaches the
/// target, a one-shot cyan sweep runs across the filled slots (once per ISO week,
/// persisted). The matching flame-flare on the Home streak chip lives in Home.
struct SevenSlotBurstRow: View {
    /// Trained days of the current ISO week: 0 = Monday … 6 = Sunday.
    let trainedDays: Set<Int>
    let goalTarget: Int
    /// Current streak (weeks) — the ceremony's "STREAK EXTENDED" hype line.
    let streakWeeks: Int

    @State private var isClaimed: Bool
    @State private var isShowingCeremony = false
    /// One-shot cyan sweep across the filled slots when the week first seals.
    @State private var sweeping = false
    @State private var sweepPhase: CGFloat = -0.5
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// One seal-sweep per ISO week — the celebratory sweep plays the moment the
    /// week seals and never again, even across a re-open of an already-sealed week.
    private static var sweptKey: String {
        let comps = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        return "sett.weekSwept.\(comps.yearForWeekOfYear ?? 0)-\(comps.weekOfYear ?? 0)"
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
                Eyebrow("THIS WEEK")
                Spacer()
                Text("\(trainedDays.count)/\(goalTarget)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettColor.ash)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week: \(trainedDays.count) of \(goalTarget) workouts")

            HStack(spacing: 0) {
                // Sunday-first display; day indices keep 0 = Monday … 6 = Sunday.
                // The enumerated position staggers the entrance pops left-to-right.
                ForEach(Array(TrainDays.sundayFirstOrder.enumerated()), id: \.element) { position, day in
                    VStack(spacing: 6) {
                        BurstSlot(isFilled: trainedDays.contains(day), isToday: day == todayIndex,
                                  cascadeDelay: Double(position) * 0.04)
                        Text(Self.dayLetters[day])
                            .font(.system(size: 10, weight: day == todayIndex ? .bold : .semibold, design: .monospaced))
                            .foregroundStyle(SettColor.ash)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // The one-shot cyan sweep rides over the filled slots when the week seals.
            .overlay { sealSweep }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(trainedDays.count) of 7 day slots filled")

            if isBurstReady {
                BurstReadyButton(action: fireBurst)
            } else if isClaimed {
                // The rest-of-the-week seal marker — cyan (ki), the chip's flame echoes it.
                Text("WEEK SEALED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.heroCyan)
                    .accessibilityLabel("Week sealed")
            }

            // Lower half of the SAME card: counters + net vs last week. Only when the
            // week has trained days — a zero week ends on seven empty rings, not zeros.
            if !trainedDays.isEmpty {
                NetGlanceStrip()
            }
        }
        .settCard()
        // The moment the trained-day count first reaches the target, run the seal
        // sweep (once per week). Only fires on a live transition — a fresh open of an
        // already-sealed week doesn't re-play it (onChange never fires on appear).
        .onChange(of: trainedDays.count) { oldCount, newCount in
            if oldCount < goalTarget && newCount >= goalTarget { runSealSweep() }
        }
        // claimKey reads the live ISO week, but isClaimed is seeded once at init.
        // Re-read it on foreground and at local midnight so the SEALED ✓ / burst
        // state follows the ISO-week rollover instead of freezing on the old week.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { isClaimed = UserDefaults.standard.bool(forKey: Self.claimKey) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            isClaimed = UserDefaults.standard.bool(forKey: Self.claimKey)
        }
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

    /// A cyan light-band that wipes left-to-right across the filled slots. Masked to
    /// the slot row via the overlay, additive so it reads as a charge, not a bar.
    @ViewBuilder
    private var sealSweep: some View {
        if sweeping {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, SettColor.heroCyan.opacity(0.6), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: sweepPhase * geo.size.width)
                    .blendMode(.plusLighter)
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Fire the seal sweep once per ISO week. Reduce Motion still marks the week swept
    /// and gives the haptic, but holds the slots still (no wipe).
    private func runSealSweep() {
        guard !UserDefaults.standard.bool(forKey: Self.sweptKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.sweptKey)
        Haptics.success()
        guard !reduceMotion else { return }
        sweeping = true
        sweepPhase = -0.5
        withAnimation(.easeInOut(duration: 0.7)) { sweepPhase = 1.0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            sweeping = false
            sweepPhase = -0.5
        }
    }
}

// MARK: - One forged-medallion slot

/// A day slot in the set-badge language the exercise cards taught: a trained day is a
/// CHARGED cyan disc (a logged set), today is the targeting reticle (the active row),
/// an untrained day is a solid ghost ring (a planned set). Days are the week's reps.
private struct BurstSlot: View {
    let isFilled: Bool
    let isToday: Bool
    /// Entrance stagger (display position × 40 ms) — the week pops in left-to-right.
    var cascadeDelay: Double = 0

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
            if isFilled { popSigil(after: cascadeDelay) }
            if isToday, !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    ringPulse = true
                }
            }
        }
        .onChange(of: isFilled) { _, nowFilled in
            // A slot earned mid-session pops instantly — the cascade is entrance-only.
            if nowFilled {
                popSigil()
                Haptics.light()
            }
        }
        .accessibilityHidden(true)
    }

    private func popSigil(after delay: Double = 0) {
        guard !reduceMotion else {
            sigilScale = 1
            return
        }
        sigilScale = 0.2
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(delay)) { sigilScale = 1 }
    }
}

// MARK: - The materializing Burst button

/// `WEEKLY BURST READY` — assembles from light via the shared System Voice
/// entrance (`materialize`). Gold here is a sanctioned reward pulse.
private struct BurstReadyButton: View {
    let action: () -> Void

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
        .materialize()
        .accessibilityLabel("Weekly burst ready")
        .accessibilityHint("Opens the week seal ceremony")
    }
}

// MARK: - Burst ceremony (the weekly recap)

/// The week-seal ceremony, staged like a cutscene: a beat of dark, then the
/// tonnage ROLLS in as a sacred number (odometer + gold burst + level-up haptic
/// on the landing), then stats → streak → seal reveal in three staggered steps.
/// Reduce Motion: everything is set directly, no stagger, no burst.
struct BurstCeremonyView: View {
    /// Streak length INCLUDING this week — the "STREAK EXTENDED" hype line.
    var streakWeeks: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The odometer only rolls on CHANGE, so the numeral holds 0 through the
    /// curtain beat, then rolls to the real tonnage.
    @State private var displayedTonnage = 0
    @State private var burstFired = false
    /// 0 = numeral only, 1 = +stats, 2 = +streak line, 3 = +seal.
    @State private var revealStage = 0
    @State private var ceremony: Task<Void, Never>?

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
                if burstFired {
                    // One-shot gold burst meeting the odometer's landing.
                    AuraBurstView(gold: true)
                        .frame(width: 220, height: 220)
                }
                VStack(spacing: 8) {
                    SacredNumberView(value: displayedTonnage)
                    Text("\(unitSymbol) MOVED THIS WEEK")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(SettColor.ash)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tonnageDisplay) \(services.settings.unit.symbol) moved this week")

            if revealStage >= 1 {
                statRows
                    .transition(revealTransition)
            }

            if streakWeeks > 1, revealStage >= 2 {
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
                .transition(revealTransition)
                .accessibilityLabel("Streak extended to \(streakWeeks) weeks")
            }

            if revealStage >= 3 {
                SystemMessageView(title: streakWeeks > 1 ? "THE FIRE GROWS" : "WEEK SEALED")
                    .transition(revealTransition)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(SettColor.etch)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Aura.cyan, in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dungeonBackground()
        .onAppear { runCeremony() }
        .onDisappear { ceremony?.cancel() }
    }

    private var revealTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .bottom))
    }

    /// The beat sheet: curtain (~0.45 s) → the tonnage rolls → burst + haptic on
    /// the landing (~0.5 s of odometer) → stats, streak, seal 0.25 s apart.
    private func runCeremony() {
        guard !reduceMotion else {
            displayedTonnage = tonnageDisplay
            revealStage = 3
            Haptics.levelUp()
            return
        }
        ceremony?.cancel()
        ceremony = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation { displayedTonnage = tonnageDisplay }
            // The odometer takes ~0.5 s to land (5 steps + hit-stops) — the burst
            // and level-up haptic meet it there, not at the start of the roll.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            burstFired = true
            Haptics.levelUp()
            for stage in 1...3 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { revealStage = stage }
            }
        }
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
