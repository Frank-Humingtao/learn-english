import CoreModels
import Foundation
import Lexicon
@testable import ProfileEngine
import Testing

/// The running estimate the Test Engine shows after every answer (ticket 03).
@Suite struct LiveEstimateTests {
    let lexicon = syntheticLexicon(count: 8000)

    /// An honest learner who knows words up to rank `known`: one test of `n` stratified answers
    /// plus a few pseudowords, in order.
    func session(known: Int, n: Int, day: Int, seed: UInt64) -> [Observation] {
        var rng = SeededRNG(seed: seed)
        var out: [Observation] = []
        for k in 0..<n {
            let rank = 1 + Int(rng.next() % 8000)
            out.append(obs(word(rank), .test, rank <= known ? "yes" : "no", day: day, minute: k / 10))
            if k % 7 == 0 {
                out.append(Observation(ts: ts(day: day, minute: k / 10), lemma: "zq\(seed)x\(k)", source: .test,
                                       result: k % 70 == 0 ? "yes" : "no", session: "s\(day)", pseudo: true))
            }
        }
        return out
    }

    @Test func gradientMatchesFiniteDifferences() {
        var live = LiveEstimate(profile: ProfileEngine.compute(observations: [], lexicon: lexicon))
        for o in session(known: 3000, n: 120, day: 0, seed: 1) { live.record(o, lexicon: lexicon) }
        let x = live.state.x.map { $0 + 0.1 }
        let g = live.evaluate(x).1
        for k in 0..<LiveEstimate.n {
            var xp = x, xm = x
            xp[k] += 1e-5
            xm[k] -= 1e-5
            let fd = (live.logPosterior(xp) - live.logPosterior(xm)) / 2e-5
            #expect(abs(fd - g[k]) < 1e-3 * max(1, abs(fd)), "component \(k): \(g[k]) vs \(fd)")
        }
    }

    @Test func liveNumberEndsNearTheFullFitAndTheTruth() {
        let history = session(known: 3000, n: 150, day: 0, seed: 2)
        let before = ProfileEngine.compute(observations: history, lexicon: lexicon)
        var live = LiveEstimate(profile: before)
        let test = session(known: 3000, n: 300, day: 1, seed: 3)
        for o in test { live.record(o, lexicon: lexicon) }
        let full = ProfileEngine.compute(observations: history + test, lexicon: lexicon).vocabulary.families
        let now = live.families
        #expect(abs(now.estimate - full.estimate) / full.estimate < 0.1, "live \(now.estimate) full \(full.estimate)")
        #expect(abs(now.estimate - 3000) / 3000 < 0.15)
        #expect(now.low < now.estimate && now.estimate < now.high)
    }

    @Test func wordsAnsweredBeforeOnlyMoveTheirOwnP() {
        let history = session(known: 3000, n: 150, day: 0, seed: 4)
        let before = ProfileEngine.compute(observations: history, lexicon: lexicon)
        var live = LiveEstimate(profile: before)
        let old = history.first { $0.pseudo != true && $0.result == "no" }!
        let i = lexicon.index(of: old.lemma)!
        let p0 = live.probability(i), theta0 = live.theta
        live.record(obs(old.lemma, .spotcheck, "yes", day: 1), lexicon: lexicon)
        #expect(live.probability(i) > p0)
        #expect(live.theta == theta0)
    }

    @Test func stateSurvivesEncoding() throws {
        var live = LiveEstimate(profile: ProfileEngine.compute(observations: [], lexicon: lexicon))
        for o in session(known: 2000, n: 40, day: 0, seed: 5) { live.record(o, lexicon: lexicon) }
        let state = try JSONDecoder().decode(LiveEstimate.State.self, from: JSONEncoder().encode(live.state))
        let restored = LiveEstimate(state: state, lexicon: lexicon)
        #expect(restored.families == live.families)
    }
}
