import CoreModels
import Lexicon
import ProfileEngine
import Testing

/// The two-layer model's outputs (ticket 02): knowledge only, standard errors, split totals,
/// exam-tag feature and the session quality gate.
@Suite struct TwoLayerTests {
    func background(session: String = "s0", knownUpTo: Int = 3000) -> [Observation] {
        stride(from: 100, through: 9000, by: 100).map {
            var o = obs(word($0), .test, $0 <= knownUpTo ? "yes" : "no", day: 0, minute: $0 / 100)
            o.session = session
            return o
        }
    }

    func pseudo(_ k: Int, _ yes: Bool, session: String) -> Observation {
        Observation(ts: ts(day: 0, minute: 100 + k), lemma: "blorf\(k)", source: .test, result: yes ? "yes" : "no",
                    session: session, pseudo: true)
    }

    @Test func standardErrorsShrinkWithDirectEvidenceAndTotalsSplitAtLevel14() {
        let lexicon = syntheticLexicon(count: 20000)
        let profile = ProfileEngine.compute(observations: background(), lexicon: lexicon)
        let observed = lexicon.index(of: word(3000))!, unobserved = lexicon.index(of: word(3050))!
        #expect(profile.standardErrors[observed] < profile.standardErrors[unobserved])
        #expect(profile.standardErrors.allSatisfy { $0 >= 0 && $0 < 0.5 })
        let v = profile.vocabulary
        #expect(abs(v.core.lemmas.estimate + v.tail.lemmas.estimate - v.lemmas.estimate) < 1e-6)
        #expect(abs(v.core.families.estimate + v.tail.families.estimate - v.families.estimate) < 1e-6)
        #expect(v.tail.families.estimate < v.core.families.estimate)
        #expect(v.families.low <= v.families.estimate && v.families.estimate <= v.families.high)
    }

    @Test func guessingNeverCountsAsKnowing() {
        // Half the pseudowords answered "yes": that rate must not lift P of words never asked about.
        let lexicon = syntheticLexicon(count: 20000)
        let honest = ProfileEngine.compute(observations: background() + (0..<40).map { pseudo($0, false, session: "s0") },
                                           lexicon: lexicon)
        let guesser = ProfileEngine.compute(observations: background() + (0..<40).map { pseudo($0, $0 % 2 == 0, session: "s0") },
                                            lexicon: lexicon)
        let rare = lexicon.index(of: word(19000))!
        #expect(guesser.probabilities[rare] <= honest.probabilities[rare] + 1e-3)
        #expect(guesser.vocabulary.lemmas.estimate < honest.vocabulary.lemmas.estimate)
    }

    @Test func sessionsFailingTheQualityGateCountLessButStillCount() {
        let lexicon = syntheticLexicon(count: 10000)
        let target = word(4321)
        let good = (0..<20).map { pseudo($0, false, session: "s0") }
        let sloppy = (0..<20).map { pseudo(20 + $0, $0 < 5, session: "s1") } // 25% false alarms
        var yes = obs(target, .test, "yes", day: 0, minute: 200)
        yes.session = "s1"
        let base = ProfileEngine.compute(observations: background() + good + sloppy, lexicon: lexicon)
        let withYes = ProfileEngine.compute(observations: background() + good + sloppy + [yes], lexicon: lexicon)
        #expect(withYes.sessionWeights == ["s1": 0.5])
        #expect(withYes.probability(of: target)! > base.probability(of: target)!)
    }

    @Test func examTagsAreLearnedFromTheAnswers() {
        // Every third word carries a cet4 tag; the Learner knows tagged words up to rank 8000 but
        // untagged ones only up to 2000. Tagged words should come out easier.
        var entries: [LexiconEntry] = []
        for i in 1...10000 {
            entries.append(LexiconEntry(lemma: word(i), rank: i, family: word(i), familyRank: i,
                                        level: (i - 1) / 1000 + 1, tags: i % 3 == 0 ? "cet4 cet6" : ""))
        }
        let lexicon = Lexicon(version: "tags-1", entries: entries)
        let answers = stride(from: 50, through: 9950, by: 25).map { r -> Observation in
            let known = r % 3 == 0 ? r <= 8000 : r <= 2000
            return obs(word(r), .test, known ? "yes" : "no", day: 0, minute: r / 25)
        }
        let profile = ProfileEngine.compute(observations: answers, lexicon: lexicon)
        let tagged = profile.probability(of: word(5001))!, untagged = profile.probability(of: word(5002))!
        #expect(tagged > untagged + 0.2, "tagged \(tagged) untagged \(untagged)")
    }
}
