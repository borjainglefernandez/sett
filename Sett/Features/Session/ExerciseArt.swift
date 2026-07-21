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
    /// The catalog has ONE lower-body asset (`ExArt_muscle_legs`), so every group the
    /// legs bucket split into wears it — a follow-up may commission per-group art.
    static func muscleAsset(for muscle: Muscle) -> String? {
        let resolved = Muscle.lowerBody.contains(muscle) ? Muscle.legs : muscle
        let name = "ExArt_muscle_\(resolved.rawValue)"
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

/// A "battle medallion" (BOOST+ treatment). The Gemini art is ~95% dark linework at
/// avg luminance 35/255 — a glowing-figure-in-the-dark look that goes to mud when shrunk.
/// An earlier version screen-blended it over a tinted disc, but `.screen` only keeps the
/// *bright* ~5% of the figure and drops the rest, making the icon fainter still.
///
/// This draws the art normally over a near-void disc and lifts it — saturation/contrast/
/// brightness push the dark cyan linework up to a visible glow, so the whole warrior
/// reads, not just the gold torso. The tier-coloured ring carries the performance signal
/// full-colour art can't. Verified in the Icon Lab (SETT_DEBUG_ICONLAB) to beat every
/// other treatment at 44pt; below ~40pt the art is inherently too dense, so call sites
/// keep icons at or above that floor.
struct ExerciseArtView: View {
    let asset: String
    var size: CGFloat = 40
    var color: Color = SettColor.heroCyan

    @Environment(\.activeSettCharacter) private var activeCharacter

    var body: some View {
        let theme = activeCharacter.iconTheme
        ZStack {
            // A near-void ground with a faint tier wash — dark enough that the brightened
            // linework stands off it, unlike the old bright tinted disc it fought against.
            Circle()
                .fill(RadialGradient(
                    colors: [theme.primary.opacity(0.20), TimeChamber.void.opacity(0.98)],
                    center: .center, startRadius: 0, endRadius: size * 0.6))
            // The warrior, lifted so the dark 95% becomes a visible glow instead of vanishing.
            Image(asset)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: size, height: size)
                .saturation(2.0)
                .contrast(1.7)
                .brightness(0.12)
                .colorMultiply(theme.highlight)
            CharacterIconMotifRing(theme: theme)
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(theme.primary.opacity(0.92), lineWidth: max(1.5, size / 15))
        }
        .overlay(alignment: .topTrailing) {
            CharacterSignatureBadge(theme: theme)
                .frame(width: max(13, size * 0.30), height: max(13, size * 0.30))
                .offset(x: size * 0.03, y: -size * 0.03)
        }
        .shadow(color: theme.primary.opacity(0.45), radius: size * 0.16)
    }
}
