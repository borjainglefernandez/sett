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

/// Circular art icon with a tier-colored ring — the ring keeps the performance
/// signal (amber/green/…) that full-color art can't carry by tint.
struct ExerciseArtView: View {
    let asset: String
    var size: CGFloat = 28
    var color: Color = SettColor.heroCyan

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(color.opacity(0.85), lineWidth: max(1, size / 22))
            }
            .shadow(color: color.opacity(0.45), radius: size * 0.14)
    }
}
