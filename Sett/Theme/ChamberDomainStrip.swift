import SwiftUI

/// Horizontal thumbnail picker for the Time Chamber realm. `selection` is a
/// `ChamberBackground.rawValue`; when `allowsDefault` is true, a leading "Default"
/// option maps to `nil` (inherit the app-wide realm) — used by per-routine domains.
struct ChamberDomainStrip: View {
    @Binding var selection: String?
    var allowsDefault: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if allowsDefault {
                    thumb(raw: nil, title: "Default", asset: nil, selected: selection == nil)
                }
                ForEach(ChamberBackground.allCases) { background in
                    thumb(raw: background.rawValue, title: background.title,
                          asset: background.assetName, selected: selection == background.rawValue)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func thumb(raw: String?, title: String, asset: String?, selected: Bool) -> some View {
        Button {
            selection = raw
            Haptics.selection()
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let asset {
                        Image(asset).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            SettColor.cardNested
                            Image(systemName: "circle.dashed")
                                .font(.title3)
                                .foregroundStyle(SettColor.ash)
                        }
                    }
                }
                .frame(width: 76, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? SettColor.heroCyan : SettColor.cardBorder,
                                      lineWidth: selected ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(SettColor.heroCyan)
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.4)).padding(3))
                    }
                }
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? SettColor.bone : SettColor.ash)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
