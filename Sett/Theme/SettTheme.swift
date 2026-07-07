import SwiftUI
import UIKit

// MARK: - Palette
// Dungeon rules: the app is one permanently dark world — near-black blue-charcoal
// stone, with the neon accents as the only light sources.
// Cyan = action & identity. Gold = earned. Crimson = Vexeth only.
// A screen never leads with both cyan and gold.

public enum SettColor {
    /// Hero cyan — v1's .systemCyan identity, kept. Now a glow source in the dark.
    public static let heroCyan = Color(dynamicLight: 0x64D2FF, dark: 0x64D2FF)
    /// Saiyan gold — achievement/reward accent.
    public static let saiyanGold = Color(dynamicLight: 0xFFD60A, dark: 0xFFD60A)
    /// Villain crimson — reserved EXCLUSIVELY for Vexeth's rival card and form reveals.
    public static let villainCrimson = Color(dynamicLight: 0xFF453A, dark: 0xFF453A)
    public static let villainVoid = Color(dynamicLight: 0x120A0C, dark: 0x120A0C)

    public static let positive = Color(uiColor: .systemGreen)
    public static let negative = Color(uiColor: .systemRed)

    /// Near-black blue-charcoal — the gravity-chamber floor.
    /// Both dynamic variants are dark on purpose: there is no light mode anymore,
    /// but the initializer is kept so every call site keeps compiling.
    public static let screen = Color(dynamicLight: 0x0A0D12, dark: 0x0A0D12)
    /// A raised stone slab.
    public static let card = Color(dynamicLight: 0x141A23, dark: 0x141A23)
    /// An inset carved into a slab.
    public static let cardNested = Color(dynamicLight: 0x1B2330, dark: 0x1B2330)
    /// Hairline slab edge — consumed at 60% opacity by `.settCard()`.
    public static let cardBorder = Color(dynamicLight: 0x2A3548, dark: 0x2A3548)
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
    public static let gold = LinearGradient(
        colors: [Color(dynamicLight: 0xFFE04B, dark: 0xFFE04B), Color(dynamicLight: 0xFF9F0A, dark: 0xFF9F0A)],
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

// MARK: - Aura glow (neon light in the dark — numerals, icons, scouter readouts)

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
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(value)))
            .auraGlow(color, radius: glowRadius)
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

// MARK: - Cards (radius 16 continuous — the squircle pill language, now edged stone)

public struct SettCardStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape
                    .fill(SettColor.card)
                    .overlay {
                        // Faint torchlight catching the top edge of the slab.
                        shape.fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.04), location: 0),
                                    .init(color: .clear, location: 0.28),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .overlay {
                        shape.strokeBorder(SettColor.cardBorder.opacity(0.6), lineWidth: 1)
                    }
            }
    }
}

public extension View {
    func settCard() -> some View { modifier(SettCardStyle()) }
}

// MARK: - Dungeon background (gravity-chamber murk: glow bleed + stone grain)

/// Full-bleed screen backdrop: near-black stone, a faint cyan glow bleeding from
/// the top-leading corner, a fainter gold ember bottom-trailing, and a static
/// grain of ~1200 seeded specks. Drawn once — no TimelineView, nothing animates,
/// so Reduce Motion needs no special-casing.
public struct DungeonBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            SettColor.screen
            RadialGradient(
                colors: [SettColor.heroCyan.opacity(0.06), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [SettColor.saiyanGold.opacity(0.04), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
            grain
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Deterministic noise: seeded LCG, never Date or SystemRandom — the texture
    /// is identical every launch and never invalidates.
    private var grain: some View {
        Canvas { context, size in
            var rng = LCG(seed: 0x5E77_0DD5)
            context.opacity = 0.025
            for _ in 0 ..< 1200 {
                let x = rng.nextUnit() * size.width
                let y = rng.nextUnit() * size.height
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white)
                )
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
    /// want the full dungeon treatment (glow bleed + grain).
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
