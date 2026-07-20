import Foundation

// MARK: - Power Level decomposition (what builds it / what moved it)
//
// The PL is one opaque number: raw = (Wss·ss + Wvol·√vol)·cm, pl = round(raw).
// These value types crack it open two ways — a static snapshot of what the current
// number is made of, and a fair attribution of a change between two moments.

/// A static split of the CURRENT power level into its strength and volume halves
/// (both already scaled by the consistency multiplier) plus the standalone PL the
/// streak multiplier adds. Built from the rounded levers the user actually sees, so
/// strengthPL + volumePL lands within a rounding step of the live PL.
public struct PLComposition: Sendable, Hashable {
    /// round(Wss · ss · cm) — the strength score's contribution, cm folded in.
    public let strengthPL: Int
    /// round(Wvol · √vol · cm) — the weekly-volume contribution, cm folded in.
    public let volumePL: Int
    /// pl − round(raw / cm): the PL the streak multiplier stacks on top of the
    /// cm = 1 base. Zero when there's no active streak (cm == 1).
    public let streakBonusPL: Int
    public let consistencyMultiplier: Double

    public init(strengthPL: Int, volumePL: Int, streakBonusPL: Int,
                consistencyMultiplier: Double) {
        self.strengthPL = strengthPL
        self.volumePL = volumePL
        self.streakBonusPL = streakBonusPL
        self.consistencyMultiplier = consistencyMultiplier
    }

    /// Strength's slice of the strength+volume base, 0…1 (guards the zero case so a
    /// brand-new user's bars don't divide by zero).
    public var strengthShare: Double {
        let total = strengthPL + volumePL
        return total > 0 ? Double(strengthPL) / Double(total) : 0
    }

    /// Volume's slice of the strength+volume base, 0…1.
    public var volumeShare: Double {
        let total = strengthPL + volumePL
        return total > 0 ? Double(volumePL) / Double(total) : 0
    }
}

/// A signed attribution of a PL change over a window, split across the three levers
/// that drive it. `strength + volume + consistency == deltaPL` EXACTLY — the receipt
/// always balances.
public struct PLAttribution: Sendable, Hashable {
    public let deltaPL: Int
    public let strength: Int
    public let volume: Int
    public let consistency: Int
    public let fromDate: Date
    public let toDate: Date

    public init(deltaPL: Int, strength: Int, volume: Int, consistency: Int,
                fromDate: Date, toDate: Date) {
        self.deltaPL = deltaPL
        self.strength = strength
        self.volume = volume
        self.consistency = consistency
        self.fromDate = fromDate
        self.toDate = toDate
    }
}

public enum PowerLevelBreakdown {

    /// Split the current PL into its strength / volume / streak-bonus pieces.
    /// Recomputed from the rounded snapshot levers, so the pieces reconstruct the
    /// PL the user sees (to within one rounding step).
    public static func composition(strengthScore: Int, weeklyVolumeLb: Int,
                                   consistencyMultiplier: Double,
                                   config: ProgressionConfig) -> PLComposition {
        let plc = config.powerLevel
        let ss = Double(strengthScore)
        let vol = Double(weeklyVolumeLb)
        let cm = consistencyMultiplier

        let strengthPL = Int((plc.strengthWeight * ss * cm).rounded())
        let volumePL = Int((plc.volumeWeight * vol.squareRoot() * cm).rounded())

        // The streak bonus is what the multiplier adds over a cm = 1 world: pl minus
        // the PL you'd have at the same strength/volume with no streak. raw / cm is
        // exactly the cm = 1 bracket, so this is round(raw) − round(raw / cm).
        let raw = (plc.strengthWeight * ss + plc.volumeWeight * vol.squareRoot()) * cm
        let pl = Int(raw.rounded())
        let streakBonusPL = pl - Int((raw / cm).rounded())

        return PLComposition(strengthPL: strengthPL, volumePL: volumePL,
                             streakBonusPL: streakBonusPL, consistencyMultiplier: cm)
    }

    /// Attribute the raw-PL change between two history points across the three
    /// factors {strength, volume, consistency}, using an EXACT Shapley decomposition
    /// of f(ss, vol, cm) = (Wss·ss + Wvol·√vol)·cm.
    ///
    /// WHY Shapley and not a partial-derivative split: the cm factor multiplies the
    /// whole bracket, so the levers interact — moving both strength and the streak in
    /// the same window produces a cross term that belongs to neither alone. A naive
    /// "hold the others, vary one" split double-counts (or drops) that cross term and
    /// wouldn't sum back to the delta. Shapley is the unique attribution that is fair
    /// (symmetric, order-independent) AND additive: averaging each factor's marginal
    /// contribution over all 3! orderings makes the three shares sum EXACTLY to
    /// f(to) − f(from). We then round the three real shares to ints with the
    /// largest-remainder method so they still sum exactly to deltaPL.
    public static func attribution(from: PLPoint, to: PLPoint,
                                   config: ProgressionConfig) -> PLAttribution {
        let plc = config.powerLevel
        let wss = plc.strengthWeight
        let wvol = plc.volumeWeight

        // f over the three factors, indexed 0 = strength, 1 = volume, 2 = consistency.
        func f(_ v: [Double]) -> Double {
            (wss * v[0] + wvol * v[1].squareRoot()) * v[2]
        }

        let fromVals = [Double(from.strengthScore), Double(from.weeklyVolumeLb),
                        from.consistencyMultiplier]
        let toVals = [Double(to.strengthScore), Double(to.weeklyVolumeLb),
                      to.consistencyMultiplier]

        // For a subset (bitmask), a factor takes its "to" value iff it's in the set,
        // else its "from" value — the coalition that has already moved.
        let n = 3
        func vals(forSubset mask: Int) -> [Double] {
            (0..<n).map { (mask >> $0) & 1 == 1 ? toVals[$0] : fromVals[$0] }
        }

        // Standard Shapley weights |S|!·(n−|S|−1)! / n!  (n = 3 -> 1/3, 1/6, 1/3).
        var phi = [Double](repeating: 0, count: n)
        for i in 0..<n {
            for mask in 0..<(1 << n) where (mask >> i) & 1 == 0 {
                let s = (0..<n).filter { (mask >> $0) & 1 == 1 }.count
                let weight = factorial(s) * factorial(n - s - 1) / factorial(n)
                phi[i] += weight * (f(vals(forSubset: mask | (1 << i))) - f(vals(forSubset: mask)))
            }
        }

        // deltaPL is defined on the ROUNDED raw endpoints (round(raw_to) −
        // round(raw_from)), matching how the stored PLs round — apportion the real
        // shares to hit it exactly.
        let deltaPL = Int(f(toVals).rounded()) - Int(f(fromVals).rounded())
        let ints = apportion(phi, toSum: deltaPL)

        return PLAttribution(deltaPL: deltaPL, strength: ints[0], volume: ints[1],
                             consistency: ints[2], fromDate: from.date, toDate: to.date)
    }

    // MARK: - Helpers

    private static func factorial(_ n: Int) -> Double {
        n <= 1 ? 1 : (2...n).reduce(1.0) { $0 * Double($1) }
    }

    /// Largest-remainder (Hamilton) rounding: floor every value, then hand the
    /// leftover units to the largest fractional remainders (or reclaim from the
    /// smallest) so the ints sum EXACTLY to `target`, regardless of tiny FP drift in
    /// the Shapley shares.
    private static func apportion(_ values: [Double], toSum target: Int) -> [Int] {
        var result = values.map { Int($0.rounded(.down)) }
        let deficit = target - result.reduce(0, +)
        guard deficit != 0 else { return result }
        // Factors ordered by descending fractional part — the fairest to round up.
        let order = values.indices.sorted {
            (values[$0] - values[$0].rounded(.down)) > (values[$1] - values[$1].rounded(.down))
        }
        if deficit > 0 {
            for k in 0..<deficit { result[order[k % order.count]] += 1 }
        } else {
            for k in 0..<(-deficit) { result[order[order.count - 1 - (k % order.count)]] -= 1 }
        }
        return result
    }
}
