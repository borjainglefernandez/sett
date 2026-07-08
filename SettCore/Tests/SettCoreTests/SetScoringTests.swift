import Foundation
import Testing
@testable import SettCore

/// Per-set scoring: e1RM as the single "output" number that prices the weight↔reps
/// trade, and the one-rep exchange rate that falls out of it.
@Suite struct SetScoringTests {

    private func grams(_ lb: Double) -> Int { Units.grams(fromDisplay: lb, unit: .lb) }
    private func lb(_ grams: Int) -> Double { Units.pounds(fromGrams: grams) }

    @Test("225 lb × 10 out-scores 250 lb × 3 (reps pay for the lighter bar)")
    func highRepBeatsHeavyLowRep() {
        let heavy = ProgressEngine.e1RMGrams(weightGrams: grams(250), reps: 3)   // ~275 lb
        let light = ProgressEngine.e1RMGrams(weightGrams: grams(225), reps: 10)  // 300 lb
        #expect(abs(lb(heavy) - 275) < 0.5)
        #expect(abs(lb(light) - 300) < 0.5)
        #expect(light > heavy)
        #expect(abs(lb(light) - lb(heavy) - 25) < 1.0) // beats by ~25 lb
    }

    @Test("At 250×3, +1 rep out-scores +5 lb")
    func extraRepBeatsExtraWeight() {
        let plusRep = ProgressEngine.e1RMGrams(weightGrams: grams(250), reps: 4)  // ~283.3 lb
        let plusWeight = ProgressEngine.e1RMGrams(weightGrams: grams(255), reps: 3) // ~280.5 lb
        #expect(abs(lb(plusRep) - 283.3) < 0.5)
        #expect(abs(lb(plusWeight) - 280.5) < 0.5)
        #expect(plusRep > plusWeight) // the extra rep is worth more here
    }

    @Test("Dropping weight or reps below the reference scores negative")
    func regressionsScoreNegative() {
        let reference = ProgressEngine.e1RMGrams(weightGrams: grams(250), reps: 3)
        let lighter = ProgressEngine.e1RMGrams(weightGrams: grams(245), reps: 3)
        let fewerReps = ProgressEngine.e1RMGrams(weightGrams: grams(250), reps: 2)
        #expect(lighter < reference)
        #expect(fewerReps < reference)
    }

    @Test("One-rep exchange rate at 250 lb × 3 is ~7.6 lb")
    func exchangeRate() {
        let perRep = ProgressEngine.oneRepEquivalentGrams(weightGrams: grams(250), reps: 3)
        #expect(abs(lb(perRep) - 7.58) < 0.25) // w/(30+r) = 250/33 ≈ 7.58 lb on the bar
        // The defining identity: +1 rep gives the SAME e1RM as +oneRepEquivalent lb
        // of load. e1RM(w, r+1) == e1RM(w + perRep, r).
        let viaExtraRep = ProgressEngine.e1RMGrams(weightGrams: grams(250), reps: 4)
        let viaExtraWeight = ProgressEngine.e1RMGrams(weightGrams: grams(250) + perRep, reps: 3)
        #expect(abs(lb(viaExtraRep) - lb(viaExtraWeight)) < 0.3)
    }
}
