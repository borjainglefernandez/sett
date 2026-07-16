import SwiftUI
import SettCore

// MARK: - Streak sheet (tap the flame — see the rules, the margin, the fire)

/// The streak, opened up: how it's counted for THIS user's schedule mode, this week's
/// progress against their real target, and the shield system that forgives a missed
/// week. The forgiveness rule is deliberately one sentence: every 4 on-target weeks
/// bank a shield (max 2); a missed week spends one instead of breaking the streak.
struct StreakSheet: View {
    let state: StreakEngine.StreakState
    let mode: ScheduleMode
    /// Short names of the scheduled weekdays (weekday mode only), e.g. ["MON","WED","FRI"].
    let scheduledDays: [String]
    /// The streak's consistency multiplier on the power level (1.0…1.5) — the reason
    /// the fire matters mechanically, not just emotionally. nil hides the row.
    var plMultiplier: Double? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flameScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    thisWeekCard
                    shieldsCard
                    ruleCard
                }
                .padding(16)
            }
            .dungeonBackground()
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Hero — the fire itself

    private var hero: some View {
        VStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34))
                .foregroundStyle(SettColor.heroCyan)
                .shadow(color: SettColor.heroCyan.opacity(0.6), radius: 8)
                .scaleEffect(flameScale)
                .background {
                    // The hearth behind the fire — embers thicken as the streak grows.
                    EmberHalo(intensity: min(1, 0.3 + Double(state.weeks) * 0.07))
                        .padding(-36)
                }
                .onAppear {
                    // A week just extended: one celebratory punch, then still.
                    guard state.extendedThisWeek, !reduceMotion else { return }
                    flameScale = 1.15
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { flameScale = 1 }
                    Haptics.success()
                }
            Text("\(state.weeks) WK")
                .font(.system(size: 40, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
            if state.extendedThisWeek {
                // A sanctioned gold pulse — the streak extending IS the reward moment.
                Text("STREAK EXTENDED THIS WEEK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.saiyanGold)
            } else if state.weeks > 0 {
                Text("TRAIN \(max(0, state.weeklyTarget - state.daysThisWeek)) MORE DAY\(state.weeklyTarget - state.daysThisWeek == 1 ? "" : "S") TO EXTEND")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(SettColor.ash)
            }
            if state.bestWeeks > state.weeks {
                Text("BEST \(state.bestWeeks) WK")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(SettColor.ash)
            }
            if let plMultiplier, plMultiplier > 1 {
                // The mechanical payoff: the streak multiplies the power level.
                Text("POWER LEVEL ×\(plMultiplier.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(SettColor.heroCyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SettColor.heroCyan.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibility)
    }

    // MARK: This week — progress vs the user's REAL target

    private var thisWeekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("THIS WEEK")
                Spacer()
                Text("\(state.daysThisWeek)/\(state.weeklyTarget) DAYS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(state.extendedThisWeek ? SettColor.saiyanGold : SettColor.bone)
            }
            HStack(spacing: 10) {
                ForEach(0..<state.weeklyTarget, id: \.self) { index in
                    let charged = index < state.daysThisWeek
                    ZStack {
                        if charged {
                            Circle().fill(SettColor.heroCyan.opacity(0.85))
                            Circle().strokeBorder(SettColor.heroCyan, lineWidth: 1.5)
                            SettSigil(size: 13, color: SettColor.etch)
                        } else {
                            Circle().fill(TimeChamber.void.opacity(0.35))
                            Circle().strokeBorder(SettColor.iron.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .shadow(color: charged ? SettColor.heroCyan.opacity(0.45) : .clear, radius: 3)
                }
                Spacer()
            }
            Text(modeCaption)
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudCard()
        .accessibilityElement(children: .combine)
    }

    private var modeCaption: String {
        let sessions = "\(state.weeklyTarget) session\(state.weeklyTarget == 1 ? "" : "s")"
        switch mode {
        case .weekday:
            if scheduledDays.isEmpty {
                return "Weekday mode — your target is your weekly goal: \(sessions)."
            }
            return "Weekday mode — \(sessions) a week across your scheduled days: \(scheduledDays.joined(separator: " · "))."
        case .rotation:
            return "Rotation mode — no fixed days; \(sessions) a week, whichever days suit you."
        }
    }

    // MARK: Shields — the margin for life

    private var shieldsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("SHIELDS")
                Spacer()
                Text("\(state.shields)/\(state.shieldCap)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(SettColor.bone)
            }
            HStack(spacing: 12) {
                ForEach(0..<state.shieldCap, id: \.self) { index in
                    Image(systemName: index < state.shields ? "shield.fill" : "shield")
                        .font(.system(size: 24))
                        .foregroundStyle(index < state.shields
                                         ? SettColor.heroCyan
                                         : SettColor.iron.opacity(0.6))
                        .shadow(color: index < state.shields ? SettColor.heroCyan.opacity(0.4) : .clear,
                                radius: 3)
                }
                Spacer()
                if state.weeksToNextShield > 0 {
                    Text("NEXT IN \(state.weeksToNextShield) WK")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                }
            }
            Text("A shield absorbs one missed week — vacation, illness, life — without breaking your streak.")
                .font(.footnote)
                .foregroundStyle(SettColor.ash)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: The rule, spelled out

    private var ruleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("HOW IT COUNTS")
            rule("flame.fill", "A week extends your streak when you train \(state.weeklyTarget) day\(state.weeklyTarget == 1 ? "" : "s").")
            rule("shield.fill", "Every 4 on-target weeks bank a shield (max \(state.shieldCap)).")
            rule("heart.fill", "Miss a week with a shield banked — it's spent, the fire keeps burning.")
            rule("bolt.fill", "Every streak week multiplies your power level, up to ×1.5 at 10 weeks.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudCard()
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 18)
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(SettColor.bone)
        }
    }

    private var heroAccessibility: String {
        var parts = ["Streak: \(state.weeks) weeks"]
        if state.extendedThisWeek { parts.append("extended this week") }
        if state.bestWeeks > state.weeks { parts.append("best \(state.bestWeeks) weeks") }
        return parts.joined(separator: ", ")
    }
}
