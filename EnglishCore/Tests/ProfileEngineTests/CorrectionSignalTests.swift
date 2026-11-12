import CoreModels
import Lexicon
import ProfileEngine
import Testing

/// Review evidence vs the global fit, and the correction signals on Yes/No answers.
@Suite struct CorrectionSignalTests {
    let lexicon = syntheticLexicon(count: 10000)

    func background(day: Int = 0) -> [Observation] {
        stride(from: 100, through: 9000, by: 100).map {
            obs(word($0), .test, $0 <= 3000 ? "yes" : "no", day: day, minute: $0 / 100)
        }
    }

    func profile(_ observations: [Observation]) -> LearnerProfile {
        var config = ProfileConfig()
        config.asOf = ts(day: 20)
        return ProfileEngine.compute(observations: observations, lexicon: lexicon, config: config)
    }

    /// 30 cards on words ranked 3000–4000, 69 reviews, about 90% remembered, and no test at all.
    func reviewsOnly() -> [Observation] {
        var out: [Observation] = []
        var n = 0
        for k in 0..<30 {
            let lemma = word(3000 + 33 * k)
            for r in 0..<(k < 9 ? 3 : 2) {
                n += 1
                out.append(obs(lemma, .review, n % 10 == 0 ? "again" : "good", day: 1 + r * 3, minute: k))
            }
        }
        precondition(n == 69)
        return out
    }

    @Test func reviewsAloneDoNotMoveTheGlobalCurve() {
        let none = profile([])
        let reviewed = profile(reviewsOnly())
        #expect(reviewed.theta == none.theta && reviewed.slope == none.slope)
        // Only the 30 reviewed words themselves can change band; the rest of the lexicon cannot.
        #expect(reviewed.bandCounts.mastered <= none.bandCounts.mastered + 30,
                "mastered \(none.bandCounts.mastered) -> \(reviewed.bandCounts.mastered)")
        #expect(reviewed.levelMastery[3].mastery < 0.5, "level 4 mastery \(reviewed.levelMastery[3].mastery)")
        // The reviewed words do move: each is better known than its unreviewed neighbour.
        #expect(reviewed.probability(of: word(3033))! > none.probability(of: word(3033))!)
    }

    @Test func reviewsOnTopOfTestsLeaveThetaAndSlopeAlone() {
        let tests = profile(background())
        let both = profile(background() + reviewsOnly() + [obs(word(8000), .review, "easy", day: 9)])
        #expect(both.theta == tests.theta && both.slope == tests.slope)
        #expect(both.probability(of: word(8000))! > tests.probability(of: word(8000))!)
    }

    @Test func implausiblyFastYesCountsLess() {
        let target = word(4321)
        func yes(rt: Int) -> Observation {
            var o = obs(target, .test, "yes", day: 1)
            o.rtMs = rt
            return o
        }
        let base = profile(background()).probability(of: target)!
        let fast = profile(background() + [yes(rt: 150)]).probability(of: target)!
        let normal = profile(background() + [yes(rt: 1500)]).probability(of: target)!
        #expect(base < fast && fast < normal)
    }

    @Test func failedMeaningChecksAfterYesRaiseTheGuessingRate() {
        func claimed(_ verify: String) -> [Observation] {
            (0..<20).flatMap { k -> [Observation] in
                let lemma = word(5000 + 7 * k)
                return [obs(lemma, .test, "yes", day: 1, minute: 2 * k), obs(lemma, .verify, verify, day: 1, minute: 2 * k + 1)]
            }
        }
        let honest = profile(background() + claimed("correct"))
        let overclaiming = profile(background() + claimed("wrong"))
        let plain = profile(background())
        #expect(honest.falseAlarmRate == plain.falseAlarmRate)
        #expect(overclaiming.falseAlarmRate > plain.falseAlarmRate + 0.1, "\(overclaiming.falseAlarmRate)")
        // The extra guessing discounts every "yes", so an unchecked "yes" word ends lower.
        let target = word(4321)
        let extra = [obs(target, .test, "yes", day: 2)]
        #expect(profile(background() + claimed("wrong") + extra).probability(of: target)!
                    < profile(background() + claimed("correct") + extra).probability(of: target)!)
    }

    @Test func personFitFlagsAnswersTheModelCannotExplain() {
        let consistent = profile(background())
        var rng = SeededRNG(seed: 7)
        let random = profile(stride(from: 100, through: 9000, by: 100).map {
            obs(word($0), .test, Bool.random(using: &rng) ? "yes" : "no", day: 0, minute: $0 / 100)
        })
        #expect(consistent.personFit! > -2, "\(consistent.personFit!)")
        #expect(random.personFit! < -2, "\(random.personFit!)")
        #expect(profile(Array(background().prefix(10))).personFit == nil, "too few answers")
    }
}
