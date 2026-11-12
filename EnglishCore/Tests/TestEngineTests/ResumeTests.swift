import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import TestEngine
import Testing

/// Baseline Test resume: the app keeps the session as it was created (a checkpoint) plus every
/// Observation it stored; resuming replays the stored Observations onto the checkpoint.
@Suite struct ResumeTests {
    let lexicon = syntheticLexicon(count: 6000)

    func checkpoint(config: TestConfig = .short, seed: UInt64 = 21) -> TestSession {
        let profile = ProfileEngine.compute(observations: [], lexicon: lexicon)
        return TestSession(lexicon: lexicon, profile: profile, history: [], config: config, sessionID: "b1", seed: seed)
    }

    func encodeDecode(_ s: TestSession) throws -> TestSession {
        try JSONDecoder().decode(TestSession.self, from: JSONEncoder().encode(s))
    }

    /// Answers `count` items (or until finished); returns the Observations "stored".
    func answer(_ s: inout TestSession, _ learner: inout ThresholdLearner, count: Int, from second: Int) -> [Observation] {
        var out: [Observation] = []
        var t = second
        while out.count < count, let item = s.current {
            t += 2
            out.append(s.answer(learner.answer(item, lexicon: lexicon), rtMs: 1200, at: stamp(day: 5, second: t)))
        }
        return out
    }

    @Test(arguments: [0, 1, 37, 80, 83])
    func interruptedAndResumedSessionMatchesAnUninterruptedOne(stopAt: Int) throws {
        // Uninterrupted reference run.
        var whole = checkpoint()
        var l1 = ThresholdLearner(knownUpTo: 2500, falseAlarmEvery: 4)
        let reference = answer(&whole, &l1, count: .max, from: 0)
        #expect(whole.isFinished)

        // Same learner, interrupted after `stopAt` answers, then resumed from the stored checkpoint.
        let saved = try encodeDecode(checkpoint())
        var first = saved
        var l2 = ThresholdLearner(knownUpTo: 2500, falseAlarmEvery: 4)
        let stored = answer(&first, &l2, count: stopAt, from: 0)

        var resumed = saved
        let replayed = resumed.replay(stored)
        #expect(replayed == stored.count)
        #expect(resumed.observations == stored)
        let rest = answer(&resumed, &l2, count: .max, from: 2 * stopAt)
        let all = stored + rest

        #expect(resumed.isFinished)
        #expect(resumed.items == whole.items)
        #expect(all == reference)
        // No duplicates, no losses: one Observation per item.
        #expect(all.count == resumed.items.count)
    }

    @Test func replayStopsAtTheFirstObservationThatDoesNotFitTheNextItem() {
        var s = checkpoint()
        var learner = ThresholdLearner(knownUpTo: 2500)
        var copy = s
        var stored = answer(&copy, &learner, count: 5, from: 0)
        stored[3].lemma = "not-this-word"
        #expect(s.replay(stored) == 3)
        #expect(s.observations.count == 3)
    }

    @Test func baselineIsTheLongFormOfTheSameTest() {
        let b = TestConfig.baseline
        let s = TestConfig.short
        // About 30 minutes at ~2.5 s per item.
        let minutes = Double(b.yesNoCount + b.meaningCheckCount) * 2.5 / 60
        #expect((25...35).contains(minutes))
        #expect(b.pseudowordFraction == s.pseudowordFraction)
        #expect(b.spotcheckFraction == s.spotcheckFraction)
        #expect(b.meaningCheckCount > s.meaningCheckCount)
    }
}
