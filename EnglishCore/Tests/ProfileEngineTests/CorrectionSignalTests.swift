import CoreModels
import Lexicon
import ProfileEngine
import Testing

/// The correction signals on Yes/No answers.
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
        // Meaning checks enter the same likelihood as the Yes/No answers: correct ones barely move the
        // real-word false-alarm rate, failed ones raise it.
        #expect(abs(honest.falseAlarmRate - plain.falseAlarmRate) < 0.02, "\(honest.falseAlarmRate) vs \(plain.falseAlarmRate)")
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
