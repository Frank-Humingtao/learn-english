import CoreModels
import Lexicon
import ProfileEngine
import TestEngine
import Testing

@Suite struct ItemSelectionTests {
    let lexicon = syntheticLexicon(count: 6000)

    /// History of a learner who knows the first 1500 words: a spread of answers over the lexicon.
    func history() -> [Observation] {
        var out: [Observation] = []
        for k in 0..<120 {
            let rank = 1 + k * 50
            let lemma = lexicon.entries[rank - 1].lemma
            out.append(Observation(ts: stamp(day: 1, second: k), lemma: lemma, source: .test,
                                   result: rank <= 1500 ? "yes" : "no", session: "h1"))
        }
        return out
    }

    func session(history: [Observation], seed: UInt64 = 7) -> TestSession {
        let profile = ProfileEngine.compute(observations: history, lexicon: lexicon)
        return TestSession(lexicon: lexicon, profile: profile, history: history, config: .short,
                           sessionID: "s-test", seed: seed)
    }

    func yesNoItems(_ s: TestSession) -> [YesNoItem] {
        s.items.compactMap { if case .yesNo(let q) = $0 { return q } else { return nil } }
    }

    @Test func realWordsSitNearTheLearnersBoundary() {
        let h = history()
        let profile = ProfileEngine.compute(observations: h, lexicon: lexicon)
        let real = yesNoItems(session(history: h)).filter { $0.kind == .real }
        #expect(real.count >= 40)
        let ps = real.map { profile.probability(of: $0.word)! }
        let meanDistance = ps.map { abs($0 - 0.5) }.reduce(0, +) / Double(ps.count)
        #expect(meanDistance < 0.15, "mean |P-0.5| = \(meanDistance)")
        #expect(ps.allSatisfy { $0 > 0.15 && $0 < 0.85 }, "\(ps.sorted())")
    }

    @Test func realWordsAreNeverPreviouslyTestedOrRepeated() {
        let h = history()
        let tested = Set(h.map(\.lemma))
        let real = yesNoItems(session(history: h)).filter { $0.kind == .real }.map(\.word)
        #expect(Set(real).count == real.count)
        #expect(Set(real).isDisjoint(with: tested))
    }

    @Test func aboutAQuarterAreFreshPseudowordsAndAboutATenthSpotChecks() {
        let h = history()
        let profile = ProfileEngine.compute(observations: h, lexicon: lexicon)
        let items = yesNoItems(session(history: h))
        let pseudo = items.filter { $0.kind == .pseudoword }
        let spot = items.filter { $0.kind == .spotcheck }
        #expect(items.count == TestConfig.short.yesNoCount)
        #expect(abs(Double(pseudo.count) / Double(items.count) - 0.25) <= 0.02)
        #expect(abs(Double(spot.count) / Double(items.count) - 0.10) <= 0.02)
        #expect(spot.allSatisfy { profile.band(of: $0.word) == .mastered })
        for p in pseudo {
            #expect(lexicon.lemma(for: p.word) == nil, "\(p.word) is a real word")
            #expect(p.word.allSatisfy { $0.isLetter && $0.isLowercase })
        }
        #expect(Set(pseudo.map(\.word)).count == pseudo.count)
    }

    @Test func pseudowordsAreNeverReused() {
        var h = history()
        let first = yesNoItems(session(history: h, seed: 1)).filter { $0.kind == .pseudoword }
        for (i, p) in first.enumerated() {
            h.append(Observation(ts: stamp(day: 2, second: i), lemma: p.word, source: .test, result: "no",
                                 session: "h2", pseudo: true))
        }
        let second = yesNoItems(session(history: h, seed: 1)).filter { $0.kind == .pseudoword }
        #expect(Set(first.map(\.word)).isDisjoint(with: second.map(\.word)))
    }

    @Test func sameSeedGivesTheSameTest() {
        let h = history()
        #expect(session(history: h, seed: 3).items == session(history: h, seed: 3).items)
        #expect(session(history: h, seed: 3).items != session(history: h, seed: 4).items)
    }
}
