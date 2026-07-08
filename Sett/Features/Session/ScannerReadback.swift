import SwiftUI
import SettCore

// MARK: - Log outcome classification (item 5)

/// How a just-logged set compares to its reference at the same slot. Drives the
/// scanner message pool, the readback chips, and the SET → REST transition color.
/// `beatWeight` is the crit (gold numeral flash + PR haptic); `beatReps` is a
/// gold-sweep "beat" without the crit ceremony. `casual` suppresses all of it.
enum LogOutcome {
    case beatWeight   // crit — heavier than the reference set at this slot
    case beatReps     // same weight, more reps
    case held         // same weight, same reps
    case dropped      // lighter, or same weight with fewer reps
    case baseline     // no reference set at this slot
    case warmup       // logged as a warm-up
    case casual       // workout is off the record

    /// crit: gold numeral flash + prSignature haptic + gold combat text.
    var isCrit: Bool { self == .beatWeight }
    /// beat/crit: gold sweep + longer hold into REST. Others transition bone.
    var isGold: Bool { self == .beatWeight || self == .beatReps }

    static func classify(readback: SetReadback, isWarmup: Bool, isCasual: Bool) -> LogOutcome {
        if isCasual { return .casual }
        if isWarmup { return .warmup }
        if readback.isBaseline { return .baseline }
        let w = readback.weightDeltaGrams ?? 0
        let r = readback.repsDelta ?? 0
        if w > 0 { return .beatWeight }
        if w == 0 && r > 0 { return .beatReps }
        if w == 0 && r == 0 { return .held }
        return .dropped
    }
}

// MARK: - Scanner message pools (item 5 — deterministic, no randomness APIs)

/// Terse Vego/scanner lines, selected by `loggedSetCount % pool.count` so the same
/// session state always yields the same line — recompute-safe, never `.random`.
enum ScannerMessages {
    private static let pools: [LogOutcome: [String]] = [
        .beatWeight: [
            "CEILING RISING.",
            "The bar got heavier. You didn't notice.",
            "OUTPUT UP. Again.",
            "NEW CEILING. Hmph.",
        ],
        .beatReps: [
            "OUTPUT UP.",
            "More reps, same iron. Acceptable.",
            "The Scanner logged the extra work.",
        ],
        .held: [
            "HOLDING THE LINE.",
            "Matched. Consistency is a weapon.",
            "RECORDED. RECOVER.",
        ],
        .dropped: [
            "RECORDED. RECOVER.",
            "Down a notch. The Scanner remembers the peak.",
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

    var body: some View {
        VStack(spacing: 10) {
            Text(loggedLine)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .kerning(1)
                .monospacedDigit()
                .foregroundStyle(payload.outcome.isGold ? SettColor.saiyanGold : SettColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            chipsRow
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SettColor.cardBorder, lineWidth: 1)
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

    private var loggedLine: String {
        "LOGGED · \(WeightFormat.compactWithUnit(grams: payload.weightGrams, unit: unit)) × \(payload.reps)"
    }

    @ViewBuilder
    private var chipsRow: some View {
        switch payload.outcome {
        case .casual:
            EmptyView()
        case .warmup:
            chip(text: "WARM-UP", color: SettColor.ash)
        default:
            if payload.readback.isBaseline {
                chip(text: "BASELINE SET", color: SettColor.heroCyan)
            } else {
                HStack(spacing: 8) {
                    weightChip
                    repsChip
                }
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
