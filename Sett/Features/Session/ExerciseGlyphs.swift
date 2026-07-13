import SwiftUI
import SettCore

// MARK: - Exercise battle glyphs (v2 — the warrior rig)
//
// Every exercise icon is a WARRIOR (spiky-haired figure) actually PERFORMING the
// movement. Each glyph is defined as TWO keyframe poses of one shared skeleton —
// pose A = bottom of the rep, pose B = lockout — and the renderer lerps every joint
// by `phase`, so the same definition yields a static icon (phase 0.75) anywhere and
// a living, rep-performing animation in the workout. A ki burst flares in at
// lockout (rays scale with phase) — the power reads off the peak of the rep.

/// Normalised point inside a glyph's square: x,y in 0...1, (0,0) = top-left, y grows down.
func pt(_ r: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
}

/// Compact normalized-point literal for pose tables.
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

enum ExerciseGlyphKey: String, CaseIterable {
    case flatBenchPress, inclineBenchPress, declineBenchPress, chestFly, hexPress, chestPress, pullAround, pushUps
    case dips, tricepPushdown, skullCrusher, tricepExtension, frenchPress
    case bicepCurl, inclineBicepCurl, hammerBicepCurl, preacherCurl, concentrationCurl
    case lateralRaise, shoulderPress, facePulls, rearDeltFly
    case latPulldown, latPullover, bentOverRow, pullUp, row, deadlift
    case squat, hackSquat, bulgarianSplitSquat, legExtension, legCurl
    case hipThrust, sumoDeadlift, romanianDeadlift, standingCalfRaises, seatedCalfRaises, kickbacks

    /// Resolve from an exercise's display name (case / space / punctuation-insensitive),
    /// so both equipment variants of a movement share the movement's glyph.
    static func forName(_ name: String) -> ExerciseGlyphKey? {
        nameMap[normalize(name)]
    }
    private static func normalize(_ s: String) -> String { s.lowercased().filter(\.isLetter) }

    private static let nameMap: [String: ExerciseGlyphKey] = {
        var m: [String: ExerciseGlyphKey] = [:]
        for (name, key) in canonicalNames { m[normalize(name)] = key }
        return m
    }()

    /// key ↔ canonical seed name (ExerciseSeed.json).
    private static let canonicalNames: [(String, ExerciseGlyphKey)] = [
        ("Flat Bench Press", .flatBenchPress), ("Incline Bench Press", .inclineBenchPress),
        ("Decline Bench Press", .declineBenchPress), ("Chest Fly", .chestFly),
        ("Hex Press", .hexPress), ("Chest Press", .chestPress), ("Pull Around", .pullAround),
        ("Push Ups", .pushUps), ("Dips", .dips), ("Tricep Pushdown", .tricepPushdown),
        ("Skull Crusher", .skullCrusher), ("Tricep Extension", .tricepExtension),
        ("French Press", .frenchPress), ("Bicep Curl", .bicepCurl),
        ("Incline Bicep Curl", .inclineBicepCurl), ("Hammer Bicep Curl", .hammerBicepCurl),
        ("Preacher Curl", .preacherCurl), ("Concentration Curl", .concentrationCurl),
        ("Lateral Raise", .lateralRaise), ("Shoulder Press", .shoulderPress),
        ("Face Pulls", .facePulls), ("Rear Delt Fly", .rearDeltFly),
        ("Lat Pulldown", .latPulldown), ("Lat Pullover", .latPullover),
        ("Bent Over Row", .bentOverRow), ("Pull Up", .pullUp), ("Row", .row),
        ("Deadlift", .deadlift), ("Squat", .squat), ("Hack Squat", .hackSquat),
        ("Bulgarian Split Squat", .bulgarianSplitSquat), ("Leg Extension", .legExtension),
        ("Leg Curl", .legCurl), ("Hip Thrust", .hipThrust), ("Sumo Deadlift", .sumoDeadlift),
        ("Romanian Deadlift", .romanianDeadlift), ("Standing Calf Raises", .standingCalfRaises),
        ("Seated Calf Raises", .seatedCalfRaises), ("Kickbacks", .kickbacks),
    ]

    var displayName: String {
        ExerciseGlyphKey.canonicalNames.first { $0.1 == self }?.0 ?? rawValue
    }
}

// MARK: - Pose model

/// One keyframe of the warrior skeleton + equipment, in normalized 0...1 coordinates.
/// Pose A and pose B of a glyph MUST have identical array counts — every element is
/// lerped index-wise by the rep phase.
struct GlyphPose {
    var head: CGPoint                 // head-circle center (hair auto-fans away from neck)
    var neck: CGPoint
    var hip: CGPoint
    var arms: [[CGPoint]] = []        // each: [shoulder, elbow, hand]
    var legs: [[CGPoint]] = []        // each: [hipJoint, knee, ankle]
    var bar: [CGPoint]? = nil         // barbell axis [left, right] — plates auto-drawn
    var discs: [CGPoint] = []         // end-on bar / handle discs (side-view grips)
    var dumbbells: [DB] = []          // auto handle + plate ticks
    var lines: [[CGPoint]] = []       // equipment segments: bench, seat, cable, frame
    var ki: CGPoint? = nil            // burst origin — rays scale in with phase

    struct DB { var c: CGPoint; var angle: CGFloat }   // center + handle angle (radians)
}

struct GlyphSpec {
    var a: GlyphPose                  // bottom of the rep (phase 0)
    var b: GlyphPose                  // lockout / peak (phase 1)
    /// The A→B blend the STATIC icon renders at. Mid-rep (0.75) reads best for most
    /// movements, but hinge lifts must render near the bottom (the hinge IS the icon —
    /// at lockout a deadlift is just a warrior standing).
    var readPhase: CGFloat = 0.75
}

// MARK: - Renderer

enum GlyphRig {
    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
    }

    /// The fill layers of one glyph, logo-grade: the sculpted BODY silhouette, the
    /// GEAR (heavy, unmissable equipment), the KI shards, and CUTS — negative-space
    /// muscle definition punched OUT of the composite (pec line, abs, plate holes),
    /// the signature of an emblem mark rather than a stick figure.
    struct Layers {
        var body = Path()
        var gear = Path()
        var ki = Path()
        var cuts = Path()
        var combined: Path {
            var p = body; p.addPath(gear); p.addPath(ki); return p
        }
    }

    /// Build the fill layers for `spec` at rep phase `t` (0 = bottom, 1 = lockout).
    static func layers(spec: GlyphSpec, in r: CGRect, phase t: CGFloat) -> Layers {
        var out = Layers()
        let a = spec.a, b = spec.b
        let w = min(r.width, r.height)
        func at(_ pa: CGPoint, _ pb: CGPoint) -> CGPoint {
            let m = mix(pa, pb, t)
            return pt(r, m.x, m.y)
        }
        func flesh(_ pts: [CGPoint], _ width: CGFloat, into path: inout Path,
                   cap: CGLineCap = .round) {
            guard pts.count > 1 else { return }
            var seg = Path()
            seg.move(to: pts[0])
            for q in pts.dropFirst() { seg.addLine(to: q) }
            path.addPath(seg.strokedPath(StrokeStyle(lineWidth: width, lineCap: cap,
                                                     lineJoin: .round)))
        }
        func disc(_ c: CGPoint, _ radius: CGFloat, into path: inout Path) {
            path.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius,
                                       width: radius * 2, height: radius * 2))
        }

        // — Skeleton anchors —
        let head = at(a.head, b.head)
        let neck = at(a.neck, b.neck)
        let hip  = at(a.hip, b.hip)
        let arms = zip(a.arms, b.arms).filter { $0.0.count == 3 && $0.1.count == 3 }
            .map { pair in (0..<3).map { at(pair.0[$0], pair.1[$0]) } }
        let isFront = arms.count == 2   // symmetric front view → full torso sculpt

        // — Torso —
        if isFront {
            // Sculpted V-taper slab: wide shoulder line down to a narrow waist, like a
            // logo mark — not a spine stroke. Corners rounded by the girdle strokes.
            let sL = arms[0][0], sR = arms[1][0]
            let dirX = sR.x - sL.x, dirY = sR.y - sL.y
            let dl = max(0.001, sqrt(dirX * dirX + dirY * dirY))
            let ux = dirX / dl, uy = dirY / dl                    // shoulder axis
            let flare = 0.055 * w                                  // shoulders past the joints
            let waist = 0.075 * w                                  // half waist width
            var torso = Path()
            torso.move(to: CGPoint(x: sL.x - ux * flare, y: sL.y - uy * flare))
            torso.addLine(to: CGPoint(x: sR.x + ux * flare, y: sR.y + uy * flare))
            torso.addLine(to: CGPoint(x: hip.x + ux * waist, y: hip.y + uy * waist))
            torso.addLine(to: CGPoint(x: hip.x - ux * waist, y: hip.y - uy * waist))
            torso.closeSubpath()
            out.body.addPath(torso)
            flesh([sL, sR], 0.10 * w, into: &out.body)             // rounded shoulder girdle
            flesh([neck, hip], 0.09 * w, into: &out.body)
            // Deltoid caps — the boulder shoulders of the mark.
            disc(sL, 0.055 * w, into: &out.body)
            disc(sR, 0.055 * w, into: &out.body)

            // — Negative-space muscle cuts (the reference's signature) —
            let midX = (sL.x + sR.x) / 2, shY = (sL.y + sR.y) / 2
            let torsoH = max(0.001, hip.y - shY)
            var pecs = Path()   // two arcs meeting at the sternum
            pecs.move(to: CGPoint(x: midX - 0.115 * w, y: shY + torsoH * 0.18))
            pecs.addQuadCurve(to: CGPoint(x: midX - 0.008 * w, y: shY + torsoH * 0.34),
                              control: CGPoint(x: midX - 0.10 * w, y: shY + torsoH * 0.40))
            pecs.move(to: CGPoint(x: midX + 0.115 * w, y: shY + torsoH * 0.18))
            pecs.addQuadCurve(to: CGPoint(x: midX + 0.008 * w, y: shY + torsoH * 0.34),
                              control: CGPoint(x: midX + 0.10 * w, y: shY + torsoH * 0.40))
            out.cuts.addPath(pecs.strokedPath(StrokeStyle(lineWidth: 0.02 * w, lineCap: .round)))
            var abs = Path()    // sternum line + two ab rows
            abs.move(to: CGPoint(x: midX, y: shY + torsoH * 0.40))
            abs.addLine(to: CGPoint(x: midX, y: hip.y - torsoH * 0.06))
            abs.move(to: CGPoint(x: midX - 0.045 * w, y: shY + torsoH * 0.58))
            abs.addLine(to: CGPoint(x: midX + 0.045 * w, y: shY + torsoH * 0.58))
            abs.move(to: CGPoint(x: midX - 0.04 * w, y: shY + torsoH * 0.76))
            abs.addLine(to: CGPoint(x: midX + 0.04 * w, y: shY + torsoH * 0.76))
            out.cuts.addPath(abs.strokedPath(StrokeStyle(lineWidth: 0.016 * w, lineCap: .round)))
        } else {
            // Side view: a heavy trunk with a chest bulge — profile mass.
            flesh([neck, hip], 0.115 * w, into: &out.body)
            let chest = CGPoint(x: neck.x + (hip.x - neck.x) * 0.28,
                                y: neck.y + (hip.y - neck.y) * 0.28)
            disc(chest, 0.068 * w, into: &out.body)
        }

        // — Limbs: tapered heavy mass (thick upper segment, leaner lower) + fists —
        for arm in arms {
            flesh([arm[0], arm[1]], 0.078 * w, into: &out.body)
            flesh([arm[1], arm[2]], 0.055 * w, into: &out.body)
            disc(arm[2], 0.034 * w, into: &out.body)               // fist
        }
        for (legA, legB) in zip(a.legs, b.legs) where legA.count == 3 && legB.count == 3 {
            let hipJ = at(legA[0], legB[0]), knee = at(legA[1], legB[1]), ankle = at(legA[2], legB[2])
            flesh([hipJ, knee], 0.088 * w, into: &out.body)        // thigh
            flesh([knee, ankle], 0.06 * w, into: &out.body)        // shin
        }

        // — Head + the flame crown: BIG, the Saiyan crest —
        let hr = 0.075 * w
        disc(head, hr, into: &out.body)
        var ux2 = head.x - neck.x, uy2 = head.y - neck.y
        let ul2 = max(0.001, sqrt(ux2 * ux2 + uy2 * uy2)); ux2 /= ul2; uy2 /= ul2
        let crown = atan2(uy2, ux2)
        let tips: [(CGFloat, CGFloat)] = [(-1.15, 0.085), (-0.7, 0.14), (-0.25, 0.185),
                                          (0.15, 0.165), (0.55, 0.12), (1.0, 0.075)]
        var hair = Path()
        hair.move(to: CGPoint(x: head.x + cos(crown - 1.35) * hr * 0.85,
                              y: head.y + sin(crown - 1.35) * hr * 0.85))
        for (i, tip) in tips.enumerated() {
            let (off, len) = tip
            hair.addLine(to: CGPoint(x: head.x + cos(crown + off) * (hr + len * w),
                                     y: head.y + sin(crown + off) * (hr + len * w)))
            let valley = i < tips.count - 1 ? (off + tips[i + 1].0) / 2 : 1.3
            hair.addLine(to: CGPoint(x: head.x + cos(crown + valley) * hr * 0.8,
                                     y: head.y + sin(crown + valley) * hr * 0.8))
        }
        hair.closeSubpath()
        out.body.addPath(hair)

        // — Gear: heavy and unmissable —
        // Barbell: thick bar + STACKED slab plates per end (the logo read).
        if let barA = a.bar, let barB = b.bar, barA.count == 2, barB.count == 2 {
            let l = at(barA[0], barB[0]), rt = at(barA[1], barB[1])
            flesh([l, rt], 0.045 * w, into: &out.gear)
            var dx = rt.x - l.x, dy = rt.y - l.y
            let dl = max(0.001, sqrt(dx * dx + dy * dy)); dx /= dl; dy /= dl
            let nx = -dy, ny = dx
            // Two slabs per side: inner big, outer smaller — butt caps = sharp rects.
            for (end, dir) in [(l, 1.0), (rt, -1.0)] {
                for (inset, half, thick) in [(0.035, 0.115, 0.055), (0.10, 0.08, 0.05)] {
                    let cx = end.x + dx * dir * inset * w
                    let cy = end.y + dy * dir * inset * w
                    flesh([CGPoint(x: cx + nx * half * w, y: cy + ny * half * w),
                           CGPoint(x: cx - nx * half * w, y: cy - ny * half * w)],
                          thick * w, into: &out.gear, cap: .butt)
                }
            }
        }
        // End-on plate discs: big, with a punched center hole (a real plate).
        for (dA, dB) in zip(a.discs, b.discs) {
            let c = at(dA, dB)
            disc(c, 0.075 * w, into: &out.gear)
            disc(c, 0.02 * w, into: &out.cuts)
        }
        // Dumbbells: thick handle + chunky slab plates.
        for (dbA, dbB) in zip(a.dumbbells, b.dumbbells) {
            let c = at(dbA.c, dbB.c)
            let ang = mix(dbA.angle, dbB.angle, t)
            let hx = cos(ang), hy = sin(ang)
            let nx = -hy, ny = hx
            let half = 0.09 * w
            flesh([CGPoint(x: c.x - hx * half, y: c.y - hy * half),
                   CGPoint(x: c.x + hx * half, y: c.y + hy * half)], 0.04 * w, into: &out.gear)
            for dir in [-1.0, 1.0] {
                let px = c.x + hx * dir * half * 0.72, py = c.y + hy * dir * half * 0.72
                flesh([CGPoint(x: px + nx * 0.075 * w, y: py + ny * 0.075 * w),
                       CGPoint(x: px - nx * 0.075 * w, y: py - ny * 0.075 * w)],
                      0.055 * w, into: &out.gear, cap: .butt)
            }
        }
        // Benches / seats / cables / frames: solid slabs, not hairlines.
        for (lnA, lnB) in zip(a.lines, b.lines) where lnA.count == 2 && lnB.count == 2 {
            flesh([at(lnA[0], lnB[0]), at(lnA[1], lnB[1])], 0.05 * w, into: &out.gear)
        }

        // — Ki shards: bold energy slivers off the load at the peak —
        if let kA = a.ki ?? b.ki, let kB = b.ki ?? a.ki {
            let c = at(kA, kB)
            for (ang, len) in [(-1.95, 0.11), (-1.32, 0.145), (-0.72, 0.095)] {
                let tipX = c.x + cos(ang) * len * w
                let tipY = c.y + sin(ang) * len * w
                let nx = -sin(ang) * 0.022 * w, ny = cos(ang) * 0.022 * w
                var shard = Path()
                shard.move(to: CGPoint(x: c.x + nx, y: c.y + ny))
                shard.addLine(to: CGPoint(x: tipX, y: tipY))
                shard.addLine(to: CGPoint(x: c.x - nx, y: c.y - ny))
                shard.closeSubpath()
                out.ki.addPath(shard)
            }
        }
        return out
    }
}

// MARK: - Specs (pose tables; BEGIN/END markers are the codegen splice points)

enum Glyphs {
    static func layers(for key: ExerciseGlyphKey, in r: CGRect) -> GlyphRig.Layers {
        let spec = specs[key] ?? Self.placeholder
        return GlyphRig.layers(spec: spec, in: r, phase: spec.readPhase)
    }

    /// Muscle-group warrior emblems — the default icon for CUSTOM exercises. Each is
    /// the classic bodybuilding pose for that muscle group, struck by the same warrior
    /// (front double biceps, lat spread, most-muscular, squat stance…).
    static func muscleLayers(for muscle: Muscle, in r: CGRect) -> GlyphRig.Layers {
        GlyphRig.layers(spec: muscleEmblems[muscle] ?? Self.placeholder, in: r, phase: 1)
    }

    private static func emblem(_ pose: GlyphPose) -> GlyphSpec { GlyphSpec(a: pose, b: pose) }

    static let muscleEmblems: [Muscle: GlyphSpec] = [
        // Most-muscular crab: arms curled hard in front of the chest.
        .chest: emblem(GlyphPose(
            head: P(0.5, 0.22), neck: P(0.5, 0.30), hip: P(0.5, 0.56),
            arms: [[P(0.42, 0.32), P(0.28, 0.42), P(0.41, 0.49)],
                   [P(0.58, 0.32), P(0.72, 0.42), P(0.59, 0.49)]],
            legs: [[P(0.5, 0.56), P(0.42, 0.70), P(0.40, 0.86)],
                   [P(0.5, 0.56), P(0.58, 0.70), P(0.60, 0.86)]],
            ki: P(0.5, 0.10))),
        // One arm locked overhead, angled clear of the crown — the extension lockout.
        .triceps: emblem(GlyphPose(
            head: P(0.42, 0.24), neck: P(0.42, 0.32), hip: P(0.42, 0.58),
            arms: [[P(0.44, 0.34), P(0.58, 0.26), P(0.66, 0.14)],
                   [P(0.42, 0.34), P(0.40, 0.47), P(0.42, 0.58)]],
            legs: [[P(0.42, 0.58), P(0.39, 0.72), P(0.38, 0.87)],
                   [P(0.42, 0.58), P(0.47, 0.72), P(0.49, 0.87)]],
            ki: P(0.74, 0.10))),
        // Front double biceps — elbows out, fists curled toward the head.
        .biceps: emblem(GlyphPose(
            head: P(0.5, 0.24), neck: P(0.5, 0.32), hip: P(0.5, 0.58),
            arms: [[P(0.42, 0.33), P(0.26, 0.32), P(0.31, 0.19)],
                   [P(0.58, 0.33), P(0.74, 0.32), P(0.69, 0.19)]],
            legs: [[P(0.5, 0.58), P(0.43, 0.71), P(0.42, 0.87)],
                   [P(0.5, 0.58), P(0.57, 0.71), P(0.58, 0.87)]],
            ki: P(0.80, 0.12))),
        // Iron cross T — both arms dead straight to the sides.
        .shoulders: emblem(GlyphPose(
            head: P(0.5, 0.24), neck: P(0.5, 0.32), hip: P(0.5, 0.58),
            arms: [[P(0.44, 0.33), P(0.30, 0.32), P(0.15, 0.31)],
                   [P(0.56, 0.33), P(0.70, 0.32), P(0.85, 0.31)]],
            legs: [[P(0.5, 0.58), P(0.44, 0.71), P(0.43, 0.87)],
                   [P(0.5, 0.58), P(0.56, 0.71), P(0.57, 0.87)]],
            ki: P(0.87, 0.20))),
        // Lat spread — arms bowed wide and down, the back flared.
        .back: emblem(GlyphPose(
            head: P(0.5, 0.22), neck: P(0.5, 0.30), hip: P(0.5, 0.56),
            arms: [[P(0.41, 0.31), P(0.25, 0.38), P(0.29, 0.52)],
                   [P(0.59, 0.31), P(0.75, 0.38), P(0.71, 0.52)]],
            legs: [[P(0.5, 0.56), P(0.43, 0.70), P(0.42, 0.86)],
                   [P(0.5, 0.56), P(0.57, 0.70), P(0.58, 0.86)]],
            ki: P(0.5, 0.09))),
        // Deep squat stance, arms punched forward.
        .legs: emblem(GlyphPose(
            head: P(0.5, 0.26), neck: P(0.5, 0.34), hip: P(0.5, 0.58),
            arms: [[P(0.44, 0.36), P(0.33, 0.38), P(0.23, 0.38)],
                   [P(0.56, 0.36), P(0.67, 0.38), P(0.77, 0.38)]],
            legs: [[P(0.5, 0.58), P(0.37, 0.66), P(0.41, 0.86)],
                   [P(0.5, 0.58), P(0.63, 0.66), P(0.59, 0.86)]],
            ki: P(0.5, 0.13))),
        // Rock-solid plank over the floor line.
        .core: emblem(GlyphPose(
            head: P(0.22, 0.56), neck: P(0.30, 0.60), hip: P(0.55, 0.71),
            arms: [[P(0.31, 0.61), P(0.31, 0.75), P(0.31, 0.88)]],
            legs: [[P(0.55, 0.71), P(0.69, 0.78), P(0.83, 0.86)],
                   [P(0.55, 0.71), P(0.70, 0.79), P(0.85, 0.87)]],
            lines: [[P(0.12, 0.91), P(0.92, 0.91)]],
            ki: P(0.31, 0.48))),
        // Power-charge stance — crouched, fists down-out, ki rising off the crown.
        .other: emblem(GlyphPose(
            head: P(0.5, 0.22), neck: P(0.5, 0.30), hip: P(0.5, 0.56),
            arms: [[P(0.44, 0.32), P(0.36, 0.43), P(0.33, 0.53)],
                   [P(0.56, 0.32), P(0.64, 0.43), P(0.67, 0.53)]],
            legs: [[P(0.5, 0.56), P(0.43, 0.68), P(0.41, 0.86)],
                   [P(0.5, 0.56), P(0.57, 0.68), P(0.59, 0.86)]],
            ki: P(0.5, 0.09))),
    ]

    /// Unfilled movements render a resting warrior — obviously placeholder, never broken.
    static let placeholder = GlyphSpec(
        a: GlyphPose(head: P(0.46, 0.22), neck: P(0.46, 0.30), hip: P(0.46, 0.56),
                     arms: [[P(0.46, 0.32), P(0.48, 0.44), P(0.50, 0.55)]],
                     legs: [[P(0.46, 0.56), P(0.44, 0.70), P(0.44, 0.86)],
                            [P(0.46, 0.56), P(0.52, 0.70), P(0.54, 0.86)]]),
        b: GlyphPose(head: P(0.46, 0.20), neck: P(0.46, 0.28), hip: P(0.46, 0.56),
                     arms: [[P(0.46, 0.30), P(0.48, 0.42), P(0.50, 0.53)]],
                     legs: [[P(0.46, 0.56), P(0.44, 0.70), P(0.44, 0.86)],
                            [P(0.46, 0.56), P(0.52, 0.70), P(0.54, 0.86)]])
    )

    // BEGIN GENERATED SPECS
    static let specs: [ExerciseGlyphKey: GlyphSpec] = [
        // Flat bench press — side view: warrior lying on the bench, pressing the bar
        // (end-on disc) from chest to lockout; feet planted off the bench end.
        .flatBenchPress: GlyphSpec(
            a: GlyphPose(head: P(0.20, 0.64), neck: P(0.28, 0.66), hip: P(0.52, 0.66),
                         arms: [[P(0.30, 0.66), P(0.39, 0.60), P(0.35, 0.50)]],
                         legs: [[P(0.52, 0.66), P(0.64, 0.72), P(0.68, 0.88)]],
                         discs: [P(0.35, 0.50)],
                         lines: [[P(0.14, 0.74), P(0.66, 0.74)]],
                         ki: P(0.35, 0.44)),
            b: GlyphPose(head: P(0.20, 0.64), neck: P(0.28, 0.66), hip: P(0.52, 0.66),
                         arms: [[P(0.30, 0.66), P(0.31, 0.54), P(0.31, 0.40)]],
                         legs: [[P(0.52, 0.66), P(0.64, 0.72), P(0.68, 0.88)]],
                         discs: [P(0.31, 0.40)],
                         lines: [[P(0.14, 0.74), P(0.66, 0.74)]],
                         ki: P(0.31, 0.30))),
        // Squat — front view: bar across the shoulders, warrior rises from the hole
        // to lockout; ki flares off the bar at the top.
        .squat: GlyphSpec(
            a: GlyphPose(head: P(0.50, 0.34), neck: P(0.50, 0.42), hip: P(0.50, 0.60),
                         arms: [[P(0.44, 0.43), P(0.39, 0.48), P(0.34, 0.44)],
                                [P(0.56, 0.43), P(0.61, 0.48), P(0.66, 0.44)]],
                         legs: [[P(0.50, 0.60), P(0.37, 0.64), P(0.42, 0.86)],
                                [P(0.50, 0.60), P(0.63, 0.64), P(0.58, 0.86)]],
                         bar: [P(0.22, 0.44), P(0.78, 0.44)],
                         ki: P(0.50, 0.36)),
            b: GlyphPose(head: P(0.50, 0.16), neck: P(0.50, 0.24), hip: P(0.50, 0.50),
                         arms: [[P(0.44, 0.25), P(0.39, 0.31), P(0.34, 0.26)],
                                [P(0.56, 0.25), P(0.61, 0.31), P(0.66, 0.26)]],
                         legs: [[P(0.50, 0.50), P(0.45, 0.68), P(0.44, 0.86)],
                                [P(0.50, 0.50), P(0.55, 0.68), P(0.56, 0.86)]],
                         bar: [P(0.22, 0.26), P(0.78, 0.26)],
                         ki: P(0.50, 0.16))),
        // Bicep curl — side view: standing warrior, elbow pinned, dumbbell curls
        // from thigh to shoulder height.
        .bicepCurl: GlyphSpec(
            a: GlyphPose(head: P(0.40, 0.20), neck: P(0.40, 0.28), hip: P(0.40, 0.56),
                         arms: [[P(0.40, 0.30), P(0.43, 0.46), P(0.47, 0.60)]],
                         legs: [[P(0.40, 0.56), P(0.39, 0.70), P(0.39, 0.86)],
                                [P(0.40, 0.56), P(0.45, 0.70), P(0.47, 0.86)]],
                         dumbbells: [.init(c: P(0.50, 0.61), angle: 2.88)],
                         ki: P(0.62, 0.36)),
            b: GlyphPose(head: P(0.40, 0.20), neck: P(0.40, 0.28), hip: P(0.40, 0.56),
                         arms: [[P(0.40, 0.30), P(0.43, 0.46), P(0.58, 0.35)]],
                         legs: [[P(0.40, 0.56), P(0.39, 0.70), P(0.39, 0.86)],
                                [P(0.40, 0.56), P(0.45, 0.70), P(0.47, 0.86)]],
                         dumbbells: [.init(c: P(0.61, 0.33), angle: 2.35)],
                         ki: P(0.68, 0.22))),
        // Lat pulldown — front view: seated warrior pulls the wide bar from overhead
        // to the collarbone; cable runs up to the anchor.
        .latPulldown: GlyphSpec(
            a: GlyphPose(head: P(0.5, 0.28), neck: P(0.5, 0.35), hip: P(0.5, 0.62),
                         arms: [[P(0.44, 0.36), P(0.38, 0.25), P(0.33, 0.15)],
                                [P(0.56, 0.36), P(0.62, 0.25), P(0.67, 0.15)]],
                         legs: [[P(0.5, 0.62), P(0.43, 0.72), P(0.43, 0.86)],
                                [P(0.5, 0.62), P(0.57, 0.72), P(0.57, 0.86)]],
                         lines: [[P(0.27, 0.15), P(0.73, 0.15)], [P(0.5, 0.06), P(0.5, 0.15)],
                                 [P(0.38, 0.68), P(0.62, 0.68)]],
                         ki: P(0.5, 0.1)),
            b: GlyphPose(head: P(0.5, 0.28), neck: P(0.5, 0.35), hip: P(0.5, 0.62),
                         arms: [[P(0.44, 0.36), P(0.37, 0.44), P(0.33, 0.47)],
                                [P(0.56, 0.36), P(0.63, 0.44), P(0.67, 0.47)]],
                         legs: [[P(0.5, 0.62), P(0.43, 0.72), P(0.43, 0.86)],
                                [P(0.5, 0.62), P(0.57, 0.72), P(0.57, 0.86)]],
                         lines: [[P(0.27, 0.47), P(0.73, 0.47)], [P(0.5, 0.06), P(0.5, 0.47)],
                                 [P(0.38, 0.68), P(0.62, 0.68)]],
                         ki: P(0.5, 0.4)),
            readPhase: 0.75),
        // -- generated poses --
        .inclineBenchPress: GlyphSpec(
            a: GlyphPose(head: P(0.2, 0.54),
                neck: P(0.28, 0.575),
                hip: P(0.52, 0.68),
                arms: [
                    [P(0.3, 0.585), P(0.4, 0.55), P(0.36, 0.47)]],
                legs: [
                    [P(0.52, 0.68), P(0.61, 0.78), P(0.62, 0.9)],
                    [P(0.52, 0.68), P(0.65, 0.8), P(0.67, 0.9)]],
                discs: [P(0.36, 0.47)],
                lines: [
                    [P(0.16, 0.62), P(0.68, 0.84)]],
                ki: P(0.38, 0.42)),
            b: GlyphPose(head: P(0.2, 0.54),
                neck: P(0.28, 0.575),
                hip: P(0.52, 0.68),
                arms: [
                    [P(0.3, 0.585), P(0.35, 0.465), P(0.4, 0.345)]],
                legs: [
                    [P(0.52, 0.68), P(0.61, 0.78), P(0.62, 0.9)],
                    [P(0.52, 0.68), P(0.65, 0.8), P(0.67, 0.9)]],
                discs: [P(0.4, 0.345)],
                lines: [
                    [P(0.16, 0.62), P(0.68, 0.84)]],
                ki: P(0.44, 0.25))),
        .declineBenchPress: GlyphSpec(
            a: GlyphPose(head: P(0.22, 0.71),
                neck: P(0.3, 0.68),
                hip: P(0.54, 0.6),
                arms: [
                    [P(0.33, 0.685), P(0.42, 0.63), P(0.34, 0.54)]],
                legs: [
                    [P(0.54, 0.6), P(0.66, 0.57), P(0.7, 0.7)],
                    [P(0.54, 0.6), P(0.68, 0.6), P(0.72, 0.73)]],
                discs: [P(0.34, 0.54)],
                lines: [
                    [P(0.2, 0.8), P(0.7, 0.62)]],
                ki: P(0.32, 0.48)),
            b: GlyphPose(head: P(0.22, 0.71),
                neck: P(0.3, 0.68),
                hip: P(0.54, 0.6),
                arms: [
                    [P(0.33, 0.685), P(0.285, 0.56), P(0.24, 0.43)]],
                legs: [
                    [P(0.54, 0.6), P(0.66, 0.57), P(0.7, 0.7)],
                    [P(0.54, 0.6), P(0.68, 0.6), P(0.72, 0.73)]],
                discs: [P(0.24, 0.43)],
                lines: [
                    [P(0.2, 0.8), P(0.7, 0.62)]],
                ki: P(0.21, 0.34))),
        .chestFly: GlyphSpec(
            a: GlyphPose(head: P(0.2, 0.64), neck: P(0.28, 0.66), hip: P(0.52, 0.66),
                         arms: [[P(0.3, 0.66), P(0.26, 0.55), P(0.22, 0.45)]],
                         legs: [[P(0.52, 0.66), P(0.64, 0.72), P(0.68, 0.88)]],
                         dumbbells: [.init(c: P(0.21, 0.42), angle: 0.35)],
                         lines: [[P(0.14, 0.74), P(0.66, 0.74)]],
                         ki: P(0.24, 0.34)),
            b: GlyphPose(head: P(0.2, 0.64), neck: P(0.28, 0.66), hip: P(0.52, 0.66),
                         arms: [[P(0.3, 0.66), P(0.32, 0.54), P(0.33, 0.44)]],
                         legs: [[P(0.52, 0.66), P(0.64, 0.72), P(0.68, 0.88)]],
                         dumbbells: [.init(c: P(0.33, 0.41), angle: 0)],
                         lines: [[P(0.14, 0.74), P(0.66, 0.74)]],
                         ki: P(0.33, 0.31)),
            readPhase: 0.45),
        .hexPress: GlyphSpec(
            a: GlyphPose(head: P(0.2, 0.64),
                neck: P(0.28, 0.66),
                hip: P(0.52, 0.66),
                arms: [
                    [P(0.3, 0.66), P(0.39, 0.6), P(0.35, 0.5)]],
                legs: [
                    [P(0.52, 0.66), P(0.62, 0.72), P(0.66, 0.88)],
                    [P(0.52, 0.66), P(0.66, 0.73), P(0.7, 0.88)]],
                discs: [P(0.32, 0.5), P(0.38, 0.5)],
                lines: [
                    [P(0.14, 0.74), P(0.66, 0.74)]],
                ki: P(0.35, 0.44)),
            b: GlyphPose(head: P(0.2, 0.64),
                neck: P(0.28, 0.66),
                hip: P(0.52, 0.66),
                arms: [
                    [P(0.3, 0.66), P(0.31, 0.54), P(0.31, 0.4)]],
                legs: [
                    [P(0.52, 0.66), P(0.62, 0.72), P(0.66, 0.88)],
                    [P(0.52, 0.66), P(0.66, 0.73), P(0.7, 0.88)]],
                discs: [P(0.28, 0.4), P(0.34, 0.4)],
                lines: [
                    [P(0.14, 0.74), P(0.66, 0.74)]],
                ki: P(0.31, 0.3))),
        .chestPress: GlyphSpec(
            a: GlyphPose(head: P(0.34, 0.23),
                neck: P(0.34, 0.31),
                hip: P(0.34, 0.57),
                arms: [
                    [P(0.34, 0.32), P(0.31, 0.43), P(0.42, 0.34)]],
                legs: [
                    [P(0.34, 0.57), P(0.5, 0.58), P(0.49, 0.82)],
                    [P(0.34, 0.57), P(0.52, 0.6), P(0.53, 0.84)]],
                discs: [P(0.42, 0.34)],
                lines: [
                    [P(0.27, 0.61), P(0.48, 0.61)],
                    [P(0.27, 0.29), P(0.27, 0.63)]],
                ki: P(0.47, 0.34)),
            b: GlyphPose(head: P(0.34, 0.23),
                neck: P(0.34, 0.31),
                hip: P(0.34, 0.57),
                arms: [
                    [P(0.34, 0.32), P(0.48, 0.33), P(0.62, 0.33)]],
                legs: [
                    [P(0.34, 0.57), P(0.5, 0.58), P(0.49, 0.82)],
                    [P(0.34, 0.57), P(0.52, 0.6), P(0.53, 0.84)]],
                discs: [P(0.62, 0.33)],
                lines: [
                    [P(0.27, 0.61), P(0.48, 0.61)],
                    [P(0.27, 0.29), P(0.27, 0.63)]],
                ki: P(0.72, 0.33))),
        .pullAround: GlyphSpec(
            a: GlyphPose(head: P(0.4, 0.2),
                neck: P(0.4, 0.28),
                hip: P(0.4, 0.56),
                arms: [
                    [P(0.4, 0.3), P(0.34, 0.4), P(0.27, 0.5)]],
                legs: [
                    [P(0.4, 0.56), P(0.38, 0.7), P(0.37, 0.86)],
                    [P(0.4, 0.56), P(0.45, 0.7), P(0.47, 0.86)]],
                discs: [P(0.27, 0.5)],
                lines: [
                    [P(0.12, 0.82), P(0.27, 0.5)]],
                ki: P(0.25, 0.52)),
            b: GlyphPose(head: P(0.4, 0.2),
                neck: P(0.4, 0.28),
                hip: P(0.4, 0.56),
                arms: [
                    [P(0.4, 0.3), P(0.49, 0.33), P(0.61, 0.27)]],
                legs: [
                    [P(0.4, 0.56), P(0.38, 0.7), P(0.37, 0.86)],
                    [P(0.4, 0.56), P(0.45, 0.7), P(0.47, 0.86)]],
                discs: [P(0.61, 0.27)],
                lines: [
                    [P(0.12, 0.82), P(0.61, 0.27)]],
                ki: P(0.68, 0.22))),
        .pushUps: GlyphSpec(
            a: GlyphPose(head: P(0.22, 0.72),
                neck: P(0.3, 0.74),
                hip: P(0.55, 0.79),
                arms: [
                    [P(0.31, 0.75), P(0.43, 0.81), P(0.3, 0.88)]],
                legs: [
                    [P(0.55, 0.79), P(0.69, 0.83), P(0.82, 0.86)],
                    [P(0.55, 0.79), P(0.7, 0.84), P(0.84, 0.87)]],
                lines: [
                    [P(0.12, 0.9), P(0.92, 0.9)]],
                ki: P(0.31, 0.68)),
            b: GlyphPose(head: P(0.24, 0.55),
                neck: P(0.3, 0.6),
                hip: P(0.56, 0.72),
                arms: [
                    [P(0.31, 0.61), P(0.3, 0.75), P(0.3, 0.88)]],
                legs: [
                    [P(0.56, 0.72), P(0.69, 0.79), P(0.82, 0.86)],
                    [P(0.56, 0.72), P(0.7, 0.8), P(0.84, 0.87)]],
                lines: [
                    [P(0.12, 0.9), P(0.92, 0.9)]],
                ki: P(0.31, 0.5))),
        .dips: GlyphSpec(
            a: GlyphPose(head: P(0.4, 0.32), neck: P(0.4, 0.4), hip: P(0.44, 0.64),
                         arms: [[P(0.4, 0.41), P(0.5, 0.47), P(0.44, 0.5)]],
                         legs: [[P(0.44, 0.64), P(0.52, 0.76), P(0.42, 0.84)],
                                [P(0.44, 0.64), P(0.54, 0.78), P(0.44, 0.86)]],
                         lines: [[P(0.26, 0.5), P(0.58, 0.5)], [P(0.64, 0.5), P(0.8, 0.5)]],
                         ki: P(0.4, 0.22)),
            b: GlyphPose(head: P(0.4, 0.24), neck: P(0.4, 0.32), hip: P(0.44, 0.56),
                         arms: [[P(0.4, 0.33), P(0.42, 0.42), P(0.44, 0.5)]],
                         legs: [[P(0.44, 0.56), P(0.5, 0.7), P(0.4, 0.78)],
                                [P(0.44, 0.56), P(0.52, 0.72), P(0.42, 0.8)]],
                         lines: [[P(0.26, 0.5), P(0.58, 0.5)], [P(0.64, 0.5), P(0.8, 0.5)]],
                         ki: P(0.4, 0.16)),
            readPhase: 0.75),
        .tricepPushdown: GlyphSpec(
            a: GlyphPose(head: P(0.4, 0.2),
                neck: P(0.4, 0.28),
                hip: P(0.4, 0.56),
                arms: [
                    [P(0.4, 0.3), P(0.43, 0.44), P(0.51, 0.34)]],
                legs: [
                    [P(0.4, 0.56), P(0.39, 0.7), P(0.39, 0.86)],
                    [P(0.4, 0.56), P(0.45, 0.7), P(0.47, 0.86)]],
                discs: [P(0.51, 0.34)],
                lines: [
                    [P(0.58, 0.07), P(0.51, 0.34)]],
                ki: P(0.51, 0.36)),
            b: GlyphPose(head: P(0.4, 0.2),
                neck: P(0.4, 0.28),
                hip: P(0.4, 0.56),
                arms: [
                    [P(0.4, 0.3), P(0.43, 0.44), P(0.49, 0.57)]],
                legs: [
                    [P(0.4, 0.56), P(0.39, 0.7), P(0.39, 0.86)],
                    [P(0.4, 0.56), P(0.45, 0.7), P(0.47, 0.86)]],
                discs: [P(0.49, 0.57)],
                lines: [
                    [P(0.58, 0.07), P(0.49, 0.57)]],
                ki: P(0.49, 0.66))),
        .skullCrusher: GlyphSpec(
            a: GlyphPose(head: P(0.2, 0.64),
                neck: P(0.28, 0.66),
                hip: P(0.52, 0.66),
                arms: [
                    [P(0.3, 0.66), P(0.3, 0.53), P(0.18, 0.57)]],
                legs: [
                    [P(0.52, 0.66), P(0.64, 0.72), P(0.68, 0.88)]],
                discs: [P(0.18, 0.57)],
                lines: [
                    [P(0.14, 0.74), P(0.66, 0.74)]],
                ki: P(0.16, 0.53)),
            b: GlyphPose(head: P(0.2, 0.64),
                neck: P(0.28, 0.66),
                hip: P(0.52, 0.66),
                arms: [
                    [P(0.3, 0.66), P(0.3, 0.53), P(0.3, 0.4)]],
                legs: [
                    [P(0.52, 0.66), P(0.64, 0.72), P(0.68, 0.88)]],
                discs: [P(0.3, 0.4)],
                lines: [
                    [P(0.14, 0.74), P(0.66, 0.74)]],
                ki: P(0.3, 0.3))),
        .tricepExtension: GlyphSpec(
            a: GlyphPose(head: P(0.42, 0.3), neck: P(0.42, 0.4), hip: P(0.42, 0.62),
                         arms: [[P(0.42, 0.42), P(0.5, 0.28), P(0.38, 0.22)]],
                         legs: [[P(0.42, 0.62), P(0.41, 0.74), P(0.4, 0.88)],
                                [P(0.42, 0.62), P(0.47, 0.74), P(0.48, 0.88)]],
                         dumbbells: [.init(c: P(0.35, 0.21), angle: 1.0)],
                         ki: P(0.64, 0.14)),
            b: GlyphPose(head: P(0.42, 0.3), neck: P(0.42, 0.4), hip: P(0.42, 0.62),
                         arms: [[P(0.42, 0.42), P(0.5, 0.26), P(0.56, 0.13)]],
                         legs: [[P(0.42, 0.62), P(0.41, 0.74), P(0.4, 0.88)],
                                [P(0.42, 0.62), P(0.47, 0.74), P(0.48, 0.88)]],
                         dumbbells: [.init(c: P(0.58, 0.1), angle: 0)],
                         ki: P(0.68, 0.08)),
            readPhase: 0.85),
        .frenchPress: GlyphSpec(
            a: GlyphPose(head: P(0.4, 0.32), neck: P(0.4, 0.42), hip: P(0.4, 0.68),
                         arms: [[P(0.4, 0.44), P(0.47, 0.3), P(0.36, 0.24)]],
                         legs: [[P(0.4, 0.68), P(0.54, 0.7), P(0.54, 0.86)],
                                [P(0.4, 0.68), P(0.56, 0.72), P(0.56, 0.87)]],
                         dumbbells: [.init(c: P(0.33, 0.23), angle: 1.0)],
                         lines: [[P(0.28, 0.72), P(0.56, 0.72)]],
                         ki: P(0.62, 0.14)),
            b: GlyphPose(head: P(0.4, 0.32), neck: P(0.4, 0.42), hip: P(0.4, 0.68),
                         arms: [[P(0.4, 0.44), P(0.47, 0.28), P(0.53, 0.15)]],
                         legs: [[P(0.4, 0.68), P(0.54, 0.7), P(0.54, 0.86)],
                                [P(0.4, 0.68), P(0.56, 0.72), P(0.56, 0.87)]],
                         dumbbells: [.init(c: P(0.55, 0.12), angle: 0)],
                         lines: [[P(0.28, 0.72), P(0.56, 0.72)]],
                         ki: P(0.66, 0.1)),
            readPhase: 0.85),
        .inclineBicepCurl: GlyphSpec(
            a: GlyphPose(head: P(0.36, 0.42), neck: P(0.42, 0.5), hip: P(0.56, 0.66),
                         arms: [[P(0.43, 0.52), P(0.45, 0.64), P(0.46, 0.74)]],
                         legs: [[P(0.56, 0.66), P(0.66, 0.74), P(0.64, 0.88)]],
                         dumbbells: [.init(c: P(0.48, 0.77), angle: 2.88)],
                         lines: [[P(0.3, 0.38), P(0.64, 0.74)]],
                         ki: P(0.62, 0.5)),
            b: GlyphPose(head: P(0.36, 0.42), neck: P(0.42, 0.5), hip: P(0.56, 0.66),
                         arms: [[P(0.43, 0.52), P(0.45, 0.64), P(0.58, 0.58)]],
                         legs: [[P(0.56, 0.66), P(0.66, 0.74), P(0.64, 0.88)]],
                         dumbbells: [.init(c: P(0.6, 0.56), angle: 2.35)],
                         lines: [[P(0.3, 0.38), P(0.64, 0.74)]],
                         ki: P(0.68, 0.44)),
            readPhase: 0.65),
        .hammerBicepCurl: GlyphSpec(
            a: GlyphPose(head: P(0.4, 0.2),
                neck: P(0.4, 0.28),
                hip: P(0.4, 0.56),
                arms: [
                    [P(0.4, 0.3), P(0.43, 0.46), P(0.47, 0.6)]],
                legs: [
                    [P(0.4, 0.56), P(0.39, 0.7), P(0.39, 0.86)],
                    [P(0.4, 0.56), P(0.45, 0.7), P(0.47, 0.86)]],
                dumbbells: [.init(c: P(0.5, 0.61), angle: 1.571)],
                ki: P(0.62, 0.36)),
            b: GlyphPose(head: P(0.4, 0.2),
                neck: P(0.4, 0.28),
                hip: P(0.4, 0.56),
                arms: [
                    [P(0.4, 0.3), P(0.43, 0.46), P(0.58, 0.35)]],
                legs: [
                    [P(0.4, 0.56), P(0.39, 0.7), P(0.39, 0.86)],
                    [P(0.4, 0.56), P(0.45, 0.7), P(0.47, 0.86)]],
                dumbbells: [.init(c: P(0.61, 0.33), angle: 1.571)],
                ki: P(0.68, 0.22))),
        .preacherCurl: GlyphSpec(
            a: GlyphPose(head: P(0.34, 0.23),
                neck: P(0.33, 0.3),
                hip: P(0.3, 0.56),
                arms: [
                    [P(0.34, 0.32), P(0.48, 0.48), P(0.61, 0.61)]],
                legs: [
                    [P(0.3, 0.56), P(0.44, 0.6), P(0.46, 0.82)],
                    [P(0.3, 0.56), P(0.41, 0.61), P(0.43, 0.84)]],
                dumbbells: [.init(c: P(0.64, 0.64), angle: 2.356)],
                lines: [
                    [P(0.34, 0.36), P(0.58, 0.56)],
                    [P(0.18, 0.62), P(0.42, 0.62)]],
                ki: P(0.68, 0.7)),
            b: GlyphPose(head: P(0.34, 0.23),
                neck: P(0.33, 0.3),
                hip: P(0.3, 0.56),
                arms: [
                    [P(0.34, 0.32), P(0.48, 0.48), P(0.52, 0.32)]],
                legs: [
                    [P(0.3, 0.56), P(0.44, 0.6), P(0.46, 0.82)],
                    [P(0.3, 0.56), P(0.41, 0.61), P(0.43, 0.84)]],
                dumbbells: [.init(c: P(0.53, 0.28), angle: 0.244)],
                lines: [
                    [P(0.34, 0.36), P(0.58, 0.56)],
                    [P(0.18, 0.62), P(0.42, 0.62)]],
                ki: P(0.54, 0.19))),
        .concentrationCurl: GlyphSpec(
            a: GlyphPose(head: P(0.53, 0.28),
                neck: P(0.48, 0.36),
                hip: P(0.36, 0.56),
                arms: [
                    [P(0.48, 0.38), P(0.5, 0.58), P(0.51, 0.74)]],
                legs: [
                    [P(0.36, 0.56), P(0.56, 0.6), P(0.58, 0.82)],
                    [P(0.36, 0.56), P(0.53, 0.62), P(0.55, 0.84)]],
                dumbbells: [.init(c: P(0.51, 0.77), angle: 3.072)],
                lines: [
                    [P(0.24, 0.62), P(0.46, 0.62)]],
                ki: P(0.51, 0.82)),
            b: GlyphPose(head: P(0.53, 0.28),
                neck: P(0.48, 0.36),
                hip: P(0.36, 0.56),
                arms: [
                    [P(0.48, 0.38), P(0.5, 0.58), P(0.62, 0.49)]],
                legs: [
                    [P(0.36, 0.56), P(0.56, 0.6), P(0.58, 0.82)],
                    [P(0.36, 0.56), P(0.53, 0.62), P(0.55, 0.84)]],
                dumbbells: [.init(c: P(0.64, 0.46), angle: 0.925)],
                lines: [
                    [P(0.24, 0.62), P(0.46, 0.62)]],
                ki: P(0.7, 0.4))),
        .lateralRaise: GlyphSpec(
            a: GlyphPose(head: P(0.5, 0.18),
                neck: P(0.5, 0.26),
                hip: P(0.5, 0.56),
                arms: [
                    [P(0.44, 0.28), P(0.44, 0.4), P(0.43, 0.51)],
                    [P(0.56, 0.28), P(0.56, 0.4), P(0.57, 0.51)]],
                legs: [
                    [P(0.5, 0.56), P(0.44, 0.71), P(0.43, 0.87)],
                    [P(0.5, 0.56), P(0.56, 0.71), P(0.57, 0.87)]],
                dumbbells: [.init(c: P(0.43, 0.52), angle: 0), .init(c: P(0.57, 0.52), angle: 0)],
                ki: P(0.6, 0.54)),
            b: GlyphPose(head: P(0.5, 0.18),
                neck: P(0.5, 0.26),
                hip: P(0.5, 0.56),
                arms: [
                    [P(0.44, 0.28), P(0.32, 0.28), P(0.2, 0.27)],
                    [P(0.56, 0.28), P(0.68, 0.28), P(0.8, 0.27)]],
                legs: [
                    [P(0.5, 0.56), P(0.44, 0.71), P(0.43, 0.87)],
                    [P(0.5, 0.56), P(0.56, 0.71), P(0.57, 0.87)]],
                dumbbells: [.init(c: P(0.19, 0.27), angle: 1.571), .init(c: P(0.81, 0.27), angle: 1.571)],
                ki: P(0.83, 0.21))),
        .shoulderPress: GlyphSpec(
            a: GlyphPose(head: P(0.5, 0.22),
                neck: P(0.5, 0.29),
                hip: P(0.5, 0.58),
                arms: [
                    [P(0.44, 0.3), P(0.37, 0.4), P(0.41, 0.32)],
                    [P(0.56, 0.3), P(0.63, 0.4), P(0.59, 0.32)]],
                legs: [
                    [P(0.5, 0.58), P(0.45, 0.72), P(0.44, 0.87)],
                    [P(0.5, 0.58), P(0.55, 0.72), P(0.56, 0.87)]],
                bar: [P(0.22, 0.32), P(0.78, 0.32)],
                ki: P(0.5, 0.28)),
            b: GlyphPose(head: P(0.5, 0.22),
                neck: P(0.5, 0.29),
                hip: P(0.5, 0.58),
                arms: [
                    [P(0.44, 0.3), P(0.42, 0.2), P(0.41, 0.1)],
                    [P(0.56, 0.3), P(0.58, 0.2), P(0.59, 0.1)]],
                legs: [
                    [P(0.5, 0.58), P(0.45, 0.72), P(0.44, 0.87)],
                    [P(0.5, 0.58), P(0.55, 0.72), P(0.56, 0.87)]],
                bar: [P(0.22, 0.1), P(0.78, 0.1)],
                ki: P(0.5, 0.06))),
        .facePulls: GlyphSpec(
            a: GlyphPose(head: P(0.52, 0.2),
                neck: P(0.52, 0.28),
                hip: P(0.52, 0.56),
                arms: [
                    [P(0.52, 0.3), P(0.42, 0.26), P(0.32, 0.21)]],
                legs: [
                    [P(0.52, 0.56), P(0.51, 0.7), P(0.5, 0.87)],
                    [P(0.52, 0.56), P(0.56, 0.7), P(0.58, 0.87)]],
                lines: [
                    [P(0.1, 0.12), P(0.32, 0.21)]],
                ki: P(0.3, 0.2)),
            b: GlyphPose(head: P(0.52, 0.2),
                neck: P(0.52, 0.28),
                hip: P(0.52, 0.56),
                arms: [
                    [P(0.52, 0.3), P(0.64, 0.25), P(0.56, 0.19)]],
                legs: [
                    [P(0.52, 0.56), P(0.51, 0.7), P(0.5, 0.87)],
                    [P(0.52, 0.56), P(0.56, 0.7), P(0.58, 0.87)]],
                lines: [
                    [P(0.1, 0.12), P(0.56, 0.19)]],
                ki: P(0.65, 0.14))),
        .rearDeltFly: GlyphSpec(
            a: GlyphPose(head: P(0.66, 0.38), neck: P(0.58, 0.4), hip: P(0.4, 0.54),
                         arms: [[P(0.56, 0.42), P(0.57, 0.52), P(0.58, 0.62)]],
                         legs: [[P(0.4, 0.54), P(0.42, 0.7), P(0.41, 0.87)],
                                [P(0.4, 0.54), P(0.47, 0.7), P(0.46, 0.87)]],
                         dumbbells: [.init(c: P(0.6, 0.65), angle: 0.26)],
                         ki: P(0.66, 0.28)),
            b: GlyphPose(head: P(0.66, 0.38), neck: P(0.58, 0.4), hip: P(0.4, 0.54),
                         arms: [[P(0.56, 0.42), P(0.49, 0.42), P(0.41, 0.4)]],
                         legs: [[P(0.4, 0.54), P(0.42, 0.7), P(0.41, 0.87)],
                                [P(0.4, 0.54), P(0.47, 0.7), P(0.46, 0.87)]],
                         dumbbells: [.init(c: P(0.38, 0.39), angle: 1.4)],
                         ki: P(0.32, 0.32)),
            readPhase: 0.8),
        .latPullover: GlyphSpec(
            a: GlyphPose(head: P(0.45, 0.23),
                neck: P(0.42, 0.3),
                hip: P(0.36, 0.58),
                arms: [
                    [P(0.42, 0.31), P(0.52, 0.24), P(0.61, 0.18)]],
                legs: [
                    [P(0.36, 0.58), P(0.34, 0.72), P(0.33, 0.88)],
                    [P(0.36, 0.58), P(0.4, 0.72), P(0.42, 0.88)]],
                discs: [P(0.61, 0.18)],
                lines: [
                    [P(0.8, 0.08), P(0.61, 0.18)]],
                ki: P(0.66, 0.14)),
            b: GlyphPose(head: P(0.45, 0.23),
                neck: P(0.42, 0.3),
                hip: P(0.36, 0.58),
                arms: [
                    [P(0.42, 0.31), P(0.5, 0.42), P(0.55, 0.54)]],
                legs: [
                    [P(0.36, 0.58), P(0.34, 0.72), P(0.33, 0.88)],
                    [P(0.36, 0.58), P(0.4, 0.72), P(0.42, 0.88)]],
                discs: [P(0.55, 0.54)],
                lines: [
                    [P(0.8, 0.08), P(0.55, 0.54)]],
                ki: P(0.6, 0.62))),
        .bentOverRow: GlyphSpec(
            a: GlyphPose(head: P(0.68, 0.36), neck: P(0.6, 0.38), hip: P(0.4, 0.52),
                         arms: [[P(0.58, 0.4), P(0.59, 0.52), P(0.6, 0.64)]],
                         legs: [[P(0.4, 0.52), P(0.42, 0.68), P(0.4, 0.87)],
                                [P(0.4, 0.52), P(0.48, 0.68), P(0.46, 0.87)]],
                         discs: [P(0.6, 0.67)],
                         ki: P(0.6, 0.3)),
            b: GlyphPose(head: P(0.68, 0.36), neck: P(0.6, 0.38), hip: P(0.4, 0.52),
                         arms: [[P(0.58, 0.4), P(0.54, 0.42), P(0.58, 0.5)]],
                         legs: [[P(0.4, 0.52), P(0.42, 0.68), P(0.4, 0.87)],
                                [P(0.4, 0.52), P(0.48, 0.68), P(0.46, 0.87)]],
                         discs: [P(0.58, 0.53)],
                         ki: P(0.66, 0.24)),
            readPhase: 0.55),
        .pullUp: GlyphSpec(
            a: GlyphPose(head: P(0.5, 0.36), neck: P(0.5, 0.43), hip: P(0.5, 0.66),
                         arms: [[P(0.44, 0.44), P(0.38, 0.32), P(0.34, 0.2)],
                                [P(0.56, 0.44), P(0.62, 0.32), P(0.66, 0.2)]],
                         legs: [[P(0.5, 0.66), P(0.48, 0.78), P(0.4, 0.84)],
                                [P(0.5, 0.66), P(0.52, 0.79), P(0.44, 0.86)]],
                         lines: [[P(0.22, 0.2), P(0.78, 0.2)]],
                         ki: P(0.5, 0.1)),
            b: GlyphPose(head: P(0.5, 0.28), neck: P(0.5, 0.35), hip: P(0.5, 0.58),
                         arms: [[P(0.44, 0.36), P(0.37, 0.28), P(0.34, 0.2)],
                                [P(0.56, 0.36), P(0.63, 0.28), P(0.66, 0.2)]],
                         legs: [[P(0.5, 0.58), P(0.48, 0.72), P(0.4, 0.78)],
                                [P(0.5, 0.58), P(0.52, 0.73), P(0.44, 0.8)]],
                         lines: [[P(0.22, 0.2), P(0.78, 0.2)]],
                         ki: P(0.5, 0.1)),
            readPhase: 0.8),
        .row: GlyphSpec(
            a: GlyphPose(head: P(0.54, 0.3),
                neck: P(0.56, 0.38),
                hip: P(0.58, 0.6),
                arms: [
                    [P(0.56, 0.4), P(0.44, 0.44), P(0.32, 0.46)]],
                legs: [
                    [P(0.58, 0.6), P(0.42, 0.64), P(0.3, 0.76)],
                    [P(0.58, 0.6), P(0.44, 0.66), P(0.32, 0.78)]],
                discs: [P(0.32, 0.46)],
                lines: [
                    [P(0.48, 0.66), P(0.7, 0.66)],
                    [P(0.14, 0.46), P(0.32, 0.46)]],
                ki: P(0.3, 0.46)),
            b: GlyphPose(head: P(0.54, 0.3),
                neck: P(0.56, 0.38),
                hip: P(0.58, 0.6),
                arms: [
                    [P(0.56, 0.4), P(0.66, 0.48), P(0.54, 0.5)]],
                legs: [
                    [P(0.58, 0.6), P(0.42, 0.64), P(0.3, 0.76)],
                    [P(0.58, 0.6), P(0.44, 0.66), P(0.32, 0.78)]],
                discs: [P(0.54, 0.5)],
                lines: [
                    [P(0.48, 0.66), P(0.7, 0.66)],
                    [P(0.14, 0.46), P(0.54, 0.5)]],
                ki: P(0.74, 0.46))),
        .deadlift: GlyphSpec(
            a: GlyphPose(head: P(0.66, 0.38), neck: P(0.58, 0.4), hip: P(0.42, 0.52),
                         arms: [[P(0.57, 0.42), P(0.58, 0.54), P(0.58, 0.66)]],
                         legs: [[P(0.42, 0.52), P(0.44, 0.66), P(0.42, 0.86)],
                                [P(0.42, 0.52), P(0.5, 0.67), P(0.48, 0.87)]],
                         discs: [P(0.58, 0.69)],
                         ki: P(0.58, 0.3)),
            b: GlyphPose(head: P(0.46, 0.2), neck: P(0.46, 0.28), hip: P(0.46, 0.54),
                         arms: [[P(0.46, 0.3), P(0.47, 0.44), P(0.48, 0.56)]],
                         legs: [[P(0.46, 0.54), P(0.45, 0.7), P(0.44, 0.86)],
                                [P(0.46, 0.54), P(0.51, 0.7), P(0.5, 0.87)]],
                         discs: [P(0.48, 0.59)],
                         ki: P(0.46, 0.14)),
            readPhase: 0.2),
        .hackSquat: GlyphSpec(
            a: GlyphPose(head: P(0.6, 0.38), neck: P(0.54, 0.46), hip: P(0.42, 0.64),
                         arms: [[P(0.53, 0.48), P(0.58, 0.54), P(0.56, 0.6)]],
                         legs: [[P(0.42, 0.64), P(0.26, 0.6), P(0.22, 0.74)],
                                [P(0.42, 0.64), P(0.3, 0.64), P(0.26, 0.78)]],
                         lines: [[P(0.24, 0.84), P(0.66, 0.28)], [P(0.16, 0.76), P(0.3, 0.88)]],
                         ki: P(0.7, 0.3)),
            b: GlyphPose(head: P(0.68, 0.28), neck: P(0.62, 0.36), hip: P(0.5, 0.54),
                         arms: [[P(0.61, 0.38), P(0.66, 0.44), P(0.64, 0.5)]],
                         legs: [[P(0.5, 0.54), P(0.36, 0.66), P(0.26, 0.78)],
                                [P(0.5, 0.54), P(0.4, 0.7), P(0.3, 0.82)]],
                         lines: [[P(0.24, 0.84), P(0.66, 0.28)], [P(0.16, 0.76), P(0.3, 0.88)]],
                         ki: P(0.76, 0.22)),
            readPhase: 0.35),
        .bulgarianSplitSquat: GlyphSpec(
            a: GlyphPose(head: P(0.41, 0.34),
                neck: P(0.43, 0.41),
                hip: P(0.47, 0.67),
                arms: [
                    [P(0.43, 0.42), P(0.45, 0.53), P(0.47, 0.64)]],
                legs: [
                    [P(0.47, 0.67), P(0.33, 0.72), P(0.41, 0.86)],
                    [P(0.47, 0.67), P(0.62, 0.71), P(0.7, 0.58)]],
                dumbbells: [.init(c: P(0.47, 0.65), angle: 2.967)],
                lines: [
                    [P(0.66, 0.6), P(0.88, 0.6)],
                    [P(0.77, 0.6), P(0.77, 0.86)],
                    [P(0.18, 0.87), P(0.88, 0.87)]],
                ki: P(0.43, 0.26)),
            b: GlyphPose(head: P(0.44, 0.22),
                neck: P(0.44, 0.29),
                hip: P(0.44, 0.54),
                arms: [
                    [P(0.44, 0.3), P(0.45, 0.41), P(0.46, 0.52)]],
                legs: [
                    [P(0.44, 0.54), P(0.42, 0.7), P(0.41, 0.86)],
                    [P(0.44, 0.54), P(0.56, 0.66), P(0.7, 0.58)]],
                dumbbells: [.init(c: P(0.46, 0.53), angle: 3.054)],
                lines: [
                    [P(0.66, 0.6), P(0.88, 0.6)],
                    [P(0.77, 0.6), P(0.77, 0.86)],
                    [P(0.18, 0.87), P(0.88, 0.87)]],
                ki: P(0.44, 0.1))),
        .legExtension: GlyphSpec(
            a: GlyphPose(head: P(0.6, 0.23),
                neck: P(0.6, 0.3),
                hip: P(0.58, 0.56),
                arms: [
                    [P(0.6, 0.32), P(0.62, 0.43), P(0.61, 0.53)]],
                legs: [
                    [P(0.58, 0.56), P(0.4, 0.57), P(0.41, 0.74)],
                    [P(0.58, 0.56), P(0.42, 0.58), P(0.43, 0.75)]],
                discs: [P(0.41, 0.74)],
                lines: [
                    [P(0.46, 0.58), P(0.8, 0.58)],
                    [P(0.63, 0.3), P(0.67, 0.58)]],
                ki: P(0.41, 0.8)),
            b: GlyphPose(head: P(0.6, 0.23),
                neck: P(0.6, 0.3),
                hip: P(0.58, 0.56),
                arms: [
                    [P(0.6, 0.32), P(0.62, 0.43), P(0.61, 0.53)]],
                legs: [
                    [P(0.58, 0.56), P(0.4, 0.57), P(0.23, 0.55)],
                    [P(0.58, 0.56), P(0.42, 0.58), P(0.25, 0.56)]],
                discs: [P(0.23, 0.55)],
                lines: [
                    [P(0.46, 0.58), P(0.8, 0.58)],
                    [P(0.63, 0.3), P(0.67, 0.58)]],
                ki: P(0.13, 0.54))),
        .legCurl: GlyphSpec(
            a: GlyphPose(head: P(0.2, 0.62), neck: P(0.28, 0.64), hip: P(0.52, 0.66),
                         arms: [[P(0.3, 0.65), P(0.26, 0.72), P(0.22, 0.76)]],
                         legs: [[P(0.52, 0.66), P(0.64, 0.68), P(0.78, 0.68)]],
                         discs: [P(0.81, 0.66)],
                         lines: [[P(0.14, 0.72), P(0.7, 0.72)]],
                         ki: P(0.8, 0.56)),
            b: GlyphPose(head: P(0.2, 0.62), neck: P(0.28, 0.64), hip: P(0.52, 0.66),
                         arms: [[P(0.3, 0.65), P(0.26, 0.72), P(0.22, 0.76)]],
                         legs: [[P(0.52, 0.66), P(0.64, 0.68), P(0.64, 0.5)]],
                         discs: [P(0.64, 0.46)],
                         lines: [[P(0.14, 0.72), P(0.7, 0.72)]],
                         ki: P(0.72, 0.4)),
            readPhase: 0.85),
        .hipThrust: GlyphSpec(
            a: GlyphPose(head: P(0.73, 0.44),
                neck: P(0.67, 0.49),
                hip: P(0.53, 0.63),
                arms: [
                    [P(0.66, 0.51), P(0.63, 0.58), P(0.55, 0.57)]],
                legs: [
                    [P(0.53, 0.63), P(0.37, 0.53), P(0.3, 0.74)],
                    [P(0.53, 0.63), P(0.38, 0.55), P(0.34, 0.75)]],
                discs: [P(0.54, 0.57)],
                lines: [
                    [P(0.68, 0.5), P(0.9, 0.5)],
                    [P(0.8, 0.5), P(0.8, 0.76)],
                    [P(0.1, 0.76), P(0.9, 0.76)]],
                ki: P(0.54, 0.51)),
            b: GlyphPose(head: P(0.74, 0.45),
                neck: P(0.67, 0.49),
                hip: P(0.48, 0.49),
                arms: [
                    [P(0.66, 0.51), P(0.58, 0.52), P(0.5, 0.44)]],
                legs: [
                    [P(0.48, 0.49), P(0.28, 0.5), P(0.3, 0.74)],
                    [P(0.48, 0.49), P(0.28, 0.52), P(0.34, 0.75)]],
                discs: [P(0.49, 0.43)],
                lines: [
                    [P(0.68, 0.5), P(0.9, 0.5)],
                    [P(0.8, 0.5), P(0.8, 0.76)],
                    [P(0.1, 0.76), P(0.9, 0.76)]],
                ki: P(0.49, 0.31))),
        .sumoDeadlift: GlyphSpec(
            a: GlyphPose(head: P(0.5, 0.32),
                neck: P(0.5, 0.4),
                hip: P(0.5, 0.6),
                arms: [
                    [P(0.44, 0.41), P(0.44, 0.55), P(0.44, 0.7)],
                    [P(0.56, 0.41), P(0.56, 0.55), P(0.56, 0.7)]],
                legs: [
                    [P(0.5, 0.6), P(0.29, 0.65), P(0.24, 0.86)],
                    [P(0.5, 0.6), P(0.71, 0.65), P(0.76, 0.86)]],
                bar: [P(0.16, 0.7), P(0.84, 0.7)],
                ki: P(0.5, 0.66)),
            b: GlyphPose(head: P(0.5, 0.16),
                neck: P(0.5, 0.24),
                hip: P(0.5, 0.48),
                arms: [
                    [P(0.44, 0.25), P(0.44, 0.38), P(0.44, 0.52)],
                    [P(0.56, 0.25), P(0.56, 0.38), P(0.56, 0.52)]],
                legs: [
                    [P(0.5, 0.48), P(0.37, 0.65), P(0.24, 0.86)],
                    [P(0.5, 0.48), P(0.63, 0.65), P(0.76, 0.86)]],
                bar: [P(0.16, 0.52), P(0.84, 0.52)],
                ki: P(0.5, 0.44))),
        .romanianDeadlift: GlyphSpec(
            a: GlyphPose(head: P(0.72, 0.42), neck: P(0.64, 0.43), hip: P(0.42, 0.5),
                         arms: [[P(0.62, 0.45), P(0.62, 0.58), P(0.62, 0.7)]],
                         legs: [[P(0.42, 0.5), P(0.43, 0.68), P(0.42, 0.87)],
                                [P(0.42, 0.5), P(0.49, 0.68), P(0.48, 0.87)]],
                         discs: [P(0.62, 0.73)],
                         ki: P(0.62, 0.32)),
            b: GlyphPose(head: P(0.48, 0.2), neck: P(0.48, 0.28), hip: P(0.48, 0.54),
                         arms: [[P(0.48, 0.3), P(0.49, 0.44), P(0.5, 0.56)]],
                         legs: [[P(0.48, 0.54), P(0.47, 0.7), P(0.46, 0.87)],
                                [P(0.48, 0.54), P(0.53, 0.7), P(0.52, 0.87)]],
                         discs: [P(0.5, 0.59)],
                         ki: P(0.48, 0.14)),
            readPhase: 0.12),
        .standingCalfRaises: GlyphSpec(
            a: GlyphPose(head: P(0.48, 0.22),
                neck: P(0.48, 0.29),
                hip: P(0.48, 0.55),
                arms: [
                    [P(0.48, 0.31), P(0.49, 0.43), P(0.5, 0.55)]],
                legs: [
                    [P(0.48, 0.55), P(0.47, 0.69), P(0.46, 0.83)],
                    [P(0.48, 0.55), P(0.5, 0.69), P(0.49, 0.83)]],
                dumbbells: [.init(c: P(0.52, 0.56), angle: 3.054)],
                lines: [
                    [P(0.5, 0.8), P(0.72, 0.8)],
                    [P(0.5, 0.8), P(0.5, 0.86)]],
                ki: P(0.48, 0.15)),
            b: GlyphPose(head: P(0.48, 0.14),
                neck: P(0.48, 0.21),
                hip: P(0.48, 0.47),
                arms: [
                    [P(0.48, 0.23), P(0.49, 0.35), P(0.5, 0.47)]],
                legs: [
                    [P(0.48, 0.47), P(0.47, 0.61), P(0.48, 0.75)],
                    [P(0.48, 0.47), P(0.5, 0.61), P(0.51, 0.75)]],
                dumbbells: [.init(c: P(0.52, 0.48), angle: 3.054)],
                lines: [
                    [P(0.5, 0.8), P(0.72, 0.8)],
                    [P(0.5, 0.8), P(0.5, 0.86)]],
                ki: P(0.48, 0.07))),
        .seatedCalfRaises: GlyphSpec(
            a: GlyphPose(head: P(0.39, 0.26),
                neck: P(0.38, 0.33),
                hip: P(0.36, 0.58),
                arms: [
                    [P(0.39, 0.35), P(0.46, 0.45), P(0.54, 0.53)]],
                legs: [
                    [P(0.36, 0.58), P(0.56, 0.58), P(0.55, 0.82)],
                    [P(0.36, 0.58), P(0.57, 0.61), P(0.56, 0.85)]],
                discs: [P(0.57, 0.54)],
                lines: [
                    [P(0.26, 0.63), P(0.44, 0.63)],
                    [P(0.52, 0.86), P(0.7, 0.86)]],
                ki: P(0.58, 0.5)),
            b: GlyphPose(head: P(0.39, 0.26),
                neck: P(0.38, 0.33),
                hip: P(0.36, 0.58),
                arms: [
                    [P(0.39, 0.35), P(0.46, 0.42), P(0.54, 0.49)]],
                legs: [
                    [P(0.36, 0.58), P(0.56, 0.54), P(0.55, 0.78)],
                    [P(0.36, 0.58), P(0.57, 0.57), P(0.56, 0.81)]],
                discs: [P(0.57, 0.5)],
                lines: [
                    [P(0.26, 0.63), P(0.44, 0.63)],
                    [P(0.52, 0.86), P(0.7, 0.86)]],
                ki: P(0.58, 0.42))),
        .kickbacks: GlyphSpec(
            a: GlyphPose(head: P(0.29, 0.22),
                neck: P(0.33, 0.29),
                hip: P(0.45, 0.51),
                arms: [
                    [P(0.34, 0.31), P(0.27, 0.4), P(0.21, 0.47)]],
                legs: [
                    [P(0.45, 0.51), P(0.43, 0.69), P(0.42, 0.86)],
                    [P(0.45, 0.51), P(0.36, 0.65), P(0.41, 0.81)]],
                discs: [P(0.41, 0.81)],
                lines: [
                    [P(0.2, 0.28), P(0.2, 0.62)]],
                ki: P(0.45, 0.85)),
            b: GlyphPose(head: P(0.29, 0.22),
                neck: P(0.33, 0.29),
                hip: P(0.45, 0.51),
                arms: [
                    [P(0.34, 0.31), P(0.27, 0.4), P(0.21, 0.47)]],
                legs: [
                    [P(0.45, 0.51), P(0.43, 0.69), P(0.42, 0.86)],
                    [P(0.45, 0.51), P(0.61, 0.45), P(0.77, 0.38)]],
                discs: [P(0.77, 0.38)],
                lines: [
                    [P(0.2, 0.28), P(0.2, 0.62)]],
                ki: P(0.85, 0.32))),
    ]
    // END GENERATED SPECS
}

// MARK: - Views

/// Renders one glyph as a FILLED warrior silhouette with a soft aura: a blurred
/// tint bloom beneath, the equipment a shade quieter, the body and ki solid. Pure
/// vector — crisp at any size ("resolution" is free).
struct ExerciseGlyphView: View {
    enum Source {
        case movement(ExerciseGlyphKey)
        case muscle(Muscle)
    }

    let source: Source
    var color: Color = SettColor.heroCyan

    init(key: ExerciseGlyphKey, color: Color = SettColor.heroCyan) {
        self.source = .movement(key)
        self.color = color
    }

    init(muscle: Muscle, color: Color = SettColor.heroCyan) {
        self.source = .muscle(muscle)
        self.color = color
    }

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: CGSize(width: min(size.width, size.height),
                                                          height: min(size.width, size.height)))
            let layers: GlyphRig.Layers = switch source {
            case .movement(let key): Glyphs.layers(for: key, in: rect)
            case .muscle(let muscle): Glyphs.muscleLayers(for: muscle, in: rect)
            }
            // Aura — the whole figure bloomed beneath itself.
            ctx.drawLayer { aura in
                aura.addFilter(.blur(radius: rect.width * 0.045))
                aura.fill(layers.combined, with: .color(color.opacity(0.5)))
            }
            // The mark itself, with the muscle cuts / plate holes PUNCHED out of it —
            // negative space is what turns a stick figure into an emblem.
            ctx.drawLayer { mark in
                mark.fill(layers.gear, with: .color(color.opacity(0.78)))
                mark.fill(layers.body, with: .color(color))
                mark.fill(layers.ki, with: .color(color.opacity(0.9)))
                mark.blendMode = .destinationOut
                mark.fill(layers.cuts, with: .color(.white))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Exercise icon (art → muscle art → vector glyph fallback)

/// Drop-in exercise icon. Resolution order:
/// 1. generated Saiyan ART for the movement (circular, tier-ringed),
/// 2. generated art for the muscle group (custom exercises),
/// 3. the vector warrior glyph / muscle emblem (never an empty icon).
struct ExerciseIcon: View {
    let name: String
    let equipment: Equipment
    var muscle: Muscle = .other
    var size: CGFloat = 28
    var color: Color = SettColor.heroCyan

    var body: some View {
        if let asset = ExerciseArt.movementAsset(for: name) ?? ExerciseArt.muscleAsset(for: muscle) {
            ExerciseArtView(asset: asset, size: size, color: color)
        } else {
            Group {
                if let key = ExerciseGlyphKey.forName(name) {
                    ExerciseGlyphView(key: key, color: color)
                } else {
                    ExerciseGlyphView(muscle: muscle, color: color)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

#if DEBUG
/// Contact sheet of all 39 movement glyphs + the 8 muscle emblems — for visual QA.
/// Shown via SETT_DEBUG_GLYPHS=1.
struct ExerciseGlyphContactSheet: View {
    /// SETT_DEBUG_GLYPHS=1 → first 24 movements; =2 → the rest + muscle emblems.
    var page = ProcessInfo.processInfo.environment["SETT_DEBUG_GLYPHS"] ?? "1"
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    /// Every movement name in the top-50 catalog (for the art QA page).
    private var allMovementNames: [String] {
        ExerciseGlyphKey.allCases.map(\.displayName) + [
            "Lunges", "Leg Press", "Shrugs", "Upright Row", "Front Raise",
            "Back Extension", "Crunches", "Plank", "Hanging Leg Raise",
            "Russian Twist", "Farmers Carry",
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if page == "3" {
                    // Generated-art QA: icons resolve art-first (vector fallback).
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(allMovementNames, id: \.self) { name in
                            VStack(spacing: 3) {
                                ExerciseIcon(name: name, equipment: .barbell, size: 62)
                                Text(name)
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(SettColor.ash)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    Text("MUSCLE ART (custom-exercise defaults)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.ash)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Muscle.allCases, id: \.self) { muscle in
                            VStack(spacing: 3) {
                                ExerciseIcon(name: "?", equipment: .bodyweight, muscle: muscle, size: 62)
                                Text(muscle.rawValue.capitalized)
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(SettColor.ash)
                            }
                        }
                    }
                } else if page == "2" {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ExerciseGlyphKey.allCases.dropFirst(24), id: \.self) { key in
                            tile(ExerciseGlyphView(key: key), label: key.displayName)
                        }
                    }
                    Text("MUSCLE EMBLEMS (custom-exercise defaults)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .kerning(1.5)
                        .foregroundStyle(SettColor.ash)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Muscle.allCases, id: \.self) { muscle in
                            tile(ExerciseGlyphView(muscle: muscle), label: muscle.rawValue.capitalized)
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ExerciseGlyphKey.allCases.prefix(24), id: \.self) { key in
                            tile(ExerciseGlyphView(key: key), label: key.displayName)
                        }
                    }
                }
            }
            .padding(10)
        }
        .dungeonBackground()
    }

    private func tile(_ glyph: ExerciseGlyphView, label: String) -> some View {
        VStack(spacing: 3) {
            glyph
                .frame(width: 62, height: 62)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TimeChamber.void.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(SettColor.heroCyan.opacity(0.25), lineWidth: 1)
                        }
                }
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(SettColor.ash)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}
#endif

// MARK: - Icon Lab (SETT_DEBUG_ICONLAB=1) — compare art-legibility treatments
//
// The Gemini art is ~95% dark linework (avg luminance 35/255): a glowing-figure-in-
// the-dark look that reads at 200px but goes to mud at 28-44pt. This sheet renders the
// same exercises across candidate fixes at BOTH real sizes so we can pick with our eyes.

enum IconTreatment: String, CaseIterable, Identifiable {
    case now        // current screen-blend medallion (baseline)
    case boost      // normal blend + moderate brighten/contrast/saturate
    case boostPlus  // normal blend + heavy brighten/contrast/saturate
    case duotone    // luminance→alpha recolor: solid tier-hue neon figure
    var id: String { rawValue }
    var label: String {
        switch self {
        case .now: return "NOW"
        case .boost: return "BOOST"
        case .boostPlus: return "BOOST+"
        case .duotone: return "DUOTONE"
        }
    }
}

/// One candidate rendering of an art asset. `.now` reuses the shipped medallion; the
/// others draw on a dark tier-ringed disc so we compare the *art treatment*, not framing.
struct IconTreatmentView: View {
    let asset: String
    let treatment: IconTreatment
    var size: CGFloat = 44
    var color: Color = SettColor.heroCyan

    var body: some View {
        switch treatment {
        case .now:
            ExerciseArtView(asset: asset, size: size, color: color)
        case .boost:
            disc { boosted(sat: 1.6, con: 1.35, bri: 0.05) }
        case .boostPlus:
            disc { boosted(sat: 2.0, con: 1.7, bri: 0.12) }
        case .duotone:
            disc {
                // Solid tier hue, masked by the art's own luminance: the bright 5%
                // (gold torso + hot aura + brightest cyan) becomes an opaque neon shape,
                // the dark 95% drops out. A crisp single-hue mark that survives 28pt.
                Circle()
                    .fill(RadialGradient(
                        colors: [color, color.opacity(0.75)],
                        center: .center, startRadius: 0, endRadius: size * 0.55))
                    .mask {
                        Image(asset).resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .contrast(1.5).brightness(0.02)
                            .luminanceToAlpha()
                    }
            }
        }
    }

    private func boosted(sat: Double, con: Double, bri: Double) -> some View {
        Image(asset).resizable().scaledToFill()
            .frame(width: size, height: size)
            .saturation(sat).contrast(con).brightness(bri)
    }

    @ViewBuilder private func disc<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [color.opacity(0.16), TimeChamber.void.opacity(0.98)],
                center: .center, startRadius: 0, endRadius: size * 0.6))
            content()
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(color.opacity(0.9), lineWidth: max(1.5, size / 15)) }
        .shadow(color: color.opacity(0.45), radius: size * 0.16)
    }
}

#if DEBUG
/// Side-by-side comparison of icon-legibility treatments. Shown via SETT_DEBUG_ICONLAB=1.
struct IconLabSheet: View {
    /// Representative + worst-case exercises (shrugs was the tightest/faintest).
    private let samples: [(String, Color)] = [
        ("Flat Bench Press", SettColor.heroCyan),
        ("Squat", SettColor.heroCyan),
        ("Deadlift", SettColor.heroCyan),
        ("Bicep Curl", SettColor.heroCyan),
        ("Lat Pulldown", SettColor.heroCyan),
        ("Shrugs", SettColor.heroCyan),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                block(size: 44, caption: "AT 44pt  (exercise card / player header)")
                block(size: 28, caption: "AT 28pt  (dense lists — the hard case)")
            }
            .padding(14)
        }
        .dungeonBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ICON LAB")
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).kerning(2)
                .foregroundStyle(SettColor.bone)
            HStack(spacing: 10) {
                ForEach(IconTreatment.allCases) { t in
                    Text(t.label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).kerning(1)
                        .foregroundStyle(SettColor.ash)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, 70)
        }
    }

    private func block(size: CGFloat, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.system(size: 9, weight: .bold, design: .monospaced)).kerning(1.2)
                .foregroundStyle(SettColor.heroCyan.opacity(0.8))
            ForEach(samples, id: \.0) { name, color in
                if let asset = ExerciseArt.movementAsset(for: name) {
                    HStack(spacing: 10) {
                        Text(name.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SettColor.ash)
                            .frame(width: 60, alignment: .leading)
                            .lineLimit(2)
                        ForEach(IconTreatment.allCases) { t in
                            IconTreatmentView(asset: asset, treatment: t, size: size, color: color)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TimeChamber.void.opacity(0.4))
        }
    }
}
#endif
