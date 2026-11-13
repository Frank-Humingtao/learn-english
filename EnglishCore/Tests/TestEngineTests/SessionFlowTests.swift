import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import TestEngine
import Testing

@Suite struct SessionFlowTests {
    let lexicon = syntheticLexicon(count: 6000)

    func freshSession(config: TestConfig = .short, seed: UInt64 = 11) -> TestSession {
        let profile = ProfileEngine.compute(observations: [], lexicon: lexicon)
        return TestSession(lexicon: lexicon, profile: profile, history: [], config: config, sessionID: "s1", seed: seed)
    }

    func meaningChecks(_ s: TestSession) -> [MeaningCheckItem] {
        s.items.compactMap { if case .meaningCheck(let q) = $0 { return q } else { return nil } }
    }

    @Test func baselineAndShortTestFitTheirTimeBudgets() {
        #expect(TestConfig.baseline.yesNoCount == 450)
        #expect(TestConfig.short.yesNoCount == 300)
        #expect(TestConfig.baseline.expectedMinutes <= 15)
        #expect(TestConfig.short.expectedMinutes <= 10)
        #expect(TestConfig.baseline.pseudowordFraction == 0.15)
        #expect(TestConfig.baseline.verifyFraction == 0.10)
    }

    @Test func everyAnswerBecomesOneObservationOfTheSession() {
        var s = freshSession()
        var learner = ThresholdLearner(knownUpTo: 2000, falseAlarmEvery: 5)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        #expect(s.isFinished)
        #expect(s.observations.count == s.items.count)
        #expect(s.progress.answered == s.progress.total)
        for (item, o) in zip(s.items, s.observations) {
            #expect(o.session == "s1")
            #expect(o.rtMs == 1500)
            #expect(o.lexicon == lexicon.version)
            switch item {
            case .yesNo(let q):
                #expect(o.lemma == q.word)
                #expect(o.source == (q.kind == .retest ? .spotcheck : .test))
                #expect((o.pseudo == true) == (q.kind == .pseudoword))
                #expect(o.result == "yes" || o.result == "no")
            case .meaningCheck(let q):
                #expect(o.lemma == q.lemma)
                #expect(o.source == .verify)
                #expect(["correct", "wrong", "unknown"].contains(o.result))
            }
        }
    }

    @Test func aboutOneYesInTenIsMeaningCheckedRightAway() {
        var s = freshSession(config: .baseline)
        var learner = ThresholdLearner(knownUpTo: 3500)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        var checks = 0, yes = 0
        for (k, item) in s.items.enumerated() {
            let o = s.observations[k]
            if o.pseudo != true && o.source != .verify && o.result == "yes" { yes += 1 }
            guard case .meaningCheck(let q) = item else { continue }
            checks += 1
            // Directly after a "yes" to the same real word.
            let before = s.observations[k - 1]
            #expect(before.lemma == q.lemma && before.result == "yes" && before.pseudo != true && before.source != .verify)
        }
        let rate = Double(checks) / Double(yes)
        #expect(rate > 0.06 && rate < 0.14, "\(checks) checks after \(yes) yes")
        #expect(Set(meaningChecks(s).map(\.lemma)).count == checks)
    }

    @Test func progressTotalIsAReasonableEstimateFromTheStart() {
        var s = freshSession()
        let first = s.progress.total
        var learner = ThresholdLearner(knownUpTo: 2000)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        #expect(abs(first - s.observations.count) <= 15, "\(first) vs \(s.observations.count)")
    }

    @Test func distractorsShareThePartOfSpeechAndSitNearbyInFrequency() {
        var s = freshSession(config: .baseline)
        var learner = ThresholdLearner(knownUpTo: 6000)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        let checks = meaningChecks(s)
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
                            config: .baseline, sessionID: "fx", seed: 5)
        var learner = ThresholdLearner(knownUpTo: 30000)
        runSession(&s, learner: &learner, lexicon: lex, day: 3)
        let checks = meaningChecks(s)
        #expect(checks.count >= 10)
        let byText = Dictionary(lex.entries.compactMap { e in MeaningChecks.gloss(e).map { ($0.text, Set([$0.pos])) } },
                                uniquingKeysWith: { $0.union($1) })
        for q in checks {
            let pos = MeaningChecks.gloss(lex.entry(lemma: q.lemma)!)!.pos
            // A gloss text can belong to words of several parts of speech (现代化: n and v).
            for opt in q.options { #expect(byText[opt]?.contains(pos) == true, "\(q.lemma) [\(pos)] option \(opt)") }
        }
    }

    @Test func pseudowordsAndMeaningChecksAreJudgedRealWordsAreNot() {
        var s = freshSession(config: .baseline)
        var seen: Set<String> = []
        var t = 0
        while let item = s.current {
            t += 1
            let at = stamp(day: 3, second: t)
            switch item {
            case .yesNo(let q) where q.kind == .pseudoword:
                let yes = t % 2 == 0
                let out = s.answer(.yesNo(yes), rtMs: 900, at: at)
                #expect(out.feedback == (yes ? .wrong(.pseudoword) : .correct))
                seen.insert(yes ? "pseudo-yes" : "pseudo-no")
            case .yesNo:
                let out = s.answer(.yesNo(true), rtMs: 900, at: at)
                #expect(out.feedback == .neutral)
                #expect(out.observation.result == "yes")
            case .meaningCheck(let q):
                switch seen.filter({ $0.hasPrefix("m-") }).count % 3 {
                case 0:
                    let out = s.answer(.meaning(q.correctIndex), rtMs: 2000, at: at)
                    #expect(out.observation.result == "correct")
                    #expect(out.feedback == .correct)
                    seen.insert("m-correct")
                case 1:
                    let out = s.answer(.meaning((q.correctIndex + 1) % 4), rtMs: 2000, at: at)
                    #expect(out.observation.result == "wrong")
                    #expect(out.feedback == .wrong(.meaning(q.options[q.correctIndex])))
                    seen.insert("m-wrong")
                default:
                    let out = s.answer(.meaning(nil), rtMs: 2000, at: at)
                    #expect(out.observation.result == "unknown")
                    #expect(out.feedback == .neutral)
                    seen.insert("m-unknown")
                }
            }
        }
        #expect(seen == ["pseudo-yes", "pseudo-no", "m-correct", "m-wrong", "m-unknown"])
    }

    @Test func liveEstimateMovesWithEveryFreshAnswer() {
        var s = freshSession()
        let start = s.estimate!.estimate
        var learner = ThresholdLearner(knownUpTo: 4500)
        var last = start
        var moved = 0, steps = 0
        var second = 0
        while let item = s.current, steps < 120 {
            second += 2
            s.answer(learner.answer(item, lexicon: lexicon), rtMs: 1500, at: stamp(day: 3, second: second))
            let now = s.estimate!.estimate
            if abs(now - last) > 0.5 { moved += 1 }
            last = now
            steps += 1
        }
        #expect(moved > steps / 2, "moved \(moved) of \(steps)")
        // Knowing 4500 of 6000 words: the estimate ends near it, wherever it started.
        let end = s.estimate!
        #expect(abs(end.estimate - 4500) < 900, "start \(start), end \(end)")
        #expect(end.low < end.estimate && end.estimate < end.high)
    }

    @Test func liveEstimateEndsCloseToTheFullFit() {
        var s = freshSession(config: .baseline)
        var learner = ThresholdLearner(knownUpTo: 2500, falseAlarmEvery: 10)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
        let full = ProfileEngine.compute(observations: s.observations, lexicon: lexicon).vocabulary.families.estimate
        let live = s.estimate!.estimate
        #expect(abs(live - full) / full < 0.25, "live \(live), full \(full)")
    }

    @Test func answeringIsFastOnTheFixtureLexicon() {
        let lex = fixtureLexicon()
        var s = TestSession(lexicon: lex, profile: ProfileEngine.compute(observations: [], lexicon: lex), history: [],
                            config: .short, sessionID: "fx", seed: 5)
        var learner = ThresholdLearner(knownUpTo: 5000)
        let clock = ContinuousClock()
        var n = 0
        let elapsed = clock.measure {
            var t = 0
            while let item = s.current {
                t += 2
                s.answer(learner.answer(item, lexicon: lex), rtMs: 1500, at: stamp(day: 3, second: t))
                _ = s.estimate
                n += 1
            }
        }
        let perAnswer = elapsed / n
        // About 3 ms alone in a debug build; generous because suites run in parallel. The full
        // lexicon is measured by `profile-engine eval --sim-flow engine` (release).
        #expect(perAnswer < .milliseconds(50), "\(perAnswer) per answer")
    }

    @Test func anInterruptedSessionResumesFromItsEncodedState() throws {
        var s = freshSession()
        for k in 0..<30 {
            if case .meaningCheck = s.current! { s.answer(.meaning(nil), rtMs: 1000, at: stamp(day: 3, second: k)) } else {
                s.answer(.yesNo(k % 2 == 0), rtMs: 1000, at: stamp(day: 3, second: k))
            }
        }
        var restored = try JSONDecoder().decode(TestSession.self, from: JSONEncoder().encode(s))
        #expect(!restored.isAttached)
        restored.attach(lexicon)
        #expect(restored.estimate == s.estimate)
        var original = s
        var l1 = ThresholdLearner(knownUpTo: 1500), l2 = ThresholdLearner(knownUpTo: 1500)
        runSession(&original, learner: &l1, lexicon: lexicon, day: 4)
        runSession(&restored, learner: &l2, lexicon: lexicon, day: 4)
        #expect(original.observations == restored.observations)
        #expect(original.items == restored.items)
    }
}
