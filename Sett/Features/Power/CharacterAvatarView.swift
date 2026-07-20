import SwiftUI
import SettCore

enum CharacterIconMotif {
    case ember
    case endlessWell
    case mountain
    case shield
    case scar
    case data
    case momentum
}

struct CharacterIconTheme {
    let primary: Color
    let highlight: Color
    let accent: Color
    let motif: CharacterIconMotif
}

private struct ActiveSettCharacterKey: EnvironmentKey {
    static let defaultValue: CharacterKey = .vego
}

extension EnvironmentValues {
    var activeSettCharacter: CharacterKey {
        get { self[ActiveSettCharacterKey.self] }
        set { self[ActiveSettCharacterKey.self] = newValue }
    }
}

/// The tier → frame-material mapping of the v3 rarity ladder, shared by the
/// Power tab's hero card and the avatar rings: rank escalates through material
/// only — matte iron, brushed steel, engraved gold, animated prismatic.
extension TransformationTier {
    var frameMaterial: FrameMaterial {
        switch self {
        case .base, .kindled: .iron
        case .ascendant: .steel
        case .radiant: .gold
        case .zenith: .prismatic
        }
    }
}

extension CharacterKey {
    var iconTheme: CharacterIconTheme {
        switch self {
        case .vego:
            CharacterIconTheme(
                primary: Color(dynamicLight: 0x00DCF2, dark: 0x00DCF2),
                highlight: Color(dynamicLight: 0xB8FAFF, dark: 0xB8FAFF),
                accent: Color(dynamicLight: 0xFFB01A, dark: 0xFFB01A),
                motif: .ember
            )
        case .gosi:
            CharacterIconTheme(
                primary: Color(dynamicLight: 0x00E6F0, dark: 0x00E6F0),
                highlight: Color(dynamicLight: 0xC4FFFF, dark: 0xC4FFFF),
                accent: Color(dynamicLight: 0xFFB82A, dark: 0xFFB82A),
                motif: .endlessWell
            )
        case .barok:
            CharacterIconTheme(
                primary: Color(dynamicLight: 0x55D8FF, dark: 0x55D8FF),
                highlight: Color(dynamicLight: 0xE8FBFF, dark: 0xE8FBFF),
                accent: Color(dynamicLight: 0xFF9F12, dark: 0xFF9F12),
                motif: .mountain
            )
        case .nyra:
            CharacterIconTheme(
                primary: Color(dynamicLight: 0x23C8F5, dark: 0x23C8F5),
                highlight: Color(dynamicLight: 0xB6F0FF, dark: 0xB6F0FF),
                accent: Color(dynamicLight: 0xFFD048, dark: 0xFFD048),
                motif: .shield
            )
        case .torren:
            CharacterIconTheme(
                primary: Color(dynamicLight: 0x329EF5, dark: 0x329EF5),
                highlight: Color(dynamicLight: 0xC2E6FF, dark: 0xC2E6FF),
                accent: Color(dynamicLight: 0xFFB820, dark: 0xFFB820),
                motif: .scar
            )
        case .zia:
            CharacterIconTheme(
                primary: Color(dynamicLight: 0x00E5DB, dark: 0x00E5DB),
                highlight: Color(dynamicLight: 0xC5FFFC, dark: 0xC5FFFC),
                accent: Color(dynamicLight: 0xFFC83A, dark: 0xFFC83A),
                motif: .data
            )
        case .zyn:
            CharacterIconTheme(
                primary: Color(dynamicLight: 0x16B4EA, dark: 0x16B4EA),
                highlight: Color(dynamicLight: 0xA4E9FF, dark: 0xA4E9FF),
                accent: Color(dynamicLight: 0xFFB326, dark: 0xFFB326),
                motif: .momentum
            )
        }
    }

    var portraitAssetName: String {
        switch self {
        case .vego: "CharacterVego"
        case .gosi: "CharacterGosi"
        case .barok: "CharacterBarok"
        case .nyra: "CharacterNyra"
        case .torren: "CharacterTorren"
        case .zia: "CharacterZia"
        case .zyn: "CharacterZyn"
        }
    }
}

/// Small character signature laid over every movement and muscle medallion.
/// The center remains free for the exercise art; identity lives in the rim.
struct CharacterIconMotifRing: View {
    let theme: CharacterIconTheme

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let unit = side / 24
            let rect = CGRect(x: (size.width - side) / 2,
                              y: (size.height - side) / 2,
                              width: side, height: side)

            func pixel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1,
                       color: Color? = nil) {
                context.fill(Path(CGRect(x: rect.minX + x * unit,
                                         y: rect.minY + y * unit,
                                         width: w * unit,
                                         height: h * unit)),
                             with: .color(color ?? theme.primary))
            }

            switch theme.motif {
            case .ember:
                pixel(4, 3, 2, 4)
                pixel(6, 1, 2, 3, color: theme.highlight)
                pixel(17, 17, 2, 4)
                pixel(19, 15, 1, 3, color: theme.accent)
            case .endlessWell:
                context.stroke(Path(ellipseIn: rect.insetBy(dx: unit * 2.2, dy: unit * 2.2)),
                               with: .color(theme.primary.opacity(0.8)),
                               style: StrokeStyle(lineWidth: max(1, unit * 1.1), dash: [unit * 3, unit * 2]))
                for point in [(10, 1), (14, 1), (21, 10), (21, 14), (10, 21), (2, 10)] {
                    pixel(CGFloat(point.0), CGFloat(point.1), 2, 2, color: theme.accent)
                }
            case .mountain:
                var left = Path()
                left.move(to: CGPoint(x: rect.minX + unit, y: rect.maxY - unit * 3))
                left.addLine(to: CGPoint(x: rect.minX + unit * 5, y: rect.maxY - unit * 8))
                left.addLine(to: CGPoint(x: rect.minX + unit * 8, y: rect.maxY - unit * 2))
                left.closeSubpath()
                context.fill(left, with: .color(theme.primary.opacity(0.9)))
                pixel(18, 3, 2, 2, color: theme.highlight)
                pixel(20, 6, 1, 3, color: theme.accent)
            case .shield:
                pixel(2, 5, 2, 13)
                pixel(20, 5, 2, 13)
                pixel(4, 3, 4, 2, color: theme.highlight)
                pixel(16, 3, 4, 2, color: theme.highlight)
                pixel(11, 20, 2, 2, color: theme.accent)
            case .scar:
                for index in 0..<6 {
                    pixel(CGFloat(3 + index * 3), CGFloat(19 - index * 3), 3, 1,
                          color: index == 3 ? theme.accent : theme.primary)
                }
            case .data:
                for point in [(3, 4), (7, 2), (16, 3), (20, 7), (3, 17), (8, 21), (18, 19)] {
                    pixel(CGFloat(point.0), CGFloat(point.1), 1, 2,
                          color: point.0.isMultiple(of: 2) ? theme.accent : theme.primary)
                }
                pixel(20, 15, 2, 1, color: theme.highlight)
            case .momentum:
                for offset in 0..<4 {
                    pixel(CGFloat(1 + offset * 2), CGFloat(18 - offset * 4), 4, 1)
                    pixel(CGFloat(15 + offset * 2), CGFloat(20 - offset * 4), 3, 1,
                          color: offset == 2 ? theme.accent : theme.highlight)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Compact patron stamp placed on every exercise and muscle icon. The rim
/// treatment stays subtle; this badge makes the active identity unmistakable
/// even at the 40-point list-row size.
struct CharacterSignatureBadge: View {
    let theme: CharacterIconTheme

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let unit = side / 12
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let bounds = CGRect(origin: origin, size: CGSize(width: side, height: side))

            context.fill(Path(ellipseIn: bounds), with: .color(TimeChamber.void.opacity(0.98)))
            context.stroke(Path(ellipseIn: bounds.insetBy(dx: unit * 0.6, dy: unit * 0.6)),
                           with: .color(theme.accent),
                           lineWidth: max(1, unit * 0.8))

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
            }
            func pixel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1,
                       _ color: Color? = nil) {
                context.fill(Path(CGRect(x: origin.x + x * unit, y: origin.y + y * unit,
                                         width: w * unit, height: h * unit)),
                             with: .color(color ?? theme.primary))
            }

            switch theme.motif {
            case .ember:
                var flame = Path()
                flame.move(to: point(6, 2))
                flame.addLine(to: point(8.5, 6))
                flame.addLine(to: point(6.5, 10))
                flame.addLine(to: point(3.5, 8))
                flame.addLine(to: point(5, 5.5))
                flame.closeSubpath()
                context.fill(flame, with: .color(theme.primary))
                pixel(5.5, 6.5, 1.5, 2.5, theme.highlight)
            case .endlessWell:
                context.stroke(Path(ellipseIn: bounds.insetBy(dx: unit * 3.2, dy: unit * 3.2)),
                               with: .color(theme.primary), lineWidth: max(1, unit))
                pixel(5, 1.5, 2, 2, theme.accent)
                pixel(8.5, 5, 2, 2, theme.accent)
                pixel(5, 8.5, 2, 2, theme.accent)
                pixel(1.5, 5, 2, 2, theme.accent)
            case .mountain:
                var mountain = Path()
                mountain.move(to: point(2, 9))
                mountain.addLine(to: point(5.5, 3))
                mountain.addLine(to: point(7, 6))
                mountain.addLine(to: point(8.5, 4.5))
                mountain.addLine(to: point(10, 9))
                mountain.closeSubpath()
                context.fill(mountain, with: .color(theme.primary))
                pixel(5, 5, 1, 1, theme.highlight)
            case .shield:
                var shield = Path()
                shield.move(to: point(3, 3))
                shield.addLine(to: point(9, 3))
                shield.addLine(to: point(8.3, 8))
                shield.addLine(to: point(6, 10))
                shield.addLine(to: point(3.7, 8))
                shield.closeSubpath()
                context.fill(shield, with: .color(theme.primary))
                pixel(5.5, 4.5, 1, 3, theme.highlight)
            case .scar:
                for offset in 0..<3 {
                    pixel(CGFloat(2 + offset * 3), CGFloat(8 - offset * 3), 3, 1,
                          offset == 1 ? theme.accent : theme.primary)
                }
            case .data:
                pixel(2.5, 2.5, 2, 2)
                pixel(7.5, 2.5, 2, 2, theme.highlight)
                pixel(2.5, 7.5, 2, 2, theme.highlight)
                pixel(7.5, 7.5, 2, 2, theme.accent)
                pixel(5.5, 4, 1, 4)
                pixel(4, 5.5, 4, 1)
            case .momentum:
                var upper = Path()
                upper.move(to: point(2, 4))
                upper.addLine(to: point(6, 2))
                upper.addLine(to: point(10, 4))
                upper.addLine(to: point(6, 5.5))
                upper.closeSubpath()
                context.fill(upper, with: .color(theme.primary))
                var lower = upper
                lower = lower.applying(CGAffineTransform(translationX: 0, y: unit * 3))
                context.fill(lower, with: .color(theme.highlight))
            }
        }
        .accessibilityHidden(true)
    }
}

enum VexethArtwork {
    static func assetName(for form: Int) -> String {
        switch min(max(form, 1), 3) {
        case 1: "CharacterVexethForm1"
        case 2: "CharacterVexethForm2"
        default: "CharacterVexethForm3"
        }
    }

    static func title(for form: Int) -> String {
        switch min(max(form, 1), 3) {
        case 1: "Vexeth · Crimson Star"
        case 2: "Vexeth Unbound · Crimson Nova"
        default: "Vexeth Apex · Crimson Singularity"
        }
    }
}

/// Circular roster portrait backed by the commissioned pixel-art asset. Rank
/// remains encoded in the frame material; the character identity now comes
/// from the actual illustration instead of an initial and SF Symbol.
struct CharacterAvatarView: View {
    let character: CharacterKey
    let tier: TransformationTier
    var size: CGFloat = 88
    /// Sealed patrons are silhouettes, not previews: the art ships in the
    /// bundle, but identity is earned, so a locked avatar goes dark and keeps
    /// only a faint ghost of the figure against the nested card.
    var locked: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(SettColor.cardNested)
            Image(character.portraitAssetName)
                .resizable()
                .scaledToFit()
                .padding(size * 0.025)
                // Crushed to a true silhouette (same multiply as the lineup's
                // sealed veil) — outline and aura shape only, no readable detail.
                .colorMultiply(locked ? Color(white: 0.12) : .white)
                .opacity(locked ? 0.9 : 1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(ringStyle, lineWidth: 4)
        }
        .overlay(alignment: .bottomTrailing) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: max(10, size * 0.16), weight: .bold))
                    .foregroundStyle(SettColor.iron)
            }
        }
        .accessibilityElement(children: .ignore)
        // A locked identity should not leak through VoiceOver either.
        .accessibilityLabel(locked ? "Sealed patron" : "\(character.displayName), \(tier.displayName)")
    }

    /// The ring rendered in the tier's material. A sealed patron shows no
    /// rank — the frame drops to iron until the identity is earned.
    private var ringStyle: AnyShapeStyle {
        guard !locked else { return AnyShapeStyle(SettColor.cardBorder) }
        return switch tier.frameMaterial {
        case .iron:
            AnyShapeStyle(SettColor.cardBorder)
        case .steel:
            AnyShapeStyle(LinearGradient(
                colors: [
                    Color(dynamicLight: 0xA8A29A, dark: 0xA8A29A),
                    Color(dynamicLight: 0x6C665E, dark: 0x6C665E),
                ],
                startPoint: .top, endPoint: .bottom
            ))
        case .gold:
            AnyShapeStyle(Aura.gold)
        case .prismatic:
            AnyShapeStyle(AngularGradient(
                gradient: Gradient(colors: [
                    SettColor.heroCyan,
                    SettColor.saiyanGold,
                    SettColor.heroCyan,
                ]),
                center: .center
            ))
        }
    }

}

struct VexethPortraitView: View {
    let form: Int

    var body: some View {
        Image(VexethArtwork.assetName(for: form))
            .resizable()
            .scaledToFit()
            .accessibilityLabel(VexethArtwork.title(for: form))
    }
}

/// Full production roster: the seven selectable patrons plus all three rival
/// forms. This is linked from Power and also doubles as the simulator review
/// surface so every shipped portrait can be inspected together.
struct CharacterLineupView: View {
    /// Defaults show the full roster, so the simulator review surface and the
    /// existing debug entry points keep working untouched; production callers
    /// pass the derived unlock state from ProgressionStore.
    var unlockedPatrons: Set<CharacterKey> = Set(CharacterKey.allCases)
    var highestSeenRivalForm: Int = 3

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// How much of a card's art the user has earned. Veiled art is crushed to a
    /// true silhouette via colorMultiply — the multiply zeroes every channel
    /// toward black so internal detail (faces, armor, motifs) cannot be read,
    /// leaving only the outline and a breath of the aura. `.sealed` keeps a
    /// cold grey whisper (a patron is someone waiting); `.unrevealed` sinks to
    /// blood-dark so a future rival form gives away nothing but its menace.
    private enum CardVeil {
        case none
        case sealed
        case unrevealed

        var multiply: Color {
            switch self {
            case .none: .white   // multiply identity — untouched art
            case .sealed: Color(white: 0.12)
            case .unrevealed: Color(red: 0.10, green: 0.02, blue: 0.02)
            }
        }

        var opacity: Double {
            switch self {
            case .none: 1
            case .sealed: 0.9
            case .unrevealed: 0.8
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                Section {
                    ForEach(CharacterKey.allCases, id: \.self) { character in
                        if unlockedPatrons.contains(character) {
                            lineupCard(
                                assetName: character.portraitAssetName,
                                title: shortName(character),
                                subtitle: character.displayName,
                                tint: SettColor.heroCyan
                            )
                        } else {
                            // Sealed patrons keep their slot but not their name: the
                            // silhouette plus the story-voice hint tells the user how
                            // this voice awakens without spoiling who it belongs to.
                            lineupCard(
                                assetName: character.portraitAssetName,
                                title: "???",
                                subtitle: PatronUnlocks.requirement(for: character),
                                tint: SettColor.heroCyan,
                                veil: .sealed,
                                accessibilityLabel: "Sealed patron. \(PatronUnlocks.requirement(for: character))"
                            )
                        }
                    }
                } header: {
                    sectionHeader("PATRONS")
                }

                Section {
                    ForEach(1...3, id: \.self) { form in
                        // The rival only shows forms the user has actually faced;
                        // anything beyond the high-water mark stays a threat, not
                        // a preview. Crimson stays crimson either way.
                        if form <= highestSeenRivalForm {
                            lineupCard(
                                assetName: VexethArtwork.assetName(for: form),
                                title: "VEXETH · FORM \(form)",
                                subtitle: VexethArtwork.title(for: form),
                                tint: SettColor.villainCrimson
                            )
                        } else {
                            lineupCard(
                                assetName: VexethArtwork.assetName(for: form),
                                title: "VEXETH · FORM \(form)",
                                subtitle: "Not yet revealed.",
                                tint: SettColor.villainCrimson,
                                veil: .unrevealed,
                                accessibilityLabel: "Vexeth, form \(form). Not yet revealed."
                            )
                        }
                    }
                } header: {
                    sectionHeader("THE CRIMSON RIVAL")
                }
            }
            .padding(16)
        }
        .dungeonBackground()
        .navigationTitle("Character Lineup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lineupCard(
        assetName: String,
        title: String,
        subtitle: String,
        tint: Color,
        veil: CardVeil = .none,
        accessibilityLabel: String? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(height: 150)
                .colorMultiply(veil.multiply)
                .opacity(veil.opacity)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .kerning(1)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            // Unclamped: the awakening requirements are full sentences and a
            // clipped hint is worse than a taller card. minHeight keeps short
            // rows (plain display names) from collapsing the grid rhythm.
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .settCard(padding: 10)
        .accessibilityElement(children: .combine)
        // Veiled cards route through the override so a sealed or unrevealed
        // identity never leaks through VoiceOver.
        .accessibilityLabel(accessibilityLabel ?? subtitle)
    }

    private func sectionHeader(_ title: String) -> some View {
        Eyebrow(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .gridCellColumns(2)
    }

    private func shortName(_ character: CharacterKey) -> String {
        let name = character.displayName
        if let comma = name.firstIndex(of: ",") {
            return String(name[..<comma]).uppercased()
        }
        return name.split(separator: " ").first.map { String($0).uppercased() } ?? name.uppercased()
    }
}
