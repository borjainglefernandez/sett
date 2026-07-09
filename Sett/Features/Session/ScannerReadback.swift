import SwiftUI
import SettCore

// MARK: - Log outcome classification (item 5)

/// How a just-logged set scored against its reference at the same slot. The verdict
/// is driven by the COMBINED e1RM delta (which prices the weight↔reps trade), not by
/// weight or reps alone — so dropping load but adding enough reps still reads as a
/// `.beat`. `.personalBest` is the crit (gold flash + PR haptic); `.beat` is a
/// gold-sweep win without the ceremony. `.casual` suppresses all of it.
enum LogOutcome {
    case personalBest  // crit — this set's e1RM beats the exercise's all-time best
    case beat          // e1RM up vs the reference set (not an all-time PR)
    case held          // e1RM within the phase's green "held" band — a WIN
    case heldUnderFire // realistic dip under the held band — supportive, never cold
    case stalled       // bulk only — flat, not enough when you're fed
    case dropped       // genuine decline (never returned in CUTTING)
    case baseline      // no reference set at this slot
    case warmup        // logged as a warm-up
    case casual        // workout is off the record

    /// crit: gold numeral flash + prSignature haptic + gold combat text.
    var isCrit: Bool { self == .personalBest }
    /// beat/crit: gold sweep + longer hold into REST + win burst. Others don't.
    var isGold: Bool { self == .personalBest || self == .beat }
    /// A phase-neutral "you held the line" success (green), vs a defended dip.
    var isHold: Bool { self == .held }

    /// Score by the RATIO of this set's e1RM to the reference set's, through the
    /// phase lens — so a cut celebrates retention and never lights the cold aura.
    static func classify(readback: SetReadback, phase: TrainingPhase,
                         isWarmup: Bool, isCasual: Bool) -> LogOutcome {
        if isCasual { return .casual }
        if isWarmup { return .warmup }
        if readback.isBaseline { return .baseline }
        if readback.isPersonalBest { return .personalBest }   // all-time PR always hyped
        guard let referenceE1RM = readback.referenceE1RMGrams, referenceE1RM > 0 else {
            let delta = readback.e1RMDeltaGrams ?? 0
            return delta > 0 ? .beat : (delta == 0 ? .held : .dropped)
        }
        let ratio = Double(readback.e1RMGrams) / Double(referenceE1RM)
        switch phase {
        case .cutting:
            // Defend the ceiling: −6%…+3% is the green win; a bigger dip is a
            // supportive hold, NEVER a cold drop.
            if ratio > 1.03 { return .beat }
            if ratio >= 0.94 { return .held }
            return .heldUnderFire
        case .bulking:
            // Break the ceiling: growth is the baseline; flat is a nudge to push.
            if ratio > 1.02 { return .beat }
            if ratio >= 0.98 { return .stalled }
            return .dropped
        case .maintaining:
            // Hold at altitude: the flat line itself is the target (±4%).
            if ratio > 1.04 { return .beat }
            if ratio >= 0.96 { return .held }
            if ratio >= 0.90 { return .heldUnderFire }
            return .dropped
        }
    }

    /// The transformation aura this outcome lights up (Time Chamber language).
    var auraTier: AuraTier {
        switch self {
        case .personalBest: .radiant
        case .beat: .ascended
        case .held, .baseline: .base
        case .heldUnderFire: .defended    // warm amber — held under fire, not cold
        case .stalled: .calm
        case .dropped: .fatigued
        case .warmup, .casual: .calm
        }
    }
}

// MARK: - Scanner message pools (item 5 — deterministic, no randomness APIs)

/// Terse Vego/scanner lines, selected by `loggedSetCount % pool.count` so the same
/// session state always yields the same line — recompute-safe, never `.random`.
enum ScannerMessages {
    private static let pools: [LogOutcome: [String]] = [
        .personalBest: [
            "NEW CEILING. Hmph.",
            "PEAK OUTPUT. The Scanner logs it.",
            "A record. Don't gloat.",
            "The highest reading yet. Adequate.",
        ],
        .beat: [
            "NET STRONGER.",
            "More output than last time. Adequate.",
            "The Scanner reads a bigger number.",
            "Traded well. Output up.",
        ],
        .held: [
            "HOLDING THE LINE.",
            "Matched output. Consistency is a weapon.",
            "RECORDED. RECOVER.",
        ],
        .heldUnderFire: [
            "HELD UNDER FIRE. The ceiling still stands.",
            "A dip is the toll for getting lean, not ground lost.",
            "Lighter tank, same threat. RETENTION LOGGED.",
            "Steel doesn't rust because the plates got lighter.",
        ],
        .stalled: [
            "FLAT. You're fed — go take more.",
            "Matched, not beaten. Add a rep. Feed the lift.",
            "The surplus wants growth. Answer it.",
        ],
        .dropped: [
            "OUTPUT DOWN. Recover, then answer.",
            "Below the last reading. The Scanner remembers the peak.",
            "Regroup. The next set answers.",
        ],
        .baseline: [
            "BASELINE SET. Now beat it.",
            "First reading. The Scanner has its mark.",
            "CALIBRATION SET.",
        ],
        .warmup: [
            "CALIBRATION SET.",
            "Warming the machine. Off the record.",
            "Warm-up logged. Save it for the work.",
        ],
        .casual: [
            "OFF THE RECORD.",
            "The Scanner looked away. The work still happened.",
            "No net today. Just iron.",
        ],
    ]

    static func line(for outcome: LogOutcome, loggedSetCount: Int) -> String {
        let pool = pools[outcome] ?? ["RECORDED. RECOVER."]
        let index = ((loggedSetCount % pool.count) + pool.count) % pool.count
        return pool[index]
    }
}

// MARK: - Payload staged on the store for the REST / in-place readback

/// Everything the readback block needs, assembled at LOG time and handed to the
/// store so the REST overlay (or the zero-rest in-place overlay) can render it.
struct LoggedReadback: Equatable {
    let weightGrams: Int
    let reps: Int
    let readback: SetReadback
    let outcome: LogOutcome
    let message: String
    var phase: TrainingPhase = .maintaining
}

// MARK: - Readback block (item 4 — SystemMessageView-style materialize)

/// "LOGGED · 160 lb × 10", delta chips vs the reference set, and the scanner line.
/// Materializes (opacity + blur + scale over 0.3 s) like `SystemMessageView`;
/// Reduce Motion plain-fades. Deltas suppressed for casual; crit/beat tint gold.
struct ReadbackBlock: View {
    let payload: LoggedReadback
    let unit: WeightUnit

    @State private var materialized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The scouter aura this reading lit up — same green→amber→red ramp as the lens.
    private var tier: AuraTier { payload.outcome.auraTier }

    /// This set's output as a power level — from canonical grams, so it's the SAME
    /// number for the same lift regardless of the user's display unit.
    private var powerLevel: Int {
        Int(Units.pounds(fromGrams: payload.readback.e1RMGrams).rounded())
    }

    private var powerDelta: Int? {
        guard let grams = payload.readback.e1RMDeltaGrams else { return nil }
        let value = Int(Units.pounds(fromGrams: grams).rounded())
        if value == 0 { return nil }
        // On a cut, never surface a negative PWR splash — retention is the story.
        if payload.phase == .cutting, value < 0 { return nil }
        return value
    }

    /// On a cut, show how much of last week's e1RM you retained, in place of the
    /// (suppressed) negative delta — "you held the ceiling" made concrete.
    private var retentionText: String? {
        guard payload.phase == .cutting,
              payload.outcome == .held || payload.outcome == .heldUnderFire,
              let reference = payload.readback.referenceE1RMGrams, reference > 0 else { return nil }
        let pct = Int((Double(payload.readback.e1RMGrams) / Double(reference) * 100).rounded())
        return "RETAINED \(pct)%"
    }

    var body: some View {
        VStack(spacing: 9) {
            if payload.outcome != .casual { powerLine }
            Text(loggedLine)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .kerning(1)
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            chipsRow
            if let netLine {
                Text(netLine)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(SettColor.ash)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(payload.message)
                .font(.system(.caption, design: .monospaced))
                .kerning(1)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(TimeChamber.void.opacity(0.85))
            shape.strokeBorder(tier.color.opacity(0.5), lineWidth: 1.5)
                .shadow(color: tier.color.opacity(0.45), radius: 9)
            CornerTicksShape(length: 6, inset: 6)
                .stroke(tier.color.opacity(0.55), lineWidth: 1)
        }
        .opacity(materialized ? 1 : 0)
        .blur(radius: materialized || reduceMotion ? 0 : 6)
        .scaleEffect(materialized || reduceMotion ? 1 : 1.04)
        .onAppear {
            if reduceMotion { materialized = true }
            else { withAnimation(.easeOut(duration: 0.3)) { materialized = true } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// The scouter's final reading: the power level in the aura hue, with the ΔPWR
    /// gained vs last time when this was a scored set.
    private var powerLine: some View {
        HStack(spacing: 6) {
            SettSigil(size: 15, color: tier.color)
            Text("PWR")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(tier.color.opacity(0.85))
            Text("\(powerLevel)")
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tier.color)
            if let delta = powerDelta {
                Text("\(delta > 0 ? "+" : "−")\(abs(delta))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? SettColor.positive : SettColor.negative)
            } else if let retentionText {
                Text(retentionText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(tier.color)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 3)
    }

    private var loggedLine: String {
        "LOGGED · \(WeightFormat.compactWithUnit(grams: payload.weightGrams, unit: unit)) × \(payload.reps)"
    }

    /// The scoring payoff: the single combined e1RM delta, plus the weight↔reps
    /// exchange rate when the two axes moved in opposite directions (the trade case).
    /// Shown only for scored sets (not baseline / warm-up / off-the-record).
    private var netLine: String? {
        switch payload.outcome {
        // Holds/stalls carry their own status chip (+ retention on a cut) — no
        // "NET −X" line, which would read as a penalty.
        case .baseline, .warmup, .casual, .held, .heldUnderFire, .stalled: return nil
        default: break
        }
        guard let net = payload.readback.e1RMDeltaGrams else { return nil }
        let sym = unit.symbol
        let base: String
        if net > 0 {
            base = "NET +\(WeightFormat.compact(grams: net, unit: unit)) \(sym) output"
        } else if net < 0 {
            base = "NET −\(WeightFormat.compact(grams: -net, unit: unit)) \(sym) output"
        } else {
            base = "NET even"
        }
        // Trade-off: weight and reps moved opposite ways — surface the exchange rate.
        let w = payload.readback.weightDeltaGrams ?? 0
        let r = payload.readback.repsDelta ?? 0
        if (w > 0 && r < 0) || (w < 0 && r > 0) {
            let perRep = ProgressEngine.oneRepEquivalentGrams(weightGrams: payload.weightGrams,
                                                              reps: payload.reps)
            return "\(base) · 1 rep ≈ \(WeightFormat.compact(grams: perRep, unit: unit)) \(sym) here"
        }
        return base
    }

    @ViewBuilder
    private var chipsRow: some View {
        switch payload.outcome {
        case .casual:
            EmptyView()
        case .warmup:
            chip(text: "WARM-UP", color: SettColor.ash)
        case .baseline:
            chip(text: "BASELINE SET", color: tier.color)
        case .held:
            chip(text: "CEILING HELD", color: SettColor.positive)
        case .heldUnderFire:
            chip(text: payload.phase == .cutting ? "CEILING DEFENDED" : "HELD UNDER FIRE",
                 color: tier.color)
        case .stalled:
            chip(text: "PUSH — NOT ENOUGH", color: tier.color)
        case .beat, .personalBest, .dropped:
            HStack(spacing: 8) {
                weightChip
                repsChip
            }
        }
    }

    private var weightChip: some View {
        let delta = payload.readback.weightDeltaGrams ?? 0
        let magnitude = WeightFormat.compact(grams: abs(delta), unit: unit)
        return deltaChip(label: "WEIGHT", delta: delta,
                         valueText: "\(delta > 0 ? "+" : "−")\(magnitude) \(unit.symbol)")
    }

    private var repsChip: some View {
        let delta = payload.readback.repsDelta ?? 0
        return deltaChip(label: "REPS", delta: delta,
                         valueText: "\(delta > 0 ? "+" : "−")\(abs(delta))")
    }

    private func deltaChip(label: String, delta: Int, valueText: String) -> some View {
        let color: Color = delta > 0 ? SettColor.positive : (delta < 0 ? SettColor.negative : SettColor.ash)
        let arrow = delta > 0 ? " ↑ " : (delta < 0 ? " ↓ " : " ")
        let text = delta == 0 ? "\(label) HELD" : "\(label)\(arrow)\(valueText)"
        return chip(text: text, color: color)
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .kerning(1)
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1)
            }
    }

    private var accessibilityText: String {
        var parts = [loggedLine]
        switch payload.outcome {
        case .casual: break
        case .warmup: parts.append("Warm-up")
        default:
            if payload.readback.isBaseline {
                parts.append("Baseline set")
            } else {
                if let w = payload.readback.weightDeltaGrams {
                    parts.append("Weight \(w > 0 ? "up" : (w < 0 ? "down" : "held"))")
                }
                if let r = payload.readback.repsDelta {
                    parts.append("Reps \(r > 0 ? "up" : (r < 0 ? "down" : "held"))")
                }
            }
        }
        parts.append(payload.message)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Corner reticle (item 3a — four L-shaped brackets, iron)

/// Four thin L-shaped corner brackets framing the numeral block — a targeting
/// frame. Drawn as a single `Path`; stroked iron by the caller.
struct CornerReticle: Shape {
    /// Length of each bracket arm.
    var arm: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let a = arm
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + a))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + a, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - a, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + a))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - a))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - a, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + a, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - a))
        return path
    }
}
