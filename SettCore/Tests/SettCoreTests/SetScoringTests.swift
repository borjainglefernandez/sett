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

    // MARK: Rep cap — beyond 12 reps, e1RM stops climbing (the Epley cap)

    @Test("e1RM caps reps at 12 — 20 reps scores the same as 12")
    func repsCapAt12() {
        let at12 = ProgressEngine.e1RMGrams(weightGrams: grams(135), reps: 12)
        let at13 = ProgressEngine.e1RMGrams(weightGrams: grams(135), reps: 13)
        let at20 = ProgressEngine.e1RMGrams(weightGrams: grams(135), reps: 20)
        #expect(at13 == at12)
        #expect(at20 == at12)
        // and 12 is still strictly above 11 (the cap kicks in only past 12)
        #expect(at12 > ProgressEngine.e1RMGrams(weightGrams: grams(135), reps: 11))
    }

    @Test("Zero/negative reps don't crash or inflate e1RM")
    func nonPositiveReps() {
        // reps clamp at 0, so e1RM == the raw weight (no rep credit), never negative.
        #expect(ProgressEngine.e1RMGrams(weightGrams: grams(135), reps: 0) == grams(135))
        #expect(ProgressEngine.e1RMGrams(weightGrams: grams(135), reps: -3) == grams(135))
    }

    // MARK: Effective load — bodyweight adds the lifter's mass (the CLAUDE.md rule)

    @Test("effectiveWeightGrams: non-bodyweight equipment is the added weight unchanged")
    func effectiveLoadFreeWeight() {
        for eq in [Equipment.barbell, .dumbbell, .machine, .cable] {
            #expect(LoadMath.effectiveWeightGrams(addedGrams: grams(185), equipment: eq,
                                                  bodyweightGrams: grams(180)) == grams(185))
        }
    }

    @Test("effectiveWeightGrams: bodyweight adds real mass; nil falls back to the default")
    func effectiveLoadBodyweight() {
        // A bodyweight pull-up at 180 lb bodyweight moves ~180 lb of effective load.
        let bw = LoadMath.effectiveWeightGrams(addedGrams: 0, equipment: .bodyweight,
                                               bodyweightGrams: grams(180))
        #expect(bw == grams(180))
        // A weighted pull-up (+45 lb) adds to bodyweight.
        let weighted = LoadMath.effectiveWeightGrams(addedGrams: grams(45), equipment: .bodyweight,
                                                     bodyweightGrams: grams(180))
        #expect(weighted == grams(180) + grams(45))
        // No captured bodyweight → the neutral default (never 0 — a pull-up must score).
        let fallback = LoadMath.effectiveWeightGrams(addedGrams: 0, equipment: .bodyweight,
                                                     bodyweightGrams: nil)
        #expect(fallback == LoadMath.defaultBodyweightGrams)
        #expect(fallback > 0)
    }

    @Test("A bodyweight pull-up scores against real bodyweight, not the 80 kg default")
    func bodyweightE1RMUsesRealMass() {
        // Same movement (BW pull-up × 8) scored at two different bodyweights must differ
        // — the whole point of capturing workout.bodyweightGrams.
        let light = LoadMath.effectiveWeightGrams(addedGrams: 0, equipment: .bodyweight,
                                                  bodyweightGrams: grams(130))
        let heavy = LoadMath.effectiveWeightGrams(addedGrams: 0, equipment: .bodyweight,
                                                  bodyweightGrams: grams(220))
        let lightE1RM = ProgressEngine.e1RMGrams(weightGrams: light, reps: 8)
        let heavyE1RM = ProgressEngine.e1RMGrams(weightGrams: heavy, reps: 8)
        #expect(heavyE1RM > lightE1RM)
        #expect(lightE1RM > 0)   // never scored as 0
    }
}
