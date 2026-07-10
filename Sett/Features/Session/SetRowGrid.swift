import SwiftUI

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
    static let stepperGutter: CGFloat = 28
    static let times: CGFloat = 18        // the "×" anchor
    static let repsCell: CGFloat = 26     // up to "99", left-aligned
    static let rowHeight: CGFloat = 44
    static let hPad: CGFloat = 10
}

/// The weight / × / reps value columns for the NON-editable rows (logged + planned).
/// Reserves BOTH stepper gutters as clear space so the `×` and both value edges sit at
/// the exact same x as the active input row's real micro-steppers.
@ViewBuilder
func setValueColumns(weightText: String, reps: Int,
                     valueColor: Color, weight: Font.Weight) -> some View {
    Text(weightText)
        .font(.system(size: 15, weight: weight, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(valueColor)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: SetRowGrid.weightCell, height: SetRowGrid.rowHeight, alignment: .trailing)
    Color.clear.frame(width: SetRowGrid.stepperGutter, height: 1)
    Text("×")
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundStyle(SettColor.iron)
        .frame(width: SetRowGrid.times)
    Text("\(reps)")
        .font(.system(size: 15, weight: weight, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(valueColor)
        .frame(width: SetRowGrid.repsCell, height: SetRowGrid.rowHeight, alignment: .leading)
    Color.clear.frame(width: SetRowGrid.stepperGutter, height: 1)
}
