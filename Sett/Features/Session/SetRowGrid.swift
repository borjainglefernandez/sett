import SwiftUI
import SettCore
import UniformTypeIdentifiers

// MARK: - Live long-press-drag reordering (system drag interaction)

/// `.onDrag` lifts a row/card on long-press; this delegate reorders the model live as
/// the drag hovers each sibling, and the move commits through the store (persisted as
/// you go, so releasing anywhere is safe). No edit mode, no handles — reorder from the
/// get-go. `Item.ID` is the model's UUID.
struct ReorderDropDelegate<Item: Identifiable>: DropDelegate where Item.ID: Equatable {
    let target: Item
    let items: [Item]
    @Binding var dragging: Item?
    let move: (IndexSet, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != target.id,
              let from = items.firstIndex(where: { $0.id == dragging.id }),
              let to = items.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            move(IndexSet(integer: from), to > from ? to + 1 : to)
        }
        Haptics.selection()
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// The ONE source of truth for a "vs last week" PWR delta's glyph + colour, so the
/// scouter (SetPlayerView) and the overview rows (ExerciseCard) can never disagree
/// about the same number: ▲ ahead (green), ▼ behind (red), and on a CUT a dip is
/// neutral — ▽ in ash, never penalised.
enum VsLast {
    static func label(_ delta: Int, phase: TrainingPhase) -> String {
        if delta > 0 { return "▲+\(delta)" }
        if delta == 0 { return "◇0" }
        return phase == .cutting ? "▽\(abs(delta))" : "▼\(abs(delta))"
    }
    static func color(_ delta: Int, phase: TrainingPhase) -> Color {
        if delta > 0 { return SettColor.positive }
        if delta == 0 { return TimeChamber.teal }
        return phase == .cutting ? SettColor.ash : SettColor.negative
    }
}

/// The single source of truth for the overview set-row column grid. Adopted by
/// `ExerciseCard.setRow` (logged), `ExerciseCard.plannedRow` (planned), AND
/// `SetEntryRow` (active input) so all three read as ONE aligned column: the weight
/// values stack (right-aligned on the unit), the `×` is a fixed seam, the reps stack
/// (left-aligned), every badge is 24 pt, every row 44 pt. Both ± gutters are reserved
/// in every row — real micro-steppers in the active row, clear space elsewhere — so
/// the value edges land on the same x whether or not a stepper is present.
enum SetRowGrid {
    static let badge: CGFloat = 24
    static let badgeGap: CGFloat = 10
    static let weightCell: CGFloat = 76   // "157.5 lb" mono-15 bold, right-aligned
    /// A single ± flank column — a hairline − sits left of a value, a + right of it.
    /// FOUR of these (weight −, weight +, reps −, reps +) replace the old two 28pt
    /// stepper gutters, so 4×14 = 2×28: the value cells keep their exact x (no
    /// realignment) and the steppers become sleek flanking glyphs, not a chunky box.
    static let stepFlank: CGFloat = 14   // ± glyph flank (also reserved as a clear gutter in logged/planned rows); tap target is 44pt tall
    /// Breathing room between a value and its inner ± glyph, so a − never reads as a
    /// negation of the number (e.g. "− 8" not "−8"). Lives INSIDE the value cell, so it
    /// costs no width and the shared column stays aligned.
    static let valueInset: CGFloat = 5
    static let times: CGFloat = 18        // the "×" anchor
    static let repsCell: CGFloat = 26     // up to "99", left-aligned
    static let rowHeight: CGFloat = 44
    static let hPad: CGFloat = 10
}

/// The weight / × / reps value columns for the NON-editable rows (logged + planned).
/// Reserves the FOUR ± flank columns as clear space (weight −, weight +, reps −, reps +)
/// so the `×` and both value edges sit at the exact same x as the active input row's
/// real flanking steppers.
@ViewBuilder
func setValueColumns(weightText: String, repsText: String,
                     valueColor: Color, weight: Font.Weight) -> some View {
    Color.clear.frame(width: SetRowGrid.stepFlank, height: 1)   // weight −
    Text(weightText)
        .font(.system(size: 15, weight: weight, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(valueColor)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.trailing, SetRowGrid.valueInset)              // gap to the + flank
        .frame(width: SetRowGrid.weightCell, height: SetRowGrid.rowHeight, alignment: .trailing)
    Color.clear.frame(width: SetRowGrid.stepFlank, height: 1)   // weight +
    Text("×")
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundStyle(SettColor.iron)
        .frame(width: SetRowGrid.times)
    Color.clear.frame(width: SetRowGrid.stepFlank, height: 1)   // reps −
    Text(repsText)
        .font(.system(size: 15, weight: weight, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(valueColor)
        .padding(.leading, SetRowGrid.valueInset)               // gap from the − flank
        .frame(width: SetRowGrid.repsCell, height: SetRowGrid.rowHeight, alignment: .leading)
    Color.clear.frame(width: SetRowGrid.stepFlank, height: 1)   // reps +
}

// MARK: - Set index badge (ONE badge for every overview set-row index)

/// The single badge for every set-row index — logged, active, planned, warm-up. Every
/// state draws the IDENTICAL silhouette (a 24pt disc + a solid inset ring + a centred
/// mono numeral); only PAINT branches — fill, ring hue, numeral ink, an active-only
/// cyan reticle, a layout-free bloom. That is what makes earned/active/unearned render
/// at pixel-identical size: the frame, ring width and font are literals shared by all
/// states, and nothing dashes (the old dashed planned ring is what read "smaller").
struct SetIndexBadge: View {
    enum Charge: Equatable {
        case earned(AuraTier)   // logged & scored — a charged tier disc
        case warmup             // logged, off the record — a neutral ash disc
        case active             // the live input row — a hollow cyan targeting reticle
        case unearned           // planned, not yet — a hollow iron ghost ring
    }

    let label: String
    let charge: Charge

    /// Constant shared by EVERY state — the size contract lives here.
    private static let ring: CGFloat = 1.5

    var body: some View {
        ZStack {
            Circle().fill(discColor)                                  // body: disc / tint / faint mass
            Circle().strokeBorder(ringColor, lineWidth: Self.ring)    // rim: same width, same radius, NEVER dashed
            if case .active = charge {
                ReticleTicks(arm: 3)                                  // scouter targeting marks — active only
                    .stroke(SettColor.heroCyan.opacity(0.85), lineWidth: 1)
            }
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(numeralColor)
                .lineLimit(1)
        }
        .frame(width: SetRowGrid.badge, height: SetRowGrid.badge)     // the ONLY size source — 24pt, every state
        .compositingGroup()
        .shadow(color: glowColor, radius: glowRadius)                 // layout-free bloom; .clear/0 for hollow states
    }

    // MARK: paint — the only thing state changes

    private var discColor: Color {
        switch charge {
        case .earned(let tier): tier.color.opacity(0.85)   // solid = charged
        case .warmup:           SettColor.iron.opacity(0.30)
        case .active:           SettColor.heroCyan.opacity(0.12)
        case .unearned:         TimeChamber.void.opacity(0.35)  // faint mass so the ghost never optically shrinks
        }
    }

    private var ringColor: Color {
        switch charge {
        case .earned(let tier): tier.color                 // full — a crisp charged rim
        case .warmup:           SettColor.ash.opacity(0.6)
        case .active:           SettColor.heroCyan.opacity(0.9)
        case .unearned:         SettColor.iron.opacity(0.5) // SOLID ghost ring — the dash is gone
        }
    }

    private var numeralColor: Color {
        switch charge {
        case .earned:   SettColor.etch      // punched out of the charged phosphor (max contrast on amber/red)
        case .warmup:   SettColor.ash
        case .active:   SettColor.heroCyan
        case .unearned: SettColor.iron
        }
    }

    private var glowColor: Color {
        switch charge {
        case .earned(let tier):  tier.color.opacity(0.45)
        case .active:            SettColor.heroCyan.opacity(0.30)
        case .warmup, .unearned: .clear
        }
    }

    private var glowRadius: CGFloat {
        switch charge {
        case .earned, .active:   3
        case .warmup, .unearned: 0
        }
    }
}

/// Four cardinal targeting ticks at the frame edge — the scouter gunsight. Draws inside
/// the fixed badge frame, so it has no intrinsic size and can never widen the badge.
struct ReticleTicks: Shape {
    var arm: CGFloat = 3
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY + arm))
        p.move(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY - arm))
        p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.minX + arm, y: r.midY))
        p.move(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX - arm, y: r.midY))
        return p
    }
}
