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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Canvas { context, size in
                for track in Self.tracks.prefix(28) {
                    let x = track.x * size.width
                    let y = track.baseY * size.height
                    let d = track.size
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)),
                                 with: .color(tint(track).opacity(0.30)))
                }
            }
            .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    context.blendMode = .plusLighter
                    let count = 14 + Int(16 * tier.intensity)
                    for track in Self.tracks.prefix(count) {
                        let cycle = t / track.period + track.phase
                        let progress = cycle - cycle.rounded(.down)   // 0→1 rise
                        let fade = sin(progress * .pi)
                        let x = track.x * size.width
                            + sin(t * track.wanderFreq + track.phase * 11) * track.wander
                        let y = size.height * (1.02 - progress * 1.04)
                        let d = track.size * (0.8 + 0.5 * tier.intensity)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                            with: .color(tint(track).opacity(fade * 0.5 * (0.5 + tier.intensity / 2)))
                        )
                    }
                }
                .allowsHitTesting(false)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Outer bloom (brightens on both inhale + burst).
            Circle()
                .stroke(tier.color.opacity(0.24 * tier.intensity), lineWidth: 14 + abs(flare) * 22)
                .blur(radius: 16 + flare * 14)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 1.015 : 0.985))
            // Steady base ring.
            Circle().stroke(tier.color.opacity(0.45), lineWidth: 1.5)
            // Energy arcs — same wrap-safe angle, differing direction/trim/width.
            arc(trim: 0.55, width: 3.0).rotationEffect(.degrees(spinA ? 360 : 0))
            arc(trim: 0.14, width: 4.0).rotationEffect(.degrees(spinA ? 360 : 0)).blur(radius: 1)
            arc(trim: 0.30, width: 2.0).rotationEffect(.degrees(spinB ? -360 : 0))
        }
        .scaleEffect(1 + flare * 0.10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: startSpin)
        .onChange(of: tier) { _, _ in startSpin() }
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
    /// True when the live reading has crossed the ceiling — flips LOCK→PEAK and
    /// holds the indicator solid (the scouter has locked onto a record).
    var atCeiling: Bool = false

    @State private var flare: CGFloat = 0
    @State private var scanDrift: CGFloat = 0   // scan-line drift (0→1, wraps seamlessly)
    @State private var sweepPhase: CGFloat = 0  // the sweep bar's travel (0→1)
    @State private var blink = false            // lock indicator pulse
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = ScouterLensShape()
        ZStack {
            // Soft aura bloom behind the whole lens (brightens on both inhale + burst).
            shape.fill(tier.color.opacity(0.16 * tier.intensity + Double(abs(flare)) * 0.25))
                .blur(radius: 26)
                .scaleEffect(1.06 + flare * 0.06)

            // Glass: dark core (legibility) warming to the scouter hue at the edges.
            shape.fill(
                RadialGradient(
                    colors: [TimeChamber.void.opacity(0.82),
                             TimeChamber.void.opacity(0.5),
                             tier.color.opacity(0.18)],
                    center: .center, startRadius: 6, endRadius: 240
                )
            )

            ZStack {
                scanLines
                sweepBar
            }
            .clipShape(shape)
            GeometryReader { geo in tickStrip(in: geo.size) }.clipShape(shape)
            targetBrackets
            lockIndicator

            // Rim — bright scouter hue, glowing, with an inner hairline.
            shape.stroke(tier.gradient, style: StrokeStyle(lineWidth: 2.5 + abs(flare) * 2, lineJoin: .round))
                .shadow(color: tier.color.opacity(0.7), radius: 8 + abs(flare) * 10)
            shape.stroke(tier.color.opacity(0.35), lineWidth: 1).padding(5)

            emitter
        }
        .scaleEffect(1 + flare * 0.03)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: startScan)
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

    private func startScan() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) { scanDrift = 1 }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { sweepPhase = 1 }
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { blink = true }
    }

    /// Faint horizontal scan lines drifting slowly upward (seamless wrap).
    private var scanLines: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let spacing: CGFloat = 13
            let count = Int(h / spacing) + 2
            ForEach(0 ..< count, id: \.self) { i in
                Rectangle()
                    .fill(tier.color.opacity(0.10))
                    .frame(height: 1)
                    .offset(y: CGFloat(i) * spacing - spacing + scanDrift * spacing)
            }
        }
    }

    /// A bright bar sweeping down the lens — the scanner reading the target.
    private var sweepBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, tier.secondary.opacity(0.55), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .shadow(color: tier.color.opacity(0.8), radius: 6)
                .offset(y: (reduceMotion ? 0.5 : sweepPhase) * (geo.size.height - 2))
        }
    }

    /// Live power gauge along the bottom inner edge — the scouter scale. Ticks light
    /// left→right to `charge`; a taller notch marks the ceiling (prior best), so you
    /// watch the reading march toward it and, on a PR, sweep visibly past. Pure state.
    private func tickStrip(in size: CGSize) -> some View {
        let ceilingIndex = ceilingFrac >= 0 ? min(17, max(0, Int((ceilingFrac * 17).rounded()))) : -1
        return HStack(spacing: 5) {
            ForEach(0 ..< 18, id: \.self) { i in
                let lit = Double(i) / 17 <= charge
                let isCeiling = i == ceilingIndex
                Rectangle()
                    .fill(isCeiling ? tier.secondary : tier.color.opacity(lit ? 0.9 : 0.16))
                    .frame(width: isCeiling ? 2 : 1.5,
                           height: isCeiling ? 11 : (lit ? 8 : 4))
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
                    .opacity(atCeiling ? 1 : (reduceMotion ? 1 : (blink ? 1 : 0.25)))
                Text(atCeiling ? "PEAK" : "LOCK")
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
