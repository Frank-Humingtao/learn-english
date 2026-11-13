import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import TestEngine
import Testing

@Suite struct SessionFlowTests {
    let lexicon = syntheticLexicon(count: 6000)

    func freshSession(seed: UInt64 = 11) -> TestSession {
        let profile = ProfileEngine.compute(observations: [], lexicon: lexicon)
        return TestSession(lexicon: lexicon, profile: profile, history: [], config: .short, sessionID: "s1", seed: seed)
    }

    @Test func everyAnswerBecomesOneObservationOfTheSession() {
        var s = freshSession()
        var learner = ThresholdLearner(knownUpTo: 2000, falseAlarmEvery: 5)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        #expect(s.isFinished)
        #expect(s.observations.count == s.items.count)
        for (item, o) in zip(s.items, s.observations) {
            #expect(o.session == "s1")
            #expect(o.rtMs == 1500)
            #expect(o.lexicon == lexicon.version)
            switch item {
            case .yesNo(let q):
                #expect(o.lemma == q.word)
                #expect(o.source == (q.kind == .spotcheck ? .spotcheck : .test))
                #expect((o.pseudo == true) == (q.kind == .pseudoword))
                #expect(o.result == "yes" || o.result == "no")
            case .meaningCheck(let q):
                #expect(o.lemma == q.lemma)
                #expect(o.source == .verify)
                #expect(["correct", "wrong", "unknown"].contains(o.result))
            }
        }
    }

    @Test func fiveToEightMeaningChecksComeFromWordsAnsweredYes() {
        var s = freshSession()
        var learner = ThresholdLearner(knownUpTo: 3500)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        let yes = Set(s.observations.filter { $0.result == "yes" && $0.pseudo != true }.map(\.lemma))
        let checks = s.items.compactMap { if case .meaningCheck(let q) = $0 { return q } else { return nil } }
        #expect((5...8).contains(checks.count))
        #expect(checks.allSatisfy { yes.contains($0.lemma) })
        #expect(Set(checks.map(\.lemma)).count == checks.count)
    }

    @Test func distractorsShareThePartOfSpeechAndSitNearbyInFrequency() {
        var s = freshSession()
        var learner = ThresholdLearner(knownUpTo: 6000)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        let checks = s.items.compactMap { if case .meaningCheck(let q) = $0 { return q } else { return nil } }
        #expect(!checks.isEmpty)
        for q in checks {
            let target = lexicon.entry(lemma: q.lemma)!
            #expect(q.options.count == 4)
            #expect(Set(q.options).count == 4)
            #expect(q.options[q.correctIndex] == String(target.translation.split(separator: " ")[1]))
            for (i, opt) in q.options.enumerated() where i != q.correctIndex {
                // Synthetic glosses are "义<rank>"; POS rotates with rank % 3.
                let rank = Int(opt.dropFirst())!
                #expect(rank % 3 == target.rank % 3, "\(q.lemma): distractor \(opt) has another POS")
                #expect(abs(rank - target.rank) <= 3 * 8, "\(q.lemma): distractor \(opt) is far in frequency")
            }
        }
    }

    @Test func realLexiconGlossesAreShortChineseWithMatchingPOS() {
        let lex = fixtureLexicon()
        let develop = MeaningChecks.gloss(lex.entry(lemma: "develop")!)!
        #expect(develop.pos == "v")
        #expect(develop.text == "发展；使发达；进步")
        var s = TestSession(lexicon: lex, profile: ProfileEngine.compute(observations: [], lexicon: lex), history: [],
                            config: .short, sessionID: "fx", seed: 5)
        var learner = ThresholdLearner(knownUpTo: 30000)
        runSession(&s, learner: &learner, lexicon: lex, day: 3)
        let checks = s.items.compactMap { if case .meaningCheck(let q) = $0 { return q } else { return nil } }
        #expect((5...8).contains(checks.count))
        for q in checks {
            let pos = MeaningChecks.gloss(lex.entry(lemma: q.lemma)!)!.pos
            // A gloss text can belong to words of several parts of speech (现代化: n and v).
            let byText = Dictionary(lex.entries.compactMap { e in MeaningChecks.gloss(e).map { ($0.text, Set([$0.pos])) } },
                                    uniquingKeysWith: { $0.union($1) })
            for opt in q.options { #expect(byText[opt]?.contains(pos) == true, "\(q.lemma) [\(pos)] option \(opt)") }
        }
    }

    @Test func meaningCheckAnswersAreScoredCorrectWrongOrUnknown() {
        var s = freshSession()
        while let item = s.current, case .yesNo = item { s.answer(.yesNo(true), rtMs: 900, at: stamp(day: 3, second: 1)) }
        guard case .meaningCheck(let q1) = s.current else { Issue.record("no meaning check"); return }
        #expect(s.answer(.meaning(q1.correctIndex), rtMs: 2000, at: stamp(day: 3, second: 2)).result == "correct")
        guard case .meaningCheck(let q2) = s.current else { Issue.record("no meaning check"); return }
        #expect(s.answer(.meaning((q2.correctIndex + 1) % 4), rtMs: 2000, at: stamp(day: 3, second: 3)).result == "wrong")
        #expect(s.answer(.meaning(nil), rtMs: 2000, at: stamp(day: 3, second: 4)).result == "unknown")
    }

    @Test func anInterruptedSessionResumesFromItsEncodedState() throws {
        var s = freshSession()
        for k in 0..<30 { s.answer(.yesNo(k % 2 == 0), rtMs: 1000, at: stamp(day: 3, second: k)) }
        var restored = try JSONDecoder().decode(TestSession.self, from: JSONEncoder().encode(s))
        var original = s
        var l1 = ThresholdLearner(knownUpTo: 1500), l2 = ThresholdLearner(knownUpTo: 1500)
        runSession(&original, learner: &l1, lexicon: lexicon, day: 4)
        runSession(&restored, learner: &l2, lexicon: lexicon, day: 4)
        #expect(original.observations == restored.observations)
        #expect(original.items == restored.items)
    }
}
