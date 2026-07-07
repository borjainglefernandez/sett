import SwiftUI
import UIKit

// MARK: - Palette
// Cyan = action & identity. Gold = earned. Crimson = Vexeth only.
// A screen never leads with both cyan and gold.

public enum SettColor {
    /// Hero cyan — v1's .systemCyan identity, kept.
    public static let heroCyan = Color(dynamicLight: 0x32ADE6, dark: 0x64D2FF)
    /// Saiyan gold — achievement/reward accent. Darkened in light mode for contrast.
    public static let saiyanGold = Color(dynamicLight: 0xC9930A, dark: 0xFFD60A)
    /// Villain crimson — reserved EXCLUSIVELY for Vexeth's rival card and form reveals.
    public static let villainCrimson = Color(dynamicLight: 0xD70015, dark: 0xFF453A)
    public static let villainVoid = Color(dynamicLight: 0x1C0D10, dark: 0x120A0C)

    public static let positive = Color(uiColor: .systemGreen)
    public static let negative = Color(uiColor: .systemRed)

    public static let card = Color(uiColor: .secondarySystemGroupedBackground)
    public static let cardNested = Color(uiColor: .tertiarySystemGroupedBackground)
    public static let screen = Color(uiColor: .systemGroupedBackground)
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
    }

    private var font: Font {
        switch size {
        case .xl: PowerFont.xl(xlSize)
        case .l: PowerFont.l(lSize)
        case .m: PowerFont.m(mSize)
        }
    }
}

// MARK: - Cards (radius 16 continuous — the squircle pill language)

public struct SettCardStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(16)
            .background(SettColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

public extension View {
    func settCard() -> some View { modifier(SettCardStyle()) }
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
