import SwiftUI
import UIKit

// MARK: - The Time Chamber kit (session design language — "training in space")
//
// The session used to be pure-black "incognito." It is now the Hyperbolic Time
// Chamber reimagined as a cosmic training void: a deep-space backdrop, a scouter
// HUD around the numbers, and an AURA that ignites and shifts color as you log —
// the powering-up "transformation" ladder. Colour and motion live HERE (out in
// the rest of the app the Dark Chamber rules still hold: gold = power level only).
// Everything has a Reduce-Motion fallback; the numbers never lose legibility.

// MARK: - Aura tier — the transformation ladder

/// A training-realm aura: the colour + energy the chamber shows for a given
/// reading. Drives the background tint, the aura ring, the ki field, and the
/// transformation burst. Higher tiers = brighter, faster, more particles.
enum AuraTier: Equatable {
    case dormant   // resting / no reading yet — faint embers
    case base      // holding the line (green win)
    case ascended  // beat the reference — amber ascension
    case radiant   // personal best — red overload (the full transformation)
    case defended  // held under fire on a cut — warm amber, never cold
    case fatigued  // output down — cool steel, dimmed
    case calm      // warm-up / off the record / stalled — quiet

    /// Primary aura hue — the classic scouter ramp: green holding, amber when you
    /// beat last time, RED when you crack a ceiling (the scouter overloading).
    var color: Color {
        switch self {
        case .dormant, .base, .calm: TimeChamber.scouterGreen
        case .ascended, .defended: TimeChamber.scouterAmber
        case .radiant: TimeChamber.scouterRed
        case .fatigued: TimeChamber.scouterSteel
        }
    }

    /// A hotter/lighter companion hue for gradients and cores.
    var secondary: Color {
        switch self {
        case .dormant, .base, .calm: TimeChamber.scouterGreenPale
        case .ascended, .defended: TimeChamber.scouterAmberPale
        case .radiant: TimeChamber.scouterRedPale
        case .fatigued: TimeChamber.iceBlue
        }
    }

    /// 0…1 — glow strength, particle density, ring flare.
    var intensity: Double {
        switch self {
        case .dormant: 0.30
        case .calm: 0.38
        case .fatigued: 0.45
        case .defended: 0.55
        case .base: 0.60
        case .ascended: 0.85
        case .radiant: 1.0
        }
    }

    /// Rotational energy of the aura arcs (deg/sec of the fastest arc).
    var spin: Double {
        switch self {
        case .dormant, .calm: 18
        case .fatigued: 22
        case .defended: 30
        case .base: 34
        case .ascended: 58
        case .radiant: 84
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [secondary, color], startPoint: .top, endPoint: .bottom)
    }

    /// Whether this tier is a "win" worth a brighter transformation flash.
    var isTransformation: Bool { self == .ascended || self == .radiant }

    // MARK: Form — separates a held WIN from idle, and orders the ladder.
    // (No new hues: every value stays on the green→amber→red ramp; gold untouched.)

    /// Ordering on the transformation ladder — higher = more powered-up. Lets callers
    /// detect an UPWARD tier change (AuraTier isn't Comparable) to fire a spool-up.
    /// Distinct integers, monotonic with `intensity`.
    var rank: Int {
        switch self {
        case .dormant: 0
        case .calm: 1
        case .fatigued: 2
        case .defended: 3
        case .base: 4
        case .ascended: 5
        case .radiant: 6
        }
    }

    /// 0…1 — how COMPLETE the energy ring reads. A sustained charge closes the halo
    /// (fuller arcs); a resting/quiet tier shows only a thin, broken filament. This is
    /// what separates a HELD win (.base) from the idle .dormant chamber — all green,
    /// but the win's ring is visibly fuller. Consumed by AuraRing arc trims.
    var ringCompleteness: Double {
        switch self {
        case .dormant:  0.34
        case .calm:     0.46
        case .fatigued: 0.52
        case .defended: 0.74
        case .base:     0.82
        case .ascended: 0.94
        case .radiant:  1.0
        }
    }

    /// 0…1 — rim / hairline brightness. Idle rim is a faint outline; a held win lights
    /// the rim to a solid charged phosphor. Same hue, brighter & more solid.
    var rimOpacity: Double {
        switch self {
        case .dormant:  0.30
        case .calm:     0.40
        case .fatigued: 0.48
        case .defended: 0.66
        case .base:     0.78
        case .ascended: 0.92
        case .radiant:  1.0
        }
    }

    /// How far the base hue is pushed toward its pale companion — a brighter "charged"
    /// phosphor. Green→pale-green is still green, so the ramp holds.
    var phosphorMix: Double {
        switch self {
        case .dormant:  0.0
        case .calm:     0.06
        case .fatigued: 0.08
        case .defended: 0.16
        case .base:     0.22
        case .ascended: 0.20
        case .radiant:  0.30
        }
    }

    /// The rim / core phosphor tone: the tier hue brightened toward its pale companion
    /// by `phosphorMix`. Stays on the green→amber→red ramp, just brighter for a charge.
    var phosphor: Color { color.mix(with: secondary, by: phosphorMix) }
}

// MARK: - Chamber backgrounds (pick your training realm)

/// The selectable session backdrops — each a generated realm with its own vibe.
/// Stored on `UserSettingsStore.chamberBackground` by `rawValue`.
enum ChamberBackground: String, CaseIterable, Identifiable {
    case nebula, white, volcanic, storm, aurora, sanctuary

    var id: String { rawValue }

    var assetName: String {
        switch self {
        case .nebula: "TimeChamberHero"
        case .white: "ChamberWhite"
        case .volcanic: "ChamberVolcanic"
        case .storm: "ChamberStorm"
        case .aurora: "ChamberAurora"
        case .sanctuary: "ChamberSanctuary"
        }
    }

    var title: String {
        switch self {
        case .nebula: "Nebula Void"
        case .white: "White Void"
        case .volcanic: "Volcanic Forge"
        case .storm: "Storm Realm"
        case .aurora: "Aurora Tundra"
        case .sanctuary: "Golden Sanctuary"
        }
    }

    static func resolve(_ raw: String) -> ChamberBackground {
        ChamberBackground(rawValue: raw) ?? .nebula
    }
}

// MARK: - Cosmic palette (session only)

enum TimeChamber {
    /// Zenith transformation — white breaking into gold.
    static let zenith = Color(dynamicLight: 0xFFF3C0, dark: 0xFFF3C0)
    static let hotGold = Color(dynamicLight: 0xFFB020, dark: 0xFFB020)
    static let iceBlue = Color(dynamicLight: 0xBFEFFF, dark: 0xBFEFFF)
    /// "Output down" — cool cosmic indigo, never alarm-red in this realm.
    static let indigo = Color(dynamicLight: 0x8E86FF, dark: 0x8E86FF)
    static let teal = Color(dynamicLight: 0x63E0C8, dark: 0x63E0C8)
    /// Deep void used to scrim the hero image for legibility.
    static let void = Color(dynamicLight: 0x070512, dark: 0x070512)

    // The classic scouter ramp — green phosphor → amber → overload red.
    static let scouterGreen = Color(dynamicLight: 0x46E0A0, dark: 0x46E0A0)
    static let scouterGreenPale = Color(dynamicLight: 0xC2FFE2, dark: 0xC2FFE2)
    static let scouterAmber = Color(dynamicLight: 0xFFC24D, dark: 0xFFC24D)
    static let scouterAmberPale = Color(dynamicLight: 0xFFE7A8, dark: 0xFFE7A8)
    static let scouterRed = Color(dynamicLight: 0xFF5A3C, dark: 0xFF5A3C)
    static let scouterRedPale = Color(dynamicLight: 0xFFB29B, dark: 0xFFB29B)
    /// "Output down" — a cool steel blue.
    static let scouterSteel = Color(dynamicLight: 0x7FA8E0, dark: 0x7FA8E0)
}

// MARK: - Time Chamber background (the cosmic void)

/// Full-bleed session backdrop: the generated cosmic hero image, slowly drifting
/// (Ken-Burns), scrimmed dark at top and bottom so UI text stays legible, tinted
/// by the current aura, with a drifting starfield/mote layer for depth. Reduce
/// Motion holds everything still. One instance lives at the shell so it persists
/// unbroken across SET ↔ REST.
struct TimeChamberBackground: View {
    var tier: AuraTier = .dormant
    var assetName: String = ChamberBackground.nebula.assetName

    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimeChamber.void
                heroImage(in: geo.size)
                scrim
                tint
                MoteField(tier: tier)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func heroImage(in size: CGSize) -> some View {
        Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .scaleEffect(reduceMotion ? 1.06 : (drift ? 1.14 : 1.04))
            .offset(y: reduceMotion ? 0 : (drift ? -16 : 12))
            .clipped()
    }

    /// Dark top (header legibility) and dark bottom (slab / readback legibility),
    /// letting the colourful nebula band glow through the middle.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: TimeChamber.void.opacity(0.92), location: 0.0),
                .init(color: TimeChamber.void.opacity(0.45), location: 0.16),
                .init(color: .clear, location: 0.40),
                .init(color: .clear, location: 0.58),
                .init(color: TimeChamber.void.opacity(0.72), location: 0.82),
                .init(color: TimeChamber.void.opacity(0.96), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// A soft central wash of the aura colour — the chamber breathes with the tier.
    private var tint: some View {
        RadialGradient(
            colors: [tier.color.opacity(0.12 * tier.intensity), .clear],
            center: .center, startRadius: 0, endRadius: 360
        )
        .blendMode(.plusLighter)
    }
}

extension View {
    /// Session-only cosmic backdrop. Pass the live aura tier so the void breathes
    /// with the reading.
    func timeChamberBackground(tier: AuraTier = .dormant) -> some View {
        background(TimeChamberBackground(tier: tier))
    }
}

// MARK: - Mote field (drifting energy specks — flowy depth)

/// A calm field of drifting glowing motes over the void, tinted by the aura.
/// Deterministic tracks (seeded), pure function of time — no per-frame alloc.
/// Reduce Motion renders a faint static scatter.
struct MoteField: View {
    var tier: AuraTier
    /// Caps the specks for sparse ambient uses (Home's realm glow) — nil keeps the
    /// session's full tier-driven density.
    var maxCount: Int? = nil

    @State private var spoolBias: CGFloat = 0   // transient inward pull + brighten on tier-up
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    for track in Self.tracks.prefix(min(28, maxCount ?? 28)) {
                        let x = track.x * size.width
                        let y = track.baseY * size.height
                        let d = track.size
                        // Reduce Motion: brightness STEP only — no inward drift.
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)),
                                     with: .color(tint(track).opacity(0.30 * (1 + Double(spoolBias) * 0.6))))
                    }
                }
                .allowsHitTesting(false)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        context.blendMode = .plusLighter
                        let count = min(14 + Int(16 * tier.intensity), maxCount ?? .max)
                        let cx = size.width * 0.5
                        let cy = size.height * 0.42   // lens sits a touch above center
                        for track in Self.tracks.prefix(count) {
                            let cycle = t / track.period + track.phase
                            let progress = cycle - cycle.rounded(.down)   // 0→1 rise
                            let fade = sin(progress * .pi)
                            let x = track.x * size.width
                                + sin(t * track.wanderFreq + track.phase * 11) * track.wander
                            let y = size.height * (1.02 - progress * 1.04)
                            // Tier-up inward bias: briefly pull motes toward the core + brighten.
                            let bx = x + (cx - x) * Double(spoolBias) * 0.22
                            let by = y + (cy - y) * Double(spoolBias) * 0.22
                            let d = track.size * (0.8 + 0.5 * tier.intensity)
                            context.fill(
                                Path(ellipseIn: CGRect(x: bx - d / 2, y: by - d / 2, width: d, height: d)),
                                with: .color(tint(track).opacity(fade * 0.5 * (0.5 + tier.intensity / 2) * (1 + Double(spoolBias) * 0.6)))
                            )
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: tier) { old, new in
            guard new.rank > old.rank else { return }
            spoolBias = 1
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.5)) { spoolBias = 0 }
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { spoolBias = 0 }
            }
        }
    }

    /// Most motes take the aura colour; a few stay white "stars" for depth.
    private func tint(_ track: Track) -> Color {
        track.warmth > 0.82 ? .white : (track.warmth > 0.55 ? tier.secondary : tier.color)
    }

    struct Track {
        let x: Double
        let baseY: Double
        let phase: Double
        let period: Double
        let wander: Double
        let wanderFreq: Double
        let size: Double
        let warmth: Double
    }

    static let tracks: [Track] = {
        var rng = SeededGen(seed: 0x71E_C4A3_1234)
        return (0 ..< 48).map { _ in
            Track(
                x: rng.unit(),
                baseY: rng.unit(),
                phase: rng.unit(),
                period: 7 + rng.unit() * 9,
                wander: 4 + rng.unit() * 12,
                wanderFreq: 0.3 + rng.unit() * 0.7,
                size: 1.4 + rng.unit() * 2.6,
                warmth: rng.unit()
            )
        }
    }()
}

/// Minimal seeded LCG for deterministic chrome (never Date / SystemRandom).
struct SeededGen {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - Aura ring (the scouter energy halo around the numbers)

/// Concentric energy the numbers sit inside: a soft outer bloom, a base ring, and
/// three trimmed arcs counter-rotating at tier speed. Rotation is driven by
/// Core-Animation `repeatForever` (GPU-composited — cheap; a 60 fps TimelineView
/// here starves touch delivery). `burstToken` (bumped on every log) flares the
/// ring outward for ~0.6 s — the "power-up." Reduce Motion: a static glowing ring.
struct AuraRing: View {
    var tier: AuraTier
    /// Increment to trigger a one-shot flare (e.g. on log).
    var burstToken: Int = 0

    @State private var spinA = false   // fast arcs (wrap at 360° — seamless)
    @State private var spinB = false   // slower counter-arc
    @State private var pulse = false
    @State private var flare: CGFloat = 0
    @State private var spoolKick: Double = 0   // additive rotation on tier-up (deg)
    @State private var spoolGlow: CGFloat = 0  // bloom overshoot on tier-up
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Outer bloom — charged phosphor (a held win glows brighter), swelling on
            // burst (flare) and on a tier-up spool (spoolGlow).
            Circle()
                .stroke(tier.phosphor.opacity(0.24 * tier.intensity + Double(abs(spoolGlow)) * 0.22),
                        lineWidth: 14 + abs(flare) * 22 + abs(spoolGlow) * 10)
                .blur(radius: 16 + flare * 14)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.015 : 0.985))
            // Steady base ring — brightness & tone read the tier's FORM (a held win is
            // a solid charged phosphor; idle is a faint ember).
            Circle().stroke(tier.phosphor.opacity(0.55 * tier.rimOpacity), lineWidth: 1.5)
            // Energy arcs — trims scale with ringCompleteness (a sustained charge closes
            // the halo; idle shows a thin filament), and ±spoolKick flares them open on
            // a tier-up.
            arc(trim: 0.55 * tier.ringCompleteness, width: 3.0).rotationEffect(.degrees((spinA ? 360 : 0) + spoolKick))
            arc(trim: 0.14 * tier.ringCompleteness, width: 4.0).rotationEffect(.degrees((spinA ? 360 : 0) + spoolKick)).blur(radius: 1)
            arc(trim: 0.30 * tier.ringCompleteness, width: 2.0).rotationEffect(.degrees((spinB ? -360 : 0) - spoolKick))
        }
        .scaleEffect(1 + flare * 0.10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: startSpin)
        .onChange(of: tier) { old, new in
            startSpin()
            guard new.rank > old.rank else { return }
            spoolUp()
        }
        .onChange(of: burstToken) { _, _ in
            guard !reduceMotion else { return }
            // Gather (inhale — contract + brighten), then detonate (snap out + settle).
            withAnimation(.easeIn(duration: 0.14)) { flare = -0.3 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                flare = 1
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { flare = 0 }
            }
        }
    }

    private func arc(trim: CGFloat, width: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(tier.gradient, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// Transient spool-up on an upward tier change: arcs sweep an extra ~40° over
    /// 0.4 s (they accelerate) and the outer bloom springs past then settles.
    private func spoolUp() {
        guard !reduceMotion else {
            // Reduce Motion: an instant brightness STEP (no withAnimation — spoolGlow
            // also feeds the bloom lineWidth geometry, which must not TWEEN under RM).
            spoolGlow = 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                spoolGlow = 0
            }
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { spoolKick += 40 }
        spoolGlow = 1
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { spoolGlow = 0 }
    }

    private func startSpin() {
        guard !reduceMotion else { return }
        // Re-seed the repeating rotations at the current tier speed.
        spinA = false; spinB = false
        withAnimation(.linear(duration: 360 / tier.spin).repeatForever(autoreverses: false)) {
            spinA = true
        }
        withAnimation(.linear(duration: 360 / (tier.spin * 0.6)).repeatForever(autoreverses: false)) {
            spinB = true
        }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

// MARK: - Scouter lens (the DBZ scouter HUD that frames the reading)

/// The iconic scouter eyepiece, drawn as an elongated angular lens: aura-tinted
/// glass (darkened in the middle so the numerals always read), a bright rim with
/// a glow, horizontal scan lines, a triangular emitter tab on the left, corner
/// target brackets, and a power-reading tick strip along the bottom. The rim/glass
/// take the aura colour, so the scouter itself "transforms." `burstToken` flares
/// it on log. Fills its frame — place numerals over it in a ZStack.
struct ScouterLensShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = rect.height * 0.32   // angled left/right ends (roomier top/bottom)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

struct ScouterLens: View {
    var tier: AuraTier
    var burstToken: Int = 0
    /// Gauge fill 0…1 — the live power reading vs the ceiling. The tick strip lights
    /// left→right to this level. Default 1 keeps standalone / preview use full.
    var charge: Double = 1
    /// Where the ceiling notch sits on the strip (0…1); −1 hides it.
    var ceilingFrac: Double = -1
    /// Where LAST WEEK's reading sits on the strip (0…1); −1 hides it. A nearer,
    /// shorter marker than the ceiling — the target you actually beat most sessions.
    var lastWeekFrac: Double = -1
    /// True when the live reading has crossed the ceiling — flips LOCK→PEAK and
    /// holds the indicator solid (the scouter has locked onto a record).
    var atCeiling: Bool = false
    /// True during the ~0.35 s acquisition sweep on a fresh slot (the player owns the
    /// timing). Fires ONE downward sweep + a searching lock flicker, then the
    /// instrument rests: static scan lines, no sweep, a SOLID lock. Default false so
    /// standalone / preview use renders the settled state, not a screensaver.
    var acquiring: Bool = false
    /// 0…1 — glass strain: how far the live reading sits above the phase "held" band
    /// toward the ceiling. Seeded hairline stress-fractures fade in at this opacity;
    /// past ~0.6 a ~1px buzz creeps in. 0 = pristine glass.
    var overload: Double = 0
    /// Stable per-slot seed for the crack polylines (pass acquireSeed so a set always
    /// cracks the same way). Non-zero fallback for previews.
    var crackSeed: UInt64 = 0x5E77_C4A6_0F13
    /// One-shot milestone highlight: `milestoneTick` is the gauge tick (0…17) to
    /// brighten as the reading crosses a round-hundred below the ceiling; `milestoneGlow`
    /// (1→0, animated by the caller) fades it. −1 / 0 = none.
    var milestoneTick: Int = -1
    var milestoneGlow: Double = 0

    @State private var flare: CGFloat = 0
    @State private var sweepPhase: CGFloat = 0  // one-shot acquisition sweep travel (0→1)
    @State private var blink = false            // lock flicker — only while acquiring
    @State private var spoolGlow: CGFloat = 0   // rim/bloom overshoot on an upward tier change
    @State private var crackFlash: Double = 0   // extra crack brightness on a PR crossing
    @State private var crackJitter: CGFloat = 0 // ~1px seeded strain buzz past 0.6 overload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = ScouterLensShape()
        ZStack {
            // Soft aura bloom — charged phosphor (a held win glows brighter than idle),
            // brightening on inhale/burst (flare) and on a tier-up spool (spoolGlow).
            shape.fill(tier.phosphor.opacity(0.16 * tier.intensity + Double(abs(flare)) * 0.25 + Double(abs(spoolGlow)) * 0.20))
                .blur(radius: 26)
                .scaleEffect(1.06 + flare * 0.06 + spoolGlow * 0.05)

            // Glass: dark core (legibility) warming to the scouter hue at the edges.
            shape.fill(
                RadialGradient(
                    colors: [TimeChamber.void.opacity(0.82),
                             TimeChamber.void.opacity(0.5),
                             tier.phosphor.opacity(0.10 + 0.14 * tier.rimOpacity)],
                    center: .center, startRadius: 6, endRadius: 240
                )
            )

            ZStack {
                scanLines
                sweepBar
            }
            .clipShape(shape)
            GeometryReader { geo in crackLayer(in: geo.size) }.clipShape(shape)
            GeometryReader { geo in tickStrip(in: geo.size) }.clipShape(shape)
            targetBrackets
            lockIndicator

            // Rim — charged phosphor, its solidity reading the tier's FORM (a held win is
            // a near-solid rim; idle a faint outline), brightening on flare + spool.
            shape.stroke(tier.gradient,
                         style: StrokeStyle(lineWidth: 2.5 + abs(flare) * 2 + abs(spoolGlow) * 1.6, lineJoin: .round))
                .opacity(0.35 + 0.65 * tier.rimOpacity)
                .shadow(color: tier.color.opacity(0.7 * tier.rimOpacity), radius: 8 + abs(flare) * 10 + abs(spoolGlow) * 8)
            shape.stroke(tier.phosphor.opacity(0.35 * tier.rimOpacity), lineWidth: 1).padding(5)

            emitter
        }
        .scaleEffect(1 + flare * 0.03)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: tier) { old, new in
            guard new.rank > old.rank else { return }
            spoolUp()
        }
        .onChange(of: burstToken) { _, _ in
            guard !reduceMotion else { return }
            // Gather (inhale — contract + brighten), then detonate (snap out + settle).
            withAnimation(.easeIn(duration: 0.14)) { flare = -0.3 }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                flare = 1
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { flare = 0 }
            }
        }
        .onChange(of: acquiring) { _, isAcquiring in
            guard !reduceMotion else { return }
            if isAcquiring {
                // One downward sweep — the scouter reading the fresh target.
                sweepPhase = 0
                withAnimation(.linear(duration: 0.35)) { sweepPhase = 1 }
                // Lock dot searches (fast flicker) until the read settles.
                blink = false
                withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true)) { blink = true }
            } else {
                // Settle: a finite anim replaces the repeatForever, stopping the loop.
                withAnimation(.easeOut(duration: 0.12)) { blink = false }
            }
        }
        .onChange(of: overload > 0.6) { _, straining in
            guard !reduceMotion else { return }
            if straining {
                crackJitter = 0
                withAnimation(.easeInOut(duration: 0.08).repeatForever(autoreverses: true)) { crackJitter = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { crackJitter = 0 }
            }
        }
        .onChange(of: atCeiling) { _, isPeak in
            guard !reduceMotion, isPeak else { return }   // PR crossing: flash then reform
            crackFlash = 0.7
            withAnimation(.easeOut(duration: 0.5)) { crackFlash = 0 }
        }
    }

    /// Rim + bloom overshoot on an upward tier change (arcs live in AuraRing).
    /// Composes additively with the burst `flare`.
    private func spoolUp() {
        guard !reduceMotion else {
            // Reduce Motion: an instant brightness STEP (no withAnimation — spoolGlow
            // also feeds the bloom scale + rim geometry, which must not TWEEN under RM).
            spoolGlow = 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                spoolGlow = 0
            }
            return
        }
        spoolGlow = 1
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { spoolGlow = 0 }
    }

    /// LOCK dot: SOLID at rest (locked) and at PEAK; a fast flicker only while a fresh
    /// read is being acquired. Reduce Motion holds it solid.
    private var lockDotOpacity: Double {
        if atCeiling || reduceMotion { return 1 }
        if acquiring { return blink ? 1 : 0.25 }
        return 1
    }

    /// SCAN (searching) while acquiring, LOCK once settled, PEAK at the ceiling.
    private var lockCaption: String {
        if atCeiling { return "PEAK" }
        return acquiring ? "SCAN" : "LOCK"
    }

    /// Faint horizontal scan lines — a STATIC phosphor grid (no drift at rest).
    private var scanLines: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let spacing: CGFloat = 13
            let count = Int(h / spacing) + 2
            ForEach(0 ..< count, id: \.self) { i in
                Rectangle()
                    .fill(tier.color.opacity(0.10))
                    .frame(height: 1)
                    .offset(y: CGFloat(i) * spacing - spacing)
            }
        }
    }

    /// A bright bar sweeping down the lens — the scanner reading the target. A ONE-SHOT
    /// tied to acquisition (visible only while `acquiring`); at rest it's hidden.
    private var sweepBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, tier.secondary.opacity(0.55), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .shadow(color: tier.color.opacity(0.8), radius: 6)
                .offset(y: sweepPhase * (geo.size.height - 2))
                .opacity(acquiring ? 1 : 0)
        }
    }

    /// A few seeded hairline fractures across the glass — deterministic polylines from
    /// `crackSeed`, so a given set always cracks identically (pure, no Date/random).
    private func crackPath(in size: CGSize) -> Path {
        var rng = SeededGen(seed: crackSeed | 1)
        var path = Path()
        for _ in 0 ..< 5 {                       // 5 strands
            var pt = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
            path.move(to: pt)
            var dir = rng.unit() * 2 * .pi
            let kinks = 3 + Int(rng.unit() * 3)  // 3…5
            for _ in 0 ..< kinks {
                let len = (0.10 + rng.unit() * 0.16) * size.width
                dir += (rng.unit() - 0.5) * 1.1
                pt = CGPoint(x: pt.x + cos(dir) * len, y: pt.y + sin(dir) * len)
                path.addLine(to: pt)
                if rng.unit() > 0.6 {            // short branch fork
                    let bl = (0.05 + rng.unit() * 0.08) * size.width
                    let bd = dir + (rng.unit() - 0.5) * 1.6
                    path.addLine(to: CGPoint(x: pt.x + cos(bd) * bl, y: pt.y + sin(bd) * bl))
                    path.move(to: pt)
                }
            }
        }
        return path
    }

    /// Stress-fracture overlay: a dark hairline channel + a hot aura-hued edge, faded in
    /// by `overload`, brightened by `crackFlash` on a PR, buzzed ~1px by `crackJitter`.
    /// Reduce Motion → static at `overload` opacity, no offset.
    private func crackLayer(in size: CGSize) -> some View {
        let base = crackPath(in: size)
        return ZStack {
            base.stroke(TimeChamber.void.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            base.stroke(tier.secondary.opacity(0.85),
                        style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
                .shadow(color: tier.color.opacity(0.7), radius: 2 + crackFlash * 4)
        }
        .opacity(min(1, overload + crackFlash))
        .offset(x: reduceMotion ? 0 : crackJitter, y: reduceMotion ? 0 : crackJitter * 0.6)
        .animation(.easeOut(duration: 0.3), value: overload)
        .allowsHitTesting(false)
    }

    /// Live power gauge along the bottom inner edge — the scouter scale. Ticks light
    /// left→right to `charge`; a taller notch marks the ceiling (prior best), so you
    /// watch the reading march toward it and, on a PR, sweep visibly past. Pure state.
    private func tickStrip(in size: CGSize) -> some View {
        let ceilingIndex = ceilingFrac >= 0 ? min(17, max(0, Int((ceilingFrac * 17).rounded()))) : -1
        let lastIndex = lastWeekFrac >= 0 ? min(17, max(0, Int((lastWeekFrac * 17).rounded()))) : -1
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(0 ..< 18, id: \.self) { i in
                let lit = Double(i) / 17 <= charge
                let isCeiling = i == ceilingIndex
                let isLast = i == lastIndex && i != ceilingIndex   // ceiling wins a tie
                let isMilestone = i == milestoneTick && milestoneGlow > 0
                Rectangle()
                    .fill(isCeiling ? tier.secondary
                          : isLast ? SettColor.bone                // last-week: a neutral bone marker
                          : (isMilestone ? tier.secondary : tier.color.opacity(lit ? 0.9 : 0.16)))
                    .frame(width: (isCeiling || isLast) ? 2 : 1.5,
                           height: (isCeiling ? 11 : (isLast ? 9 : (lit ? 8 : 4))) + (isMilestone ? CGFloat(5 * milestoneGlow) : 0))
                    .brightness(isMilestone ? milestoneGlow * 0.3 : 0)
            }
        }
        .frame(width: size.width * 0.62)
        .frame(maxWidth: .infinity, alignment: .center)
        .position(x: size.width / 2, y: size.height - 16)
    }

    /// Small corner target brackets inside the top corners — the reticle.
    private var targetBrackets: some View {
        CornerReticle(arm: 12)
            .stroke(tier.color.opacity(0.5), lineWidth: 1.5)
            .padding(.horizontal, 44)
            .padding(.vertical, 18)
    }

    /// A blinking lock light + "LOCK" caption at the top of the lens — the scouter
    /// has a target. Top-centre so it always sits fully inside the glass.
    private var lockIndicator: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                Circle()
                    .fill(tier.color)
                    .frame(width: 5, height: 5)
                    .shadow(color: tier.color, radius: 3)
                    .opacity(lockDotOpacity)
                Text(lockCaption)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .kerning(1)
                    .foregroundStyle(tier.color.opacity(0.85))
            }
            .position(x: geo.size.width / 2, y: 16)
        }
    }

    /// The scouter's characteristic side piece: a triangular emitter off the left
    /// point with a small hinge dot — the bit that would clip over the ear.
    private var emitter: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midY - 14))
                    p.addLine(to: CGPoint(x: -14, y: midY))
                    p.addLine(to: CGPoint(x: 0, y: midY + 14))
                    p.closeSubpath()
                }
                .fill(tier.gradient)
                .shadow(color: tier.color.opacity(0.7), radius: 5)
                Circle()
                    .fill(tier.secondary)
                    .frame(width: 5, height: 5)
                    .position(x: -8, y: midY)
            }
        }
    }
}

// MARK: - Ki convergence (inward speck rush that hands off to the burst)

/// A one-shot inward particle layer: on `burstToken` a seeded ring of specks rushes
/// INTO the lens centre over ~260 ms, then cuts out exactly as the outward `flare`
/// detonates (snaps to +1 at ~140 ms in ScouterLens/AuraRing) — restoring a true
/// "gather → detonate" on LOG. Pure Core-Animation: ONE shared `converge` value,
/// per-speck deterministic tracks read through pow() — no TimelineView, no Date, no
/// random. Reduce Motion renders NOTHING.
struct KiConvergence: View {
    var tier: AuraTier
    var burstToken: Int = 0
    /// Stable seed so the speck ring is identical across recomputes (slot-derived).
    var seed: UInt64 = 0

    @State private var converge: CGFloat = 0   // 0 = out on the ring, 1 = arrived
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Density scales with the tier — a PR pulls in more ki than a hold (10…20).
    private var count: Int { 10 + Int(10 * tier.intensity) }

    var body: some View {
        if reduceMotion {
            Color.clear   // renders nothing; no ForEach / no per-frame work
        } else {
            GeometryReader { geo in
                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                // Ring radius: just outside the numeral block, inside the rim.
                let ringR = min(geo.size.width, geo.size.height) * 0.46
                ZStack {
                    ForEach(0 ..< count, id: \.self) { i in
                        let s = Self.speck(i, seed: seed)
                        // pow() staggers arrival off the single shared `converge`.
                        let f = CGFloat(pow(Double(converge), Double(s.speed)))
                        let pos = CGPoint(x: c.x + s.dir.dx * ringR * (1 - f),
                                          y: c.y + s.dir.dy * ringR * (1 - f))
                        Circle()
                            .fill(s.warm ? tier.secondary : tier.color)
                            .frame(width: s.size, height: s.size)
                            .shadow(color: tier.color.opacity(0.8), radius: 2)
                            .scaleEffect(0.6 + 0.4 * f)          // tightens as it nears centre
                            .opacity(visible ? Double(1 - f) * s.bright : 0)
                            .position(pos)
                            .blur(radius: 0.4)
                    }
                }
                .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: burstToken) { _, _ in fire() }
        }
    }

    private func fire() {
        guard !reduceMotion else { return }
        // Snap the ring to its outer start, fully lit, then rush inward.
        converge = 0
        visible = true
        withAnimation(.easeIn(duration: 0.26)) { converge = 1 }
        // Cut visibility as the outward detonation takes over (flare → +1 at ~140 ms),
        // so the inward layer never fights the expansion.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.12)) { visible = false }
        }
    }

    private struct Speck {
        let dir: CGVector   // unit-ish direction centre → ring point (elliptical jitter)
        let size: CGFloat
        let speed: CGFloat  // pow exponent — >1 arrives later, <1 earlier
        let bright: Double
        let warm: Bool
    }

    private static func speck(_ i: Int, seed: UInt64) -> Speck {
        var rng = SeededGen(seed: seed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15)
        let angle = rng.unit() * 2 * .pi
        let radiusJitter = 0.85 + rng.unit() * 0.30    // 0.85…1.15 (elliptical ring)
        let dir = CGVector(dx: cos(angle) * radiusJitter, dy: sin(angle) * radiusJitter)
        let size = 2.0 + rng.unit() * 3.0              // 2…5 pt
        let speed = 0.8 + rng.unit() * 0.6             // 0.8…1.4 arrival stagger
        let bright = 0.6 + rng.unit() * 0.4
        let warm = rng.unit() > 0.6                    // a few take the hotter secondary hue
        return Speck(dir: dir, size: size, speed: CGFloat(speed), bright: bright, warm: warm)
    }
}

// MARK: - Transformation burst (full-screen power-up flash on a win)

/// A one-shot radial flash + expanding ring in the tier colour, fired on a
/// beat/PR log — the transformation. Drive by bumping `token`. Reduce Motion:
/// a brief static wash, no expansion.
struct TransformationBurst: View {
    var tier: AuraTier
    var token: Int

    @State private var flash: Double = 0
    @State private var ring: CGFloat = 0
    @State private var ringOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height)
            ZStack {
                RadialGradient(colors: [tier.secondary.opacity(flash),
                                        tier.color.opacity(flash * 0.5), .clear],
                               center: .center, startRadius: 0, endRadius: maxDim * 0.7)
                    .blendMode(.plusLighter)
                Circle()
                    .stroke(tier.secondary.opacity(ringOpacity), lineWidth: 3)
                    .frame(width: maxDim * ring, height: maxDim * ring)
                    .blur(radius: 1.5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: token) { _, _ in fire() }
    }

    private func fire() {
        if reduceMotion {
            flash = 0.35 * tier.intensity
            withAnimation(.easeOut(duration: 0.4)) { flash = 0 }
            return
        }
        flash = 0.55 * tier.intensity
        ring = 0.1
        ringOpacity = 0.9 * tier.intensity
        withAnimation(.easeOut(duration: 0.55)) { flash = 0 }
        withAnimation(.easeOut(duration: 0.7)) {
            ring = 1.3
            ringOpacity = 0
        }
    }
}

// MARK: - Realm doorway card (Home launch card + Train routine rows, ONE recipe)

/// A full-bleed chamber-realm image with a leading legibility gradient — the
/// "doorway" card Home's launch card, its first-run twin, and Train's routine
/// rows all hand-rolled separately. `emphasized` adds the cyan rim + corner-tick
/// reticle + a slow Ken-Burns drift and marks THE one next action (Home);
/// the quiet variant (white hairline, static art) is for list rows.
struct RealmDoorwayCard<Content: View, Accessory: View>: View {
    let asset: String
    var emphasized: Bool = false
    var height: CGFloat = 124
    @ViewBuilder var content: () -> Content
    @ViewBuilder var accessory: () -> Accessory

    @State private var drifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(asset)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(artScale)
            // Legibility: darker on the text side, easing to reveal the realm.
            LinearGradient(colors: [.black.opacity(0.84), .black.opacity(0.6), .black.opacity(0.28)],
                           startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 14) {
                content()
                Spacer(minLength: 8)
                accessory()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(emphasized ? AnyShapeStyle(SettColor.heroCyan.opacity(0.35))
                                         : AnyShapeStyle(.white.opacity(0.12)), lineWidth: 1)
        }
        .overlay {
            if emphasized {
                CornerTicksShape(length: 7, inset: 7)
                    .stroke(SettColor.heroCyan.opacity(0.55), lineWidth: 1.5)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .onAppear {
            guard emphasized && !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
    }

    /// Slow Ken-Burns breath on the emphasized doorway only (list rows stay static
    /// — a screenful of drifting rows would read as noise). Reduce Motion holds a
    /// fixed mid-drift scale so the crop matches without movement.
    private var artScale: CGFloat {
        guard emphasized else { return 1 }
        if reduceMotion { return 1.08 }
        return drifting ? 1.12 : 1.04
    }
}
