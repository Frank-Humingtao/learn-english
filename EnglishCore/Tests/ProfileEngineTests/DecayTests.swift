import CoreModels
import Lexicon
import ProfileEngine
import Testing

@Suite struct DecayTests {
    let lexicon = syntheticLexicon(count: 10000)

    func profile(target: Observation, halfLife: Double) -> LearnerProfile {
        var background: [Observation] = []
        for i in stride(from: 100, through: 9000, by: 100) {
            background.append(obs(word(i), .test, i <= 3000 ? "yes" : "no", day: 20, minute: i / 100))
        }
        var config = ProfileConfig()
        config.halfLifeDays = halfLife
        config.asOf = "2026-11-21T00:00:00Z"
        return ProfileEngine.compute(observations: background + [target], lexicon: lexicon, config: config)
    }

    @Test func olderAnswersCountLess() {
        let w = word(2000)
        let recentNo = Observation(ts: "2026-11-20T23:00:00Z", lemma: w, source: .test, result: "no")
        let oldNo = Observation(ts: "2025-11-20T23:00:00Z", lemma: w, source: .test, result: "no")
        let pRecent = profile(target: recentNo, halfLife: 180).probability(of: w)!
        let pOld = profile(target: oldNo, halfLife: 180).probability(of: w)!
        #expect(pRecent < pOld)
    }

    @Test func decaySpeedIsTunable() {
        let w = word(2000)
        let oldNo = Observation(ts: "2025-11-20T23:00:00Z", lemma: w, source: .test, result: "no")
        let recentNo = Observation(ts: "2026-11-20T23:00:00Z", lemma: w, source: .test, result: "no")
        let fastDecay = profile(target: oldNo, halfLife: 30).probability(of: w)!
        let slowDecay = profile(target: oldNo, halfLife: 3650).probability(of: w)!
        let noDecay = profile(target: recentNo, halfLife: 3650).probability(of: w)!
        // A year-old "no" is nearly forgotten with a 30-day half-life, nearly intact with 10 years.
        #expect(slowDecay < fastDecay)
        #expect(abs(slowDecay - noDecay) < 0.05)
    }
}
