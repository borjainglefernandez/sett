import SwiftUI
import SettCore

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

/// 88 pt circular character portrait: a tier-MATERIAL ring (rank reads from
/// the border finish, never a hue), the character's initial in SF Rounded
/// heavy, and their domain symbol beneath it. Stands in for the commissioned
/// illustrations with the same silhouette. Static — the prismatic ring holds
/// still here; the slow shine-sweep stays exclusive to the card frame.
struct CharacterAvatarView: View {
    let character: CharacterKey
    let tier: TransformationTier

    var body: some View {
        ZStack {
            Circle()
                .fill(SettColor.cardNested)
            VStack(spacing: 2) {
                Text(initial)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(SettColor.bone)
                Image(systemName: domainSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SettColor.ash)
            }
        }
        .frame(width: 88, height: 88)
        .overlay {
            Circle()
                .strokeBorder(ringStyle, lineWidth: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.displayName), \(tier.displayName)")
    }

    /// The ring rendered in the tier's material.
    private var ringStyle: AnyShapeStyle {
        switch tier.frameMaterial {
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

    private var initial: String {
        String(character.displayName.prefix(1))
    }

    private var domainSymbol: String {
        switch character {
        case .vego: "bolt.fill"
        case .gosi: "fork.knife"
        case .barok: "mountain.2.fill"
        case .nyra: "gearshape.fill"
        case .torren: "books.vertical.fill"
        case .zia: "testtube.2"
        case .zyn: "hare.fill"
        }
    }
}
