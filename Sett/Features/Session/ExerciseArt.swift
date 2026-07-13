import SwiftUI
import UIKit
import SettCore

// MARK: - Generated Saiyan art (asset catalog `ExArt_<key>` imagesets)
//
// Full-color anime warrior icons generated per movement (top-50 catalog) and per
// muscle group (custom-exercise defaults). Resolution is name-based like the vector
// glyphs; anything without art falls back to the vector warrior rig, so the app
// never renders an empty icon.

enum ExerciseArt {
    /// Asset name for a movement, if its art is in the catalog.
    static func movementAsset(for name: String) -> String? {
        let key = artKey(for: name)
        guard let key, UIImage(named: "ExArt_\(key)") != nil else { return nil }
        return "ExArt_\(key)"
    }

    /// Asset name for a muscle-group emblem, if present.
    static func muscleAsset(for muscle: Muscle) -> String? {
        let name = "ExArt_muscle_\(muscle.rawValue)"
        return UIImage(named: name) != nil ? name : nil
    }

    private static func artKey(for name: String) -> String? {
        if let glyph = ExerciseGlyphKey.forName(name) { return glyph.rawValue }
        return extraMap[normalize(name)]
    }

    private static func normalize(_ s: String) -> String { s.lowercased().filter(\.isLetter) }

    /// Movements beyond the 39 vector-rigged ones (the top-50 additions).
    private static let extraMap: [String: String] = {
        var m: [String: String] = [:]
        for (name, key) in [
            ("Lunges", "lunges"), ("Leg Press", "legPress"), ("Shrugs", "shrugs"),
            ("Upright Row", "uprightRow"), ("Front Raise", "frontRaise"),
            ("Back Extension", "backExtension"), ("Crunches", "crunches"),
            ("Plank", "plank"), ("Hanging Leg Raise", "hangingLegRaise"),
            ("Russian Twist", "russianTwist"), ("Farmers Carry", "farmersCarry"),
        ] { m[normalize(name)] = key }
        return m
    }()
}

/// A "battle medallion": the art screen-blended over a tier-tinted disc. The art's flat
/// near-black background (which matched the void card and made the icon invisible)
/// contributes almost nothing under `.screen`, so the tinted disc shows through and
/// gives the icon a clear boundary, while the warrior's glowing cyan/gold edges pop on
/// top. The ring keeps the performance-tier signal that full-color art can't carry.
struct ExerciseArtView: View {
    let asset: String
    var size: CGFloat = 28
    var color: Color = SettColor.heroCyan

    var body: some View {
        ZStack {
            // Tinted ground — a soft radial glow of the tier colour that fades to void.
            Circle()
                .fill(RadialGradient(
                    colors: [color.opacity(0.34), color.opacity(0.12), TimeChamber.void.opacity(0.96)],
                    center: .center, startRadius: 0, endRadius: size * 0.62))
            // The warrior, screen-blended so its dark background drops into the disc and
            // only its glow adds on top.
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .blendMode(.screen)
        }
        .compositingGroup()                      // isolate the blend from the card behind
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(color.opacity(0.9), lineWidth: max(1.5, size / 15))
        }
        .shadow(color: color.opacity(0.5), radius: size * 0.18)
    }
}
