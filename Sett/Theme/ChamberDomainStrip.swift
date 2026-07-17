import SwiftUI

/// Horizontal picker for the Time Chamber realm. `selection` is a
/// `ChamberBackground.rawValue`; when `allowsDefault` is true, a leading "Default"
/// option maps to `nil` (inherit the app-wide realm) — used by per-routine domains.
/// `circular` swaps the tall card thumbnails for compact circular realm previews.
struct ChamberDomainStrip: View {
    @Binding var selection: String?
    var allowsDefault: Bool = false
    var circular: Bool = false

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
            // 0.15 matches ChamberSegments, which sits directly above this strip
            // in Settings — one selection tempo across the app.
            withAnimation(.snappy(duration: 0.15)) { selection = raw }
            Haptics.selection()
        } label: {
            VStack(spacing: 6) {
                preview(asset: asset, selected: selected)
                Text(circular ? shortTitle(title) : title)
                    // 10pt floor even in the circular strip — 9 was the app's
                    // smallest text and the short titles fit at 10.
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(selected ? SettColor.bone : SettColor.ash)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: circular ? 54 : 76)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func preview(asset: String?, selected: Bool) -> some View {
        let ring = selected ? SettColor.heroCyan : SettColor.cardBorder
        if circular {
            realmImage(asset)
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(ring, lineWidth: selected ? 2.5 : 1) }
                .overlay(alignment: .bottomTrailing) {
                    if selected {
                        checkmark.offset(x: 3, y: 3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        } else {
            realmImage(asset)
                .frame(width: 76, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ring, lineWidth: selected ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        checkmark.padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
    }

    @ViewBuilder
    private func realmImage(_ asset: String?) -> some View {
        if let asset {
            Image(asset).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                SettColor.cardNested
                Image(systemName: "circle.dashed")
                    .font(circular ? .body : .title3)
                    .foregroundStyle(SettColor.ash)
            }
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(SettColor.heroCyan)
            .background(Circle().fill(SettColor.etch.opacity(0.5)).padding(1))
    }

    /// Realm titles are two words ("Nebula Void"); the circular strip shows the
    /// distinctive first word to stay compact.
    private func shortTitle(_ title: String) -> String {
        title == "Default" ? title : (title.split(separator: " ").first.map(String.init) ?? title)
    }
}
