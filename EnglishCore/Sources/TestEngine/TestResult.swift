import CoreModels
import Lexicon
import ProfileEngine

/// What the result screen shows after a test. All numbers come from the Profile Engine run on
/// the full history plus this test's Observations, exactly as `profile-engine profile` would.
public struct TestResult: Sendable {
    /// Word-family count rounded like `summary.json`.
    public struct Range: Sendable, Equatable {
        public var estimate: Int
        public var low: Int
        public var high: Int
        public init(estimate: Int, low: Int, high: Int) {
            self.estimate = estimate
            self.low = low
            self.high = high
        }
        init(_ e: Estimate) {
            self.init(estimate: Int(e.estimate.rounded()), low: Int(e.low.rounded()), high: Int(e.high.rounded()))
        }
    }

    /// Estimated vocabulary (word families) with its 95% interval, after this test.
    public var vocabulary: Range
    /// Change of the estimate versus the profile before this test; nil when there was no evidence before.
    public var change: Int?
    /// Words of this test the Learner did not show as known (no / wrong / don't know) that are now Target.
    public var newTargetWords: [String]
    public var spotcheck: (correct: Int, wrong: Int)
    /// Pseudowords answered "yes" out of those shown.
    public var pseudowords: (falseAlarms: Int, total: Int)
    /// The recomputed Learner Profile.
    public var profile: LearnerProfile

    public init(history: [Observation], session: [Observation], lexicon: Lexicon,
                config: ProfileConfig = ProfileConfig()) {
        let after = ProfileEngine.compute(observations: history + session, lexicon: lexicon, config: config)
        profile = after
        vocabulary = Range(after.vocabulary.families)
        let before = ProfileEngine.compute(observations: history, lexicon: lexicon, config: config)
        change = before.stats.used > 0 ? vocabulary.estimate - Range(before.vocabulary.families).estimate : nil

        var unknown = Set<String>()
        var spot = (correct: 0, wrong: 0)
        var pseudo = (falseAlarms: 0, total: 0)
        for o in session {
            if o.pseudo == true {
                pseudo.total += 1
                if o.result == ObservationResult.yes { pseudo.falseAlarms += 1 }
                continue
            }
            if o.source == .spotcheck {
                if o.result == ObservationResult.yes { spot.correct += 1 } else { spot.wrong += 1 }
            }
            if [ObservationResult.no, ObservationResult.wrong, ObservationResult.unknown].contains(o.result) {
                unknown.insert(o.lemma)
            }
        }
        newTargetWords = unknown.filter { after.band(of: $0) == .target }.sorted()
        spotcheck = spot
        pseudowords = pseudo
    }
}
