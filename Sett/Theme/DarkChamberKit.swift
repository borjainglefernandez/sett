import SwiftUI
import UIKit
import SettCore

// MARK: - The Dark Chamber component kit (design language v3)
// No stock parts where power flows. Every component here has a Reduce Motion
// fallback, all ornament is vector, and gold stays exclusive to the power level.

// MARK: - Seeded RNG (deterministic chrome — never Date, never SystemRandom)

/// Minimal linear congruential generator (Knuth MMIX constants), shared by the
/// kit's precomputed particle tracks and fracture lines.
private struct ChamberRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
    mutating func nextCG() -> CGFloat { CGFloat(next()) }
}

// MARK: - (5) SettSigil — the proprietary power glyph

/// An original "spark" mark: a vertically-elongated four-point star broken by
/// an offset diagonal slash — an asymmetric lightning-diamond. Drawn in-house;
/// prefixes the power level everywhere it appears. Not a bolt SF Symbol, not
/// anyone else's diamond.
public struct SettSigil: View {
    let size: CGFloat
    let color: Color

    public init(size: CGFloat, color: Color = SettColor.saiyanGold) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        SigilShape()
            .fill(color)
            .frame(width: size * 0.62, height: size)
            .accessibilityHidden(true)
    }
}

/// The sigil geometry in unit space: star minus a diagonal gap band, plus a
/// thinner slash shard offset inside the gap (the lightning break).
struct SigilShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        // Vertically-elongated 4-point star.
        var star = Path()
        star.move(to: pt(0.50, 0.00))
        star.addLine(to: pt(0.565, 0.40))
        star.addLine(to: pt(0.72, 0.50))
        star.addLine(to: pt(0.565, 0.60))
        star.addLine(to: pt(0.50, 1.00))
        star.addLine(to: pt(0.435, 0.60))
        star.addLine(to: pt(0.28, 0.50))
        star.addLine(to: pt(0.435, 0.40))
        star.closeSubpath()

        // Diagonal gap band, offset below center — the asymmetric break.
        var gap = Path()
        gap.move(to: pt(-0.10, 0.75))
        gap.addLine(to: pt(1.10, 0.33))
        gap.addLine(to: pt(1.10, 0.43))
        gap.addLine(to: pt(-0.10, 0.85))
        gap.closeSubpath()

        var result = star.subtracting(gap)

        // The slash shard bridging the break, shifted down-and-right.
        var slash = Path()
        slash.move(to: pt(0.08, 0.762))
        slash.addLine(to: pt(0.98, 0.442))
        slash.addLine(to: pt(0.98, 0.478))
        slash.addLine(to: pt(0.08, 0.798))
        slash.closeSubpath()
        result.addPath(slash)

        return result
    }
}

// MARK: - (7) EmberHalo — the hearth of the app

/// Ambient warm particles (max 20) drifting up behind the sacred number —
/// gold-to-orange, additive, slow rise with a little wander. When `intensity`
/// jumps upward the halo BURSTS to ~70 particles for one second. Particle
/// tracks are precomputed and seeded: each frame is a pure function of time,
/// no per-frame allocation beyond the draw itself. Under Reduce Motion the
/// halo renders as a static faint glow instead.
public struct EmberHalo: View {
    let intensity: Double

    @State private var burstUntil: Date = .distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(intensity: Double) {
        self.intensity = intensity
    }

    public var body: some View {
        ZStack {
            if reduceMotion {
                staticGlow
            } else {
                particles
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: intensity) { oldValue, newValue in
            if newValue > oldValue + 0.2 {
                burstUntil = Date.now.addingTimeInterval(1)
            }
        }
    }

    private var staticGlow: some View {
        RadialGradient(
            colors: [
                SettColor.saiyanGold.opacity(0.10 + 0.08 * min(max(intensity, 0), 1)),
                .clear,
            ],
            center: .center, startRadius: 0, endRadius: 130
        )
    }

    private var particles: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let bursting = timeline.date < burstUntil
                let ambient = max(0, min(20, Int((20 * intensity).rounded())))
                let count = bursting ? 70 : ambient
                guard count > 0 else { return }
                context.blendMode = .plusLighter
                for track in Self.tracks.prefix(count) {
                    let cycle = t / track.period + track.phase
                    let progress = cycle - cycle.rounded(.down) // 0..<1, bottom → top
                    let fade = sin(progress * .pi) // in & out
                    let x = track.x * size.width
                        + sin(t * track.wanderFreq + track.phase * 17) * track.wander
                    let y = size.height * (1.05 - progress * 1.1)
                    let d = track.size * (bursting ? 1.25 : 1)
                    let color = Color(
                        red: 1.0,
                        green: 0.84 - 0.22 * track.warmth, // gold → orange
                        blue: 0.05
                    ).opacity(fade * (bursting ? 0.85 : 0.55))
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                        with: .color(color)
                    )
                }
            }
        }
    }

    private struct Track {
        let x: Double
        let phase: Double
        let period: Double // seconds per full rise, 4–9 s: slow
        let wander: Double
        let wanderFreq: Double
        let size: Double
        let warmth: Double // 0 = gold, 1 = orange
    }

    /// 70 precomputed tracks; ambient mode uses the first ≤20, bursts use all.
    private static let tracks: [Track] = {
        var rng = ChamberRNG(seed: 0xE3B3_51C1)
        return (0 ..< 70).map { _ in
            Track(
                x: 0.08 + rng.next() * 0.84,
                phase: rng.next(),
                period: 4 + rng.next() * 5,
                wander: 3 + rng.next() * 9,
                wanderFreq: 0.4 + rng.next() * 0.9,
                size: 1.5 + rng.next() * 2.2,
                warmth: rng.next()
            )
        }
    }()
}

// MARK: - (6) SacredNumberView — sigil + numeral + halo + odometer physics

/// The Sacred Number, assembled: SettSigil prefix, PowerNumeral digits, and an
/// EmberHalo hearth behind. On value change it rolls like an odometer through
/// 4–6 intermediate values (numeric-text slot resolve), HIT-STOPS ~90 ms at
/// every crossed multiple of 100 with a rigid tick, then lands with a
/// 1.08 → 1.0 scale punch and a one-second ember burst. Reduce Motion: the
/// value is set directly, no roll, no punch.
public struct SacredNumberView: View {
    let value: Int
    let size: PowerNumeral.Size

    @State private var displayed: Int
    @State private var punch: CGFloat = 1
    @State private var haloIntensity: Double = 0.35
    @State private var roll: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Int, size: PowerNumeral.Size = .xl) {
        self.value = value
        self.size = size
        _displayed = State(initialValue: value)
    }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            SettSigil(size: sigilSize)
            PowerNumeral(displayed, size: size)
        }
        .scaleEffect(punch)
        .background { EmberHalo(intensity: haloIntensity).padding(-36) }
        .onChange(of: value) { _, newValue in
            rollOdometer(to: newValue)
        }
        .onDisappear {
            // Reset transient roll state so a teardown mid-roll can't leave the halo
            // stuck bright (or the numeral punched) on the next presentation.
            roll?.cancel()
            haloIntensity = 0.35
            punch = 1
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power level \(value)")
    }

    // Sigil scales with Dynamic Type in lockstep with PowerNumeral (largeTitle/title/
    // title2 for xl/l/m), so the mark and the number never diverge at large text sizes.
    @ScaledMetric(relativeTo: .largeTitle) private var xlSigil: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var lSigil: CGFloat = 22
    @ScaledMetric(relativeTo: .title2) private var mSigil: CGFloat = 14
    @ScaledMetric(relativeTo: .largeTitle) private var xlSpacing: CGFloat = 10
    @ScaledMetric(relativeTo: .title) private var lSpacing: CGFloat = 8
    @ScaledMetric(relativeTo: .title2) private var mSpacing: CGFloat = 6

    private var sigilSize: CGFloat {
        switch size {
        case .xl: xlSigil
        case .l: lSigil
        case .m: mSigil
        }
    }

    private var spacing: CGFloat {
        switch size {
        case .xl: xlSpacing
        case .l: lSpacing
        case .m: mSpacing
        }
    }

    private func rollOdometer(to newValue: Int) {
        roll?.cancel()
        let start = displayed
        guard !reduceMotion, start != newValue else {
            displayed = newValue
            return
        }
        roll = Task { @MainActor in
            let steps = 5 // 4 intermediates + the landing
            var previous = start
            for step in 1 ... steps {
                guard !Task.isCancelled else { return }
                let fraction = Double(step) / Double(steps)
                let next = step == steps
                    ? newValue
                    : start + Int((Double(newValue - start) * fraction).rounded())
                withAnimation(.easeOut(duration: 0.08)) { displayed = next }
                try? await Task.sleep(for: .milliseconds(70))
                if crossesHundred(previous, next) {
                    Haptics.rigid()
                    try? await Task.sleep(for: .milliseconds(90)) // hit-stop
                }
                previous = next
            }
            guard !Task.isCancelled else { return }
            if newValue > start { haloIntensity = 1.0 } // EmberHalo bursts on the jump
            punch = 1.08
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { punch = 1.0 }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { haloIntensity = 0.35 }
        }
    }

    private func crossesHundred(_ a: Int, _ b: Int) -> Bool {
        let lo = min(a, b)
        let hi = max(a, b)
        return lo / 100 != hi / 100
    }
}

// MARK: - (8) KiGauge — slanted segmented cells, overfillable

/// The v3 gauge: hard-edged parallelogram cells sheared ~12°, 3pt gaps, filled
/// in `accent` with a glowing hot tip on the active (partial) cell. `overfill`
/// (0...1 of an extra band, up to 3 cells) sprouts GOLD cells past the frame's
/// trailing edge. `ghost` (0...1 of the gauge) renders dimmer trailing cells at
/// 25% opacity after the fill — decay you can see draining. A small mono
/// numeral is fused to the trailing end. ~14 pt tall, width flexible. Static —
/// nothing animates, so Reduce Motion needs no special-casing.
public struct KiGauge: View {
    let filled: Double
    let segments: Int
    let overfill: Double
    let ghost: Double
    let accent: Color

    public init(
        filled: Double,
        segments: Int = 12,
        overfill: Double = 0,
        ghost: Double = 0,
        accent: Color = SettColor.heroCyan
    ) {
        self.filled = filled
        self.segments = max(1, segments)
        self.overfill = overfill
        self.ghost = ghost
        self.accent = accent
    }

    private var fillUnits: Double { min(max(filled, 0), 1) * Double(segments) }
    private var wholeCells: Int { Int(fillUnits.rounded(.down)) }

    public var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Ki gauge")
        .accessibilityValue(
            "\(wholeCells) of \(segments)" + (overfill > 0 ? ", overcharged" : "")
        )
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let height = size.height
        let shear = height * CGFloat(tan(12 * Double.pi / 180)) // ~3 pt at 14 pt
        let gap: CGFloat = 3

        // Fused numeral at the trailing end.
        let numeral = Text("\(wholeCells)/\(segments)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(overfill > 0 ? SettColor.saiyanGold : SettColor.ash)
        let resolved = context.resolve(numeral)
        let textSize = resolved.measure(in: size)

        let overfillSlots = 3
        let available = size.width - textSize.width - 8 - shear
        guard available > 0 else { return }
        let step = available / CGFloat(segments + overfillSlots)
        let cellWidth = max(1, step - gap)

        func cell(at x: CGFloat, width: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x + shear, y: 0))
            p.addLine(to: CGPoint(x: x + width + shear, y: 0))
            p.addLine(to: CGPoint(x: x + width, y: height))
            p.addLine(to: CGPoint(x: x, y: height))
            p.closeSubpath()
            return p
        }

        let fraction = fillUnits - Double(wholeCells)
        let ghostUnits = min(max(ghost, 0), 1) * Double(segments)

        for index in 0 ..< segments {
            let x = CGFloat(index) * step
            let base = cell(at: x, width: cellWidth)
            context.fill(base, with: .color(SettColor.cardNested))

            if index < wholeCells {
                context.fill(base, with: .color(accent))
            } else if index == wholeCells, fraction > 0 {
                // Active cell: partial fill + glowing hot tip at the fill edge.
                let partialWidth = cellWidth * CGFloat(fraction)
                context.fill(cell(at: x, width: partialWidth), with: .color(accent))
                let tipX = x + partialWidth
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.fill(cell(at: tipX - 2, width: 4), with: .color(accent))
                }
                context.fill(
                    cell(at: tipX - 0.75, width: 1.5),
                    with: .color(.white.opacity(0.9))
                )
            } else if Double(index) < fillUnits + ghostUnits {
                // Ghost decay trail.
                context.fill(base, with: .color(accent.opacity(0.25)))
            }
        }

        // The frame's trailing edge — overfill sprouts past this line.
        let frameEdgeX = CGFloat(segments) * step - gap + 1.5
        var edge = Path()
        edge.move(to: CGPoint(x: frameEdgeX + shear, y: 0))
        edge.addLine(to: CGPoint(x: frameEdgeX, y: height))
        context.stroke(edge, with: .color(SettColor.cardBorder), lineWidth: 1)

        // Overfill: gold cells past the frame edge (the "ultra" band).
        let overfillUnits = min(max(overfill, 0), 1) * Double(overfillSlots)
        if overfillUnits > 0 {
            let overfillWhole = Int(overfillUnits.rounded(.down))
            let overfillFraction = overfillUnits - Double(overfillWhole)
            for slot in 0 ..< overfillSlots {
                let x = CGFloat(segments + slot) * step + 2
                if slot < overfillWhole {
                    let path = cell(at: x, width: cellWidth)
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 3))
                        layer.fill(path, with: .color(SettColor.saiyanGold.opacity(0.55)))
                    }
                    context.fill(path, with: .color(SettColor.saiyanGold))
                } else if slot == overfillWhole, overfillFraction > 0 {
                    let path = cell(at: x, width: cellWidth * CGFloat(overfillFraction))
                    context.fill(path, with: .color(SettColor.saiyanGold))
                }
            }
        }

        context.draw(
            resolved,
            at: CGPoint(x: size.width - textSize.width / 2, y: height / 2),
            anchor: .center
        )
    }
}

// MARK: - (9) Floating combat text

/// Feed for floating `+42 PWR` text. Views attach the overlay once with
/// `.combatTextEmitter(_:)`, then anything with a reference calls `emit`.
/// Crits (PRs) render 2× and gold; haptics stay the CALLER's job so the PR
/// double-pulse never fires twice. Max 6 concurrent — oldest drop first.
@MainActor
@Observable
public final class CombatTextEmitter {
    public struct Entry: Identifiable, Equatable {
        public let id: UUID
        public let text: String
        public let crit: Bool
        public let jitter: CGFloat
        /// Absolute magnitude of the gain (lb) — scales the splash's size, rise, and
        /// glow so a +2 tick and a +45 record never read the same. 0 = neutral.
        public var magnitude: Int = 0
        /// Text / glow colour — the tier overload hue for gains, bone for status words.
        public var color: Color = SettColor.bone
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public func emit(_ text: String, crit: Bool = false, magnitude: Int = 0,
                     color: Color = SettColor.bone) {
        // Deterministic jitter (no .random — chrome must be recompute-safe): fan
        // successive splashes across a fixed −10…10 spread by their queue position.
        let jitter = CGFloat((entries.count * 7) % 21 - 10)
        let entry = Entry(id: UUID(), text: text, crit: crit, jitter: jitter,
                          magnitude: abs(magnitude), color: color)
        entries.append(entry)
        if entries.count > 6 {
            entries.removeFirst(entries.count - 6)
        }
        let id = entry.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            self?.entries.removeAll { $0.id == id }
        }
    }
}

public struct CombatTextEmitterModifier: ViewModifier {
    let emitter: CombatTextEmitter

    public init(_ emitter: CombatTextEmitter) {
        self.emitter = emitter
    }

    public func body(content: Content) -> some View {
        content.overlay {
            CombatTextOverlay(emitter: emitter)
                .allowsHitTesting(false)
        }
    }
}

public extension View {
    /// Attaches a floating-combat-text overlay fed by `emitter`. Attach to the
    /// region the numbers should rise over (a set row, the summary numeral).
    func combatTextEmitter(_ emitter: CombatTextEmitter) -> some View {
        modifier(CombatTextEmitterModifier(emitter))
    }
}

struct CombatTextOverlay: View {
    let emitter: CombatTextEmitter

    var body: some View {
        ZStack {
            ForEach(emitter.entries) { entry in
                CombatTextLabel(entry: entry)
                    .offset(x: entry.jitter)
            }
        }
        .accessibilityHidden(true)
    }
}

struct CombatTextLabel: View {
    let entry: CombatTextEmitter.Entry

    @State private var rise: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bigger gains launch a bigger splash — the font grows, it flies higher, and
    /// the glow blooms, so the magnitude of the climb is legible at a glance.
    private var magBoost: CGFloat { min(CGFloat(entry.magnitude), 45) }
    private var fontSize: CGFloat { (entry.crit ? 17 : 14) + magBoost * 0.22 }
    private var riseTarget: CGFloat { -40 - magBoost }
    private var glowRadius: CGFloat {
        entry.crit ? 8 + magBoost * 0.2 : (entry.magnitude > 0 ? 5 : 0)
    }

    var body: some View {
        Text(entry.text)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(entry.color)
            .auraGlow(glowRadius > 0 ? entry.color : .clear, radius: glowRadius)
            .scaleEffect(scale)
            .offset(y: rise)
            .opacity(opacity)
            .onAppear(perform: play)
    }

    private func play() {
        if reduceMotion {
            // Brief fade in place.
            withAnimation(.easeIn(duration: 0.15)) { opacity = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) { opacity = 0 }
            return
        }
        opacity = 1
        if entry.crit {
            // Crit: slam in at 2×, spring settle, then rise.
            scale = 2
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { scale = 1 }
            withAnimation(.easeOut(duration: 0.7).delay(0.3)) {
                rise = riseTarget
                opacity = 0
            }
        } else {
            withAnimation(.easeOut(duration: 0.7)) {
                rise = riseTarget
                opacity = 0
            }
        }
    }
}

// MARK: - (10) SystemMessageView — the System Voice

/// Ritual header: terse all-caps wide-tracked mono over an etched slab that
/// MATERIALIZES — opacity, blur, and scale assemble over 0.3 s (the
/// Solo-Leveling grammar, reskinned as etched stone; explicitly not the blue
/// holo window). Reduce Motion: plain fade. Copy voice: `READING COMPLETE`,
/// `DIRECTIVE ISSUED`, `CEILING BROKEN`.
public struct SystemMessageView: View {
    let title: String
    let bodyText: String?

    public init(title: String, body: String? = nil) {
        self.title = title
        self.bodyText = body
    }

    public var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .kerning(3)
                .foregroundStyle(SettColor.bone)
                .multilineTextAlignment(.center)
            if let bodyText {
                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(SettColor.ash)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .settCard()
        .materialize()   // the shared System Voice entrance (RM-safe)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - (11) Frame rarity ladder — rank read from the border finish

/// One fixed card geometry; rank escalates through MATERIAL only.
/// Ornament budget (convention, not enforced): `iron` is the floor, `steel`
/// and `gold` mark mid and high ranks, and `prismatic` — the only per-frame
/// animation in the app — is reserved EXCLUSIVELY for the top tier.
public enum FrameMaterial: CaseIterable, Sendable {
    case iron
    case steel
    case gold
    case prismatic
}

public struct FrameMaterialStyle: ViewModifier {
    let material: FrameMaterial

    @State private var sweep: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ material: FrameMaterial) {
        self.material = material
    }

    public func body(content: Content) -> some View {
        content.overlay { border }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        switch material {
        case .iron:
            // Matte iron: the plain hairline.
            shape.strokeBorder(SettColor.cardBorder, lineWidth: 1)

        case .steel:
            // Brushed steel: lighter vertical-ramp double stroke.
            ZStack {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(dynamicLight: 0xA8A29A, dark: 0xA8A29A),
                            Color(dynamicLight: 0x6C665E, dark: 0x6C665E),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                    .strokeBorder(Color(dynamicLight: 0x8A8478, dark: 0x8A8478).opacity(0.35), lineWidth: 1)
                    .padding(1.5)
            }

        case .gold:
            // Engraved gold: the settCard groove, stronger.
            ZStack {
                shape.strokeBorder(SettColor.etch, lineWidth: 1)
                RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                    .strokeBorder(Aura.gold, lineWidth: 1)
                    .padding(1.5)
                CornerTicksShape(length: 6, inset: 4)
                    .stroke(SettColor.saiyanGold.opacity(0.6), lineWidth: 1)
            }

        case .prismatic:
            // Top tier only: slow cyan-gold sweep, 6 s per revolution.
            // Reduce Motion: the gradient holds still.
            shape
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            SettColor.heroCyan,
                            SettColor.saiyanGold,
                            SettColor.heroCyan,
                        ]),
                        center: .center,
                        angle: .degrees(sweep)
                    ),
                    lineWidth: 1.5
                )
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                        sweep = 360
                    }
                }
        }
    }
}

public extension View {
    /// Overlays the rank border for `material` on the standard 16pt-continuous
    /// card geometry. Prismatic is reserved for the top tier by convention —
    /// nothing enforces it, spend the ornament budget wisely.
    func frameMaterial(_ material: FrameMaterial) -> some View {
        modifier(FrameMaterialStyle(material))
    }
}

// MARK: - (12) CrackOverlay — the ceiling breaks

/// Seeded, deterministic radial fracture: ~10 branching cracks from center,
/// bone-white cores over a gold glow, revealed by `progress` 0 → 1, with a
/// brief white flash when progress lands on 1. Drive `progress` with an
/// animation or timer from the summary's ceiling-break. Reduce Motion: no
/// cracks, just the simple flash.
public struct CrackOverlay: View {
    let progress: Double
    /// The light leaking through the fissures — gold by default; the Time Chamber
    /// ceiling break passes the scouter overload red.
    var color: Color = SettColor.saiyanGold

    @State private var flash: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double, color: Color = SettColor.saiyanGold) {
        self.progress = progress
        self.color = color
    }

    public var body: some View {
        ZStack {
            if !reduceMotion {
                cracks
            }
            Color.white.opacity(flash)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: progress) { oldValue, newValue in
            if oldValue < 1, newValue >= 1 {
                flash = 0.8
                withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            }
        }
    }

    private var cracks: some View {
        Canvas { context, size in
            let clamped = min(max(progress, 0), 1)
            guard clamped > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = max(size.width, size.height) * 0.55
            for fracture in Self.fractures {
                let reveal = min(max((clamped - fracture.delay) / max(1 - fracture.delay, 0.001), 0), 1)
                guard reveal > 0 else { continue }
                let visible = max(2, Int((Double(fracture.points.count) * reveal).rounded(.up)))
                var path = Path()
                for (index, unit) in fracture.points.prefix(visible).enumerated() {
                    let point = CGPoint(
                        x: center.x + unit.x * scale,
                        y: center.y + unit.y * scale
                    )
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                // Light leaks through the fissure: coloured glow under, bone core over.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 2.5))
                    layer.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 2.5)
                }
                context.stroke(path, with: .color(SettColor.bone), lineWidth: 1.2)
            }
        }
    }

    private struct Fracture {
        let points: [CGPoint] // unit space, origin at center
        let delay: Double // fraction of progress before this line starts
    }

    /// 10 main rays plus branches, deterministic. Regenerating the seed
    /// regenerates the whole break identically.
    private static let fractures: [Fracture] = {
        var rng = ChamberRNG(seed: 0xC4AC_0FF1)
        var result: [Fracture] = []
        let rayCount = 10
        for ray in 0 ..< rayCount {
            var angle = (Double(ray) + rng.next() * 0.7) / Double(rayCount) * 2 * .pi
            var radius = 0.04 + rng.next() * 0.05
            var points = [CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)]
            let segmentCount = 6 + Int(rng.next() * 3)
            for _ in 0 ..< segmentCount {
                radius += 0.10 + rng.next() * 0.09
                angle += (rng.next() - 0.5) * 0.5
                points.append(CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
            }
            result.append(Fracture(points: points, delay: rng.next() * 0.15))

            // Branch off roughly half of the rays partway along.
            if rng.next() > 0.45, points.count > 3 {
                let startIndex = 2 + Int(rng.next() * Double(points.count - 3))
                let origin = points[startIndex]
                var branchAngle = atan2(origin.y, origin.x)
                    + (rng.next() > 0.5 ? 1 : -1) * (0.5 + rng.next() * 0.4)
                var branchRadius = 0.0
                var branchPoints = [origin]
                let branchSegments = 3 + Int(rng.next() * 2)
                for _ in 0 ..< branchSegments {
                    branchRadius += 0.05 + rng.next() * 0.05
                    branchAngle += (rng.next() - 0.5) * 0.4
                    branchPoints.append(CGPoint(
                        x: origin.x + cos(branchAngle) * branchRadius,
                        y: origin.y + sin(branchAngle) * branchRadius
                    ))
                }
                result.append(Fracture(points: branchPoints, delay: 0.35 + rng.next() * 0.2))
            }
        }
        return result
    }()
}

// MARK: - (13) CountUpNumber — the shared count-up idiom

/// Rolls a number up to `value` on first appearance using the app's numeric-text
/// idiom (a single digit-morph inside a timed easeOut — the same grammar the Weekly
/// Reading ΔPL established, now shared so every earned number tallies consistently
/// instead of popping). The caller supplies the string form via `format`, so a unit
/// or sign suffix stays put while the digits roll. Reduce Motion: sets the value
/// directly, no roll. If `value` changes after the first roll (re-computed stats),
/// it re-tallies to the new target.
public struct CountUpNumber: View {
    let value: Int
    var from: Int
    var duration: Double
    var format: (Int) -> String
    let font: Font
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int
    @State private var started = false

    public init(
        value: Int,
        from: Int = 0,
        duration: Double = 0.9,
        font: Font,
        color: Color,
        format: @escaping (Int) -> String = { $0.formatted() }
    ) {
        self.value = value
        self.from = from
        self.duration = duration
        self.font = font
        self.color = color
        self.format = format
        _shown = State(initialValue: from)
    }

    public var body: some View {
        Text(format(shown))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear {
                guard !started else { return }
                started = true
                guard !reduceMotion, from != value else { shown = value; return }
                withAnimation(.easeOut(duration: duration)) { shown = value }
            }
            .onChange(of: value) { _, newValue in
                guard started else { return }   // pre-appear changes are picked up by onAppear
                if reduceMotion { shown = newValue }
                else { withAnimation(.easeOut(duration: duration)) { shown = newValue } }
            }
            // The final value is the meaningful one for VoiceOver, not the rolling digits.
            .accessibilityLabel(format(value))
    }
}

// MARK: - (14) AnimatedKiGauge — the Ki gauge, filled on appear

/// A `KiGauge` that FILLS from `from` to `target` on first appearance. The gauge is a
/// Canvas that reads `filled` directly (it doesn't tween a Double), so the fill is
/// stepped through intermediates on a short timer — the same approach `SacredNumberView`
/// uses for its odometer — easing out over ~0.6s. Reduce Motion renders the target
/// fill directly. Re-targets if `target` changes while mounted.
public struct AnimatedKiGauge: View {
    let target: Double
    var from: Double
    var segments: Int
    var accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled: Double
    @State private var roll: Task<Void, Never>?

    public init(
        target: Double,
        from: Double = 0,
        segments: Int = 12,
        accent: Color = SettColor.heroCyan
    ) {
        self.target = target
        self.from = from
        self.segments = segments
        self.accent = accent
        _filled = State(initialValue: from)
    }

    public var body: some View {
        KiGauge(filled: filled, segments: segments, accent: accent)
            .onAppear { animate(to: target) }
            .onChange(of: target) { _, newValue in animate(to: newValue) }
            .onDisappear { roll?.cancel() }
    }

    private func animate(to newTarget: Double) {
        roll?.cancel()
        let start = filled
        let clamped = min(max(newTarget, 0), 1)
        guard !reduceMotion, abs(clamped - start) > 0.001 else {
            filled = clamped
            return
        }
        roll = Task { @MainActor in
            let steps = 26
            for step in 1 ... steps {
                guard !Task.isCancelled else { return }
                let t = Double(step) / Double(steps)
                let eased = 1 - pow(1 - t, 2)   // easeOut
                filled = start + (clamped - start) * eased
                try? await Task.sleep(for: .milliseconds(24))
            }
            guard !Task.isCancelled else { return }
            filled = clamped
        }
    }
}

// MARK: - (15) LevelUpBanner — the persistent ascension beat

/// The persistent "FORM ASCENDED" banner, shown on Home and the Power tab the first
/// time the user opens after crossing a Form threshold — so a level-up that happened
/// via a recompute or between sessions still gets its beat. Gold, because a form
/// ascension is a reward. Tapping it (or the ×) acknowledges via a single source of
/// truth in ProgressionStore, so dismissing on one surface clears both. A one-shot
/// gold ember burst fires on appear; entrance rides the shared materialize grammar;
/// the sigil glows on a slow loop. Reduce Motion: plain fade, no burst, static glow.
public struct LevelUpBanner: View {
    let form: UserForm
    let onAcknowledge: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    @State private var glow = false

    public init(form: UserForm, onAcknowledge: @escaping () -> Void) {
        self.form = form
        self.onAcknowledge = onAcknowledge
    }

    public var body: some View {
        Button(action: acknowledge) {
            HStack(spacing: 12) {
                SettSigil(size: 30, color: SettColor.saiyanGold)
                    .auraGlow(SettColor.saiyanGold, radius: glow ? 13 : 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FORM ASCENDED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(SettColor.saiyanGold.opacity(0.9))
                    Text(form.title)
                        .font(.system(.title3, design: .rounded).weight(.heavy).smallCaps())
                        .kerning(1)
                        .foregroundStyle(SettColor.saiyanGold)
                        .shadow(color: SettColor.saiyanGold.opacity(0.5), radius: 6)
                }
                Spacer(minLength: 8)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SettColor.ash)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudCard(tint: SettColor.saiyanGold)
            .overlay {
                if burst {
                    AuraBurstView(gold: true).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .materialize()
        .onAppear {
            Haptics.levelUp()
            burst = true
            // Unmount the burst once it's spent: a live AuraBurstView keeps its
            // TimelineView(.animation) redrawing EVERY frame forever (it never stops
            // on its own), which pins a CPU core while this persistent banner is up.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                burst = false
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Form ascended to \(form.title). Tap to dismiss.")
        .accessibilityAddTraits(.isButton)
    }

    private func acknowledge() {
        Haptics.selection()
        onAcknowledge()
    }
}

// MARK: - (16) PRShockwaveView — the all-time-PR gold shockwave

/// A one-shot gold shockwave — a ring that expands from the center and fades over
/// ~0.6s — fired when a set beats an all-time lift PR mid-session, so a record reads
/// as bigger than an ordinary beat. Mount it keyed by a token (`.id(token)`) so each
/// PR re-triggers it. Draws nothing under Reduce Motion (the PR haptic ramp still fires).
public struct PRShockwaveView: View {
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expand = false

    public init(color: Color = SettColor.saiyanGold) { self.color = color }

    public var body: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height)
            Circle()
                .stroke(color, lineWidth: expand ? 1 : 7)
                .frame(width: expand ? maxDim * 1.5 : 12,
                       height: expand ? maxDim * 1.5 : 12)
                .opacity(expand ? 0 : 0.9)
                .auraGlow(color, radius: 10)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.6)) { expand = true }
        }
    }
}
