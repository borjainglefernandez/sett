import SwiftUI
import Charts
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
    /// One knob so screens needing tighter insets stop re-implementing the groove.
    var padding: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .padding(padding)
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
    func settCard(padding: CGFloat = 16) -> some View { modifier(SettCardStyle(padding: padding)) }
    /// The in-card nested slab (rows inside a settCard/hudCard): cardNested fill +
    /// cardBorder hairline. ONE recipe so editors stop inventing slab variants.
    func nestedSlab(radius: CGFloat = 10) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(SettColor.cardNested)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(SettColor.cardBorder, lineWidth: 1)
                }
        }
    }
    /// The System Voice entrance (opacity + blur(6) + scale(1.04) assembling over
    /// 0.3s) as ONE modifier — extracted from SystemMessageView/BurstReadyButton so
    /// set-piece cards materialize instead of popping. Plain fade under Reduce Motion.
    func materialize() -> some View { modifier(MaterializeOnAppear()) }
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
                    withAnimation(.snappy(duration: 0.15)) { selection = option.value }
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

/// Rest-timer tuning — ONE source so Settings, the routine editor, and the in-session
/// ±buttons all step by the same amount over the same range (they had drifted to 5s in
/// Settings but 15s in the routine editor, with different floors/ceilings).
public enum RestTuning {
    public static let step = 5
    public static let range = 15...600
}

/// Set-count tuning — ONE source for the planned-set clamp and the default count, so
/// the routine editor's ± stepper and every "new exercise gets N sets" seed agree.
public enum SetTuning {
    public static let range = 1...10
    public static let defaultCount = 3
}

/// The mid-flow sheet shell. Every quick sheet the session or home presents (numeric
/// pad, note, fix-set, machine setup, bodyweight) wears this instead of stock iOS nav
/// chrome: a mono kerned title row flanked by a ghost CANCEL and a cyan commit capsule,
/// content below, the chamber behind. Tapping a scouter numeral no longer cuts to
/// another operating system.
public struct ChamberSheet<Content: View>: View {
    let title: String
    var commitLabel: String
    var canCommit: Bool
    let onCommit: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    public init(title: String, commitLabel: String = "SAVE", canCommit: Bool = true,
                onCommit: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.commitLabel = commitLabel
        self.canCommit = canCommit
        self.onCommit = onCommit
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("CANCEL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.ash)
                        .frame(minWidth: 64, minHeight: 44)
                        .background { Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(SettColor.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button {
                    Haptics.success()
                    onCommit()
                    dismiss()
                } label: {
                    Text(commitLabel.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .kerning(1)
                        .foregroundStyle(SettColor.etch)
                        .frame(minWidth: 64, minHeight: 44)
                        .background(SettColor.heroCyan.opacity(canCommit ? 1 : 0.35), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { DungeonBackground().ignoresSafeArea() }
    }
}

/// The app's ± stepper grammar (the session's flanking micro-steppers) as a standalone
/// control — replaces stock `Stepper` inside themed sheets.
public struct ChamberStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1

    public init(value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) {
        self._value = value
        self.range = range
        self.step = step
    }

    public var body: some View {
        HStack(spacing: 14) {
            flank("minus") { value = max(range.lowerBound, value - step) }
            Text("\(value)")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
                .frame(minWidth: 44)
                .contentTransition(.numericText(value: Double(value)))
            flank("plus") { value = min(range.upperBound, value + step) }
        }
    }

    private func flank(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            let before = value
            withAnimation(.snappy(duration: 0.15)) { action() }
            if value != before { Haptics.selection() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 34, height: 34)
                .background { Circle().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increment" : "Decrement")
    }
}

/// One axis voice for every chart — mono ash labels on iron hairlines, so Swift
/// Charts stops shipping its stock chrome into the chamber.
public struct ScouterChartStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(SettColor.iron.opacity(0.35))
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(SettColor.iron.opacity(0.35))
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettColor.ash)
                }
            }
    }
}

public extension View {
    func scouterChart() -> some View { modifier(ScouterChartStyle()) }
}

/// The themed empty state — replaces stock `ContentUnavailableView` so an empty screen
/// still lives in the chamber: a quiet sigil, a mono title, ash body, optional cyan CTA.
public struct EmptyChamber<Actions: View>: View {
    let title: String
    var message: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    /// Compact = in-card empty states (tighter padding, smaller sigil) so screens
    /// stop rolling bespoke empty cards just to fit inside a settCard.
    var compact: Bool = false
    /// Custom action slot for CTAs a closure can't express (NavigationLink,
    /// ChamberCTAButton) — previously forced consumers to duplicate the CTA outside.
    @ViewBuilder var actions: () -> Actions

    public init(title: String, message: String? = nil, compact: Bool = false,
                @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.message = message
        self.compact = compact
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Prose combines into one VO element; the CTAs below stay interactive.
            VStack(spacing: 10) {
                SettSigil(size: compact ? 22 : 30, color: SettColor.ash.opacity(0.7))
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
            }
            .accessibilityElement(children: .combine)
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
            actions()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 14 : 40)
    }
}

public extension EmptyChamber where Actions == EmptyView {
    /// The original closure-CTA form — every existing call site keeps compiling.
    init(title: String, message: String? = nil,
         actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
        self.actions = { EmptyView() }
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

// MARK: - Materialize (the System Voice entrance, shared)

/// Opacity + blur(6) + scale(1.04) assembling over 0.3s easeOut on first appearance
/// — the entrance grammar SystemMessageView and BurstReadyButton established, now
/// available to any set-piece card. Reduce Motion collapses to a plain fade.
struct MaterializeOnAppear: ViewModifier {
    @State private var materialized = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(materialized ? 1 : 0)
            .blur(radius: materialized || reduceMotion ? 0 : 6)
            .scaleEffect(materialized || reduceMotion ? 1 : 1.04)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { materialized = true }
            }
    }
}

// MARK: - Pressable slab (the session's press-in physicality, app-wide)

/// The card/CTA presses IN (0.97) with a synchronous haptic on touch-down — the
/// "charge" before the action fires on touch-up (commit latency untouched).
/// Promoted from the Set Player so the launch card / GO / CLAIM / primary CTAs
/// share the session's physicality. `haptic: nil` for silent presses.
public struct PressableSlabStyle: ButtonStyle {
    public enum PressHaptic { case rigid, light }
    var enabled: Bool = true
    var haptic: PressHaptic? = .rigid

    public init(enabled: Bool = true, haptic: PressHaptic? = .rigid) {
        self.enabled = enabled
        self.haptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed && enabled, let haptic else { return }
                switch haptic {
                case .rigid: Haptics.rigid()
                case .light: Haptics.light()
                }
            }
    }
}

// MARK: - ChamberCTA (the ONE full-width primary action button)

/// The canonical primary CTA: mono uppercase kerned label, etch ink on a flat
/// heroCyan capsule, full width, pressable. Disabled = cardNested fill + iron ink.
/// Replaces the stock bordered buttons and the sentence-case gradient capsules.
public struct ChamberCTAButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    public init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(enabled ? SettColor.etch : SettColor.iron)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(enabled ? AnyShapeStyle(SettColor.heroCyan)
                                    : AnyShapeStyle(SettColor.cardNested), in: Capsule())
                .overlay {
                    if !enabled { Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableSlabStyle(enabled: enabled, haptic: .light))
        .disabled(!enabled)
    }
}

// MARK: - FilterChip (the ONE scrollable filter-row chip)

/// The History/ChamberSegments chip grammar as a shared control: mono uppercase,
/// active = heroCyan fill with etch ink, inactive = ghost stroke with ash ink.
public struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    public init(_ label: String, active: Bool, action: @escaping () -> Void) {
        self.label = label
        self.active = active
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(active ? SettColor.etch : SettColor.ash)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background {
                    if active {
                        Capsule().fill(SettColor.heroCyan)
                    } else {
                        Capsule().strokeBorder(SettColor.cardBorder, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - CardTitle (the ONE card headline)

/// Card headline: title3 semibold with an optional trailing accessory glyph —
/// the treatment the Progress cards established, now shared so titles stop
/// drifting between .headline Labels and bespoke rows.
public struct CardTitle: View {
    let title: String
    var icon: String? = nil
    var iconTint: Color = SettColor.heroCyan

    public init(_ title: String, icon: String? = nil, iconTint: Color = SettColor.heroCyan) {
        self.title = title
        self.icon = icon
        self.iconTint = iconTint
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SettColor.bone)
            Spacer()
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(iconTint)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - ChamberStepControl (closure-driven ± for non-Int values)

/// ChamberStepper's flank grammar for values that aren't a plain Int binding
/// (formatted weights, settings-dependent increments): the caller renders the
/// text and owns clamping; the control provides the ± flanks + haptics.
public struct ChamberStepControl: View {
    let text: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    public init(text: String, onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) {
        self.text = text
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    public var body: some View {
        HStack(spacing: 14) {
            flank("minus", action: onDecrement)
            Text(text)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(SettColor.bone)
                .frame(minWidth: 44)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            flank("plus", action: onIncrement)
        }
    }

    private func flank(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { action() }
            Haptics.selection()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SettColor.heroCyan)
                .frame(width: 34, height: 34)
                .background { Circle().strokeBorder(SettColor.heroCyan.opacity(0.4), lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increment" : "Decrement")
    }
}

// MARK: - StatusChip (the ONE small status pill)

/// The status-pill family (CASUAL, SURGE ARMED, NEXT UP, rarity…) as one voice:
/// mono uppercase kerned capsule. Ghost by default (tinted ink on a 12% tint
/// wash); `filled` inverts to etch ink on a solid tint fill for the highlighted
/// state (NEXT UP).
public struct StatusChip: View {
    let label: String
    var tint: Color = SettColor.ash
    var icon: String? = nil
    var filled: Bool = false

    public init(_ label: String, tint: Color = SettColor.ash,
                icon: String? = nil, filled: Bool = false) {
        self.label = label
        self.tint = tint
        self.icon = icon
        self.filled = filled
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(label.uppercased())
                .kerning(1)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(filled ? SettColor.etch : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            if filled {
                Capsule().fill(tint)
            } else {
                Capsule().fill(tint.opacity(0.12))
                Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityLabel(label)
    }
}
