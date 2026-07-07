import SwiftUI
import SettCore

/// 88 pt circular character portrait: tier-colored aura ring (4 pt), the
/// character's initial in SF Rounded heavy, and their domain symbol beneath it.
/// Stands in for the commissioned illustrations with the same silhouette.
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
                    .foregroundStyle(.primary)
                Image(systemName: domainSymbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .overlay {
            Circle()
                .strokeBorder(Aura.forTier(tier.rawValue), lineWidth: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.displayName), \(tier.displayName)")
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
