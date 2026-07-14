import SwiftUI
import UIKit

// MARK: - Palette (the Dark Chamber, design language v3)
// One permanently dark world — warm near-black stone lit from the center.
// Gold belongs to the power level EXCLUSIVELY. Cyan is ki — energy, gauges,
// action. Crimson is Vexeth only. A screen never leads with both cyan and gold.

public enum SettColor {
    /// Ki cyan — v1's .systemCyan identity, kept. Energy, gauges, active states.
    public static let heroCyan = Color(dynamicLight: 0x64D2FF, dark: 0x64D2FF)
    /// Sacred gold — the power level's hue and nothing else's.
    public static let saiyanGold = Color(dynamicLight: 0xFFD60A, dark: 0xFFD60A)
    /// Villain crimson — reserved EXCLUSIVELY for Vexeth's rival card and form reveals.
    public static let villainCrimson = Color(dynamicLight: 0xFF453A, dark: 0xFF453A)
    public static let villainVoid = Color(dynamicLight: 0x120A0C, dark: 0x120A0C)

    public static let positive = Color(uiColor: .systemGreen)
    public static let negative = Color(uiColor: .systemRed)

    /// Warm near-black — the chamber floor. Never #000; flat black halates.
    /// Both dynamic variants are dark on purpose: there is no light mode anymore,
    /// but the initializer is kept so every call site keeps compiling.
    public static let screen = Color(dynamicLight: 0x0B0908, dark: 0x0B0908)
    /// A raised stone slab.
    public static let card = Color(dynamicLight: 0x151110, dark: 0x151110)
    /// An inset carved into a slab.
    public static let cardNested = Color(dynamicLight: 0x1C1714, dark: 0x1C1714)
    /// Hairline slab edge — the "iron" frame material.
    public static let cardBorder = Color(dynamicLight: 0x2E2620, dark: 0x2E2620)

    // Text ramp — never pure white on near-black (astigmatism halation).
    /// Primary text.
    public static let bone = Color(dynamicLight: 0xE8E1D0, dark: 0xE8E1D0)
    /// Secondary text.
    public static let ash = Color(dynamicLight: 0x9B948A, dark: 0x9B948A)
    /// Tertiary text / ghost values. Lifted from 0x5C564E (~2.8:1 on the void, failing
    /// WCAG AA for the functional text it carries — units, PLANNED, planned numerals) to
    /// ~4:1 while staying clearly below `ash`, so the tertiary hierarchy is preserved.
    public static let iron = Color(dynamicLight: 0x776F63, dark: 0x776F63)

    /// The engraved-groove near-black — outer strokes and numeral outlines.
    public static let etch = Color(dynamicLight: 0x050403, dark: 0x050403)
}

public extension Color {
    init(dynamicLight light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Aura gradients

public enum Aura {
    public static let cyan = LinearGradient(
        colors: [Color(dynamicLight: 0x64D2FF, dark: 0x64D2FF), Color(dynamicLight: 0x0A84FF, dark: 0x0A84FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// The sacred gradient — #FFD60A → #FF9F0A, power level only.
    public static let gold = LinearGradient(
        colors: [Color(dynamicLight: 0xFFD60A, dark: 0xFFD60A), Color(dynamicLight: 0xFF9F0A, dark: 0xFF9F0A)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Zenith only — scarcity is the point.
    public static let zenith = LinearGradient(
        colors: [.white, Color(dynamicLight: 0x64D2FF, dark: 0x64D2FF)],
        startPoint: .top, endPoint: .bottom
    )
    /// Vexeth only.
    public static let villain = LinearGradient(
        colors: [SettColor.villainCrimson, SettColor.villainVoid],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    public static func forTier(_ tier: Int) -> LinearGradient {
        switch tier {
        case 0, 1, 2: cyan
        case 3: gold
        default: zenith
        }
    }
}

// MARK: - Aura glow (light sources in the dark — numerals, icons, scouter readouts)

public struct AuraGlowStyle: ViewModifier {
    let color: Color
    let radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.55), radius: radius)
            .shadow(color: color.opacity(0.35), radius: radius * 0.35)
    }
}

public extension View {
    /// Neon bloom for accent content: a wide soft shadow plus a tighter hot core.
    /// Gold glows gold, cyan glows cyan. Static — nothing animates.
    func auraGlow(_ color: Color, radius: CGFloat = 12) -> some View {
        modifier(AuraGlowStyle(color: color, radius: radius))
    }
}

// MARK: - Power numerals (the ONLY fixed type sizes in the app; everything else is Dynamic Type)

public enum PowerFont {
    public static func xl(_ scaled: CGFloat = 56) -> Font {
        .system(size: scaled, weight: .heavy, design: .rounded)
    }
    public static func l(_ scaled: CGFloat = 34) -> Font {
        .system(size: scaled, weight: .heavy, design: .rounded)
    }
    public static func m(_ scaled: CGFloat = 22) -> Font {
        .system(size: scaled, weight: .bold, design: .rounded)
    }
}

/// The sacred numeral cut: ultra-heavy rounded tabular digits, sheared via
/// italic (approximating the spec's 10° shear), gradient fill with a hard
/// near-black outline so it reads engraved, not printed. Gold by default —
/// used for the power level and nothing else. Other hues (Vexeth's crimson)
/// pass an explicit `color`.
public struct PowerNumeral: View {
    public enum Size { case xl, l, m }
    let value: Int
    let size: Size
    let color: Color

    @ScaledMetric(relativeTo: .largeTitle) private var xlSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var lSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title2) private var mSize: CGFloat = 22

    public init(_ value: Int, size: Size = .l, color: Color = SettColor.saiyanGold) {
        self.value = value
        self.size = size
        self.color = color
    }

    public var body: some View {
        Text("\(value)")
            .font(font.italic())
            .monospacedDigit()
            .foregroundStyle(fill)
            .contentTransition(.numericText(value: Double(value)))
            // Hard dark outline: two zero-radius shadows, opposite x offsets.
            .shadow(color: SettColor.etch, radius: 0, x: 1, y: 1)
            .shadow(color: SettColor.etch, radius: 0, x: -1, y: 1)
            .auraGlow(color, radius: glowRadius)
    }

    private var fill: LinearGradient {
        // The default (sacred gold) gets the canonical #FFD60A → #FF9F0A ramp;
        // explicit colors get a subtle top-lit ramp of themselves.
        if color == SettColor.saiyanGold {
            return Aura.gold
        }
        return LinearGradient(
            colors: [color, color.opacity(0.72)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var font: Font {
        switch size {
        case .xl: PowerFont.xl(xlSize)
        case .l: PowerFont.l(lSize)
        case .m: PowerFont.m(mSize)
        }
    }

    private var glowRadius: CGFloat {
        switch size {
        case .xl: 14
        case .l: 12
        case .m: 8
        }
    }
}

// MARK: - Cards (radius 16 continuous — etched dual-stroke slabs, v3)

/// The etched slab: card fill, a 1px near-black OUTER stroke and a 1px
/// 20%-gold INNER stroke inset 1.5pt (together reading as an engraved groove),
/// plus 5pt L-shaped corner ticks at 25% gold. No shadows, no glass.
public struct SettCardStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape
                    .fill(SettColor.card)
                    .overlay {
                        // Outer groove wall — near-black.
                        shape.strokeBorder(SettColor.etch, lineWidth: 1)
                    }
                    .overlay {
                        // Inner groove floor — faint gold catching torchlight.
                        RoundedRectangle(cornerRadius: 14.5, style: .continuous)
                            .strokeBorder(SettColor.saiyanGold.opacity(0.2), lineWidth: 1)
                            .padding(1.5)
                    }
                    .overlay {
                        CornerTicksShape(length: 5, inset: 4)
                            .stroke(SettColor.saiyanGold.opacity(0.25), lineWidth: 1)
                    }
            }
    }
}

/// Four L-shaped corner ticks — the forged-corner detail on every slab.
public struct CornerTicksShape: Shape {
    var length: CGFloat = 5
    var inset: CGFloat = 4

    public init(length: CGFloat = 5, inset: CGFloat = 4) {
        self.length = length
        self.inset = inset
    }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length
        let i = inset
        // Top-leading
        p.move(to: CGPoint(x: rect.minX + i, y: rect.minY + i + l))
        p.addLine(to: CGPoint(x: rect.minX + i, y: rect.minY + i))
        p.addLine(to: CGPoint(x: rect.minX + i + l, y: rect.minY + i))
        // Top-trailing
        p.move(to: CGPoint(x: rect.maxX - i - l, y: rect.minY + i))
        p.addLine(to: CGPoint(x: rect.maxX - i, y: rect.minY + i))
        p.addLine(to: CGPoint(x: rect.maxX - i, y: rect.minY + i + l))
        // Bottom-trailing
        p.move(to: CGPoint(x: rect.maxX - i, y: rect.maxY - i - l))
        p.addLine(to: CGPoint(x: rect.maxX - i, y: rect.maxY - i))
        p.addLine(to: CGPoint(x: rect.maxX - i - l, y: rect.maxY - i))
        // Bottom-leading
        p.move(to: CGPoint(x: rect.minX + i + l, y: rect.maxY - i))
        p.addLine(to: CGPoint(x: rect.minX + i, y: rect.maxY - i))
        p.addLine(to: CGPoint(x: rect.minX + i, y: rect.maxY - i - l))
        return p
    }
}

/// The scouter HUD slab — the exercise cards' void-glass + tinted rim + corner
/// reticle, extracted so Home's cards can wear the same chrome as the session.
/// (`settCard` stays the warm stone/gold-groove look for parchment-y content.)
public struct HUDCardStyle: ViewModifier {
    var tint: Color = SettColor.heroCyan

    public func body(content: Content) -> some View {
        content
            .padding(14)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape.fill(TimeChamber.void.opacity(0.72))
                shape.strokeBorder(tint.opacity(0.28), lineWidth: 1)
                CornerTicksShape(length: 6, inset: 7)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            }
    }
}

public extension View {
    func settCard() -> some View { modifier(SettCardStyle()) }
    func hudCard(tint: Color = SettColor.heroCyan) -> some View {
        modifier(HUDCardStyle(tint: tint))
    }
}

// MARK: - Shared vocabulary (one source for the marks every screen kept re-rolling)

/// The mono kerned section label — the app's most-copied five lines, now one view.
/// INK RULE (documented here because this is the vocabulary file): text sitting ON a
/// heroCyan fill is always `SettColor.etch` — never white, never black.
public struct Eyebrow: View {
    let text: String
    var tint: Color

    public init(_ text: String, tint: Color = SettColor.ash) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .kerning(1.5)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The themed segmented control (extracted from Progress's period picker) — replaces
/// every stock white `.pickerStyle(.segmented)`, which was the single most repeated
/// off-world element. Mono uppercase, selected = cyan capsule with etch ink.
public struct ChamberSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    /// Compact = shorter capsules for secondary controls (e.g. schedule mode).
    var compact: Bool = false

    public init(selection: Binding<Value>, options: [(value: Value, label: String)],
                compact: Bool = false) {
        self._selection = selection
        self.options = options
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                    Haptics.selection()
                } label: {
                    Text(option.label.uppercased())
                        .font(.system(size: compact ? 10 : 11, weight: .bold, design: .monospaced))
                        .kerning(compact ? 1 : 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selection == option.value ? SettColor.etch : SettColor.ash)
                        .frame(maxWidth: .infinity, minHeight: compact ? 28 : 34)
                        .background {
                            if selection == option.value {
                                Capsule().fill(SettColor.heroCyan)
                            } else {
                                Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selection == option.value ? [.isSelected] : [])
            }
        }
    }
}

/// The themed empty state — replaces stock `ContentUnavailableView` so an empty screen
/// still lives in the chamber: a quiet sigil, a mono title, ash body, optional cyan CTA.
public struct EmptyChamber: View {
    let title: String
    var message: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    public init(title: String, message: String? = nil,
                actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            SettSigil(size: 30, color: SettColor.ash.opacity(0.7))
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(SettColor.ash.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.etch)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(SettColor.heroCyan, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dungeon background (torchlit-center architecture: vignette + grime)

/// Full-bleed screen backdrop, v3: warm near-black stone, a radial VIGNETTE
/// (clear center → 50% black corners — the torchlit-center dungeon rule; the
/// brightest zone is where the sacred number sits), and blotchy directional
/// grime — seeded points clustered into ~40 patches with a slight diagonal
/// drift, 3–6% luminance variation. Drawn once — no TimelineView, nothing
/// animates, so Reduce Motion needs no special-casing.
public struct DungeonBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            SettColor.screen
            grime
            vignette
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var vignette: some View {
        GeometryReader { geo in
            RadialGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.5), location: 1),
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(geo.size.width, geo.size.height)
            )
        }
        .allowsHitTesting(false)
    }

    /// Deterministic grime: seeded LCG, never Date or SystemRandom — the
    /// texture is identical every launch and never invalidates. ~40 blotches
    /// of 10–40 specks each, drifting down-and-right like water-stained iron.
    private var grime: some View {
        Canvas { context, size in
            var rng = LCG(seed: 0x5E77_0DD5)
            for patch in 0 ..< 40 {
                var x = rng.nextUnit() * size.width
                var y = rng.nextUnit() * size.height
                let count = 10 + Int(rng.nextUnit() * 30)
                // Slight diagonal drift, per patch.
                let driftX = 0.8 + rng.nextUnit() * 1.6
                let driftY = 0.8 + rng.nextUnit() * 1.6
                // 3–6% luminance variation; alternate light and dark stains.
                let luminance = 0.03 + rng.nextUnit() * 0.03
                let shade: Color = patch.isMultiple(of: 2) ? .white : .black
                for _ in 0 ..< count {
                    x += driftX + (rng.nextUnit() - 0.35) * 5
                    y += driftY + (rng.nextUnit() - 0.35) * 5
                    let speck = 1 + rng.nextUnit() * 1.6
                    context.fill(
                        Path(CGRect(x: x, y: y, width: speck, height: speck)),
                        with: .color(shade.opacity(luminance))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Minimal linear congruential generator (Knuth MMIX constants).
    private struct LCG {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func nextUnit() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(state >> 11) / CGFloat(UInt64(1) << 53)
        }
    }
}

public extension View {
    /// Drop-in replacement for `.background(SettColor.screen)` on screens that
    /// want the full chamber treatment (vignette + grime).
    func dungeonBackground() -> some View {
        background(DungeonBackground())
    }
}

// MARK: - Haptics (one vocabulary; nobody instantiates generators inline)

@MainActor
public enum Haptics {
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    public static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    public static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    public static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    public static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    /// The double-pulse PR signature.
    public static func prSignature() {
        success()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }
    /// Level-up / transformation.
    public static func levelUp() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            success()
        }
    }
}
