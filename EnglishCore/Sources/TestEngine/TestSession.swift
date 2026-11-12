import CoreModels
import Lexicon
import ProfileEngine

/// Size and mix of one Vocabulary Test. Baseline and short tests share the flow and differ only here.
public struct TestConfig: Sendable, Equatable, Codable {
    /// Yes/No items, including pseudowords and spot checks.
    public var yesNoCount: Int
    /// Share of Yes/No items that are freshly generated pseudowords.
    public var pseudowordFraction: Double = 0.25
    /// Share of Yes/No items that re-check a Mastered word.
    public var spotcheckFraction: Double = 0.10
    /// Chinese four-choice meaning checks drawn from words answered "yes" (fewer if not enough yeses).
    public var meaningCheckCount: Int
    /// Randomesque selection: real words are drawn at random from the `poolFactor × needed`
    /// untested words whose P is closest to 0.5.
    public var poolFactor: Int = 3

    public init(yesNoCount: Int, meaningCheckCount: Int) {
        self.yesNoCount = yesNoCount
        self.meaningCheckCount = meaningCheckCount
    }

    /// 3–5 minutes: ~80 Yes/No items (~2 s each) plus 6 meaning checks.
    public static let short = TestConfig(yesNoCount: 80, meaningCheckCount: 6)
}

public struct YesNoItem: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// An untested lexicon word near the Learner's boundary.
        case real
        /// A generated nonword; "yes" is a false alarm.
        case pseudoword
        /// A Mastered word re-checked.
        case spotcheck
    }

    public var word: String
    public var kind: Kind
}

public struct MeaningCheckItem: Sendable, Equatable, Codable {
    public var lemma: String
    /// Four Chinese glosses; the UI adds a fifth "不认识" choice.
    public var options: [String]
    public var correctIndex: Int
}

public enum TestItem: Sendable, Equatable, Codable {
    case yesNo(YesNoItem)
    case meaningCheck(MeaningCheckItem)
}

public enum TestAnswer: Sendable, Equatable {
    case yesNo(Bool)
    /// Index into `options`, or nil for "不认识".
    case meaning(Int?)
}

/// One run of a Vocabulary Test: a fixed list of Yes/No items chosen up front from the current
/// Learner Profile, then meaning checks chosen from this run's "yes" answers. Each answer yields
/// the Observation to store. Codable so an interrupted test can be resumed.
public struct TestSession: Sendable, Codable {
    public let sessionID: String
    public let config: TestConfig
    public let lexiconVersion: String
    /// Items so far; meaning checks are appended once the Yes/No part is done.
    public private(set) var items: [TestItem]
    public private(set) var observations: [Observation] = []
    private var rng: SplitMix64
    private var meaningChecksAdded = false
    private let meaningPlan: [MeaningCheckItem?]

    public init(lexicon: Lexicon, profile: LearnerProfile, history: [Observation], config: TestConfig,
                sessionID: String, seed: UInt64) {
        self.sessionID = sessionID
        self.config = config
        self.lexiconVersion = lexicon.version
        var rng = SplitMix64(seed: seed)
        let yesNo = ItemSelector.yesNoItems(lexicon: lexicon, profile: profile, history: history, config: config,
                                            rng: &rng)
        items = yesNo.map(TestItem.yesNo)
        // Meaning-check options are fixed now (per candidate word), so the session stays deterministic
        // regardless of when answers arrive.
        meaningPlan = yesNo.map { q in
            q.kind == .pseudoword ? nil : MeaningChecks.item(for: q.word, lexicon: lexicon, rng: &rng)
        }
        self.rng = rng
    }

    /// Next unanswered item, or nil when the test is complete.
    public var current: TestItem? {
        observations.count < items.count ? items[observations.count] : nil
    }

    public var isFinished: Bool { current == nil }

    /// Answered so far / expected total (the total is an estimate until meaning checks are chosen).
    public var progress: (answered: Int, total: Int) {
        let yesNo = meaningPlan.count
        let total = meaningChecksAdded ? items.count : yesNo + config.meaningCheckCount
        return (observations.count, max(total, observations.count))
    }

    /// Records the answer to `current` and returns the Observation to store.
    @discardableResult
    public mutating func answer(_ answer: TestAnswer, rtMs: Int, at ts: String) -> Observation {
        guard let item = current else { preconditionFailure("test already finished") }
        let o: Observation
        switch (item, answer) {
        case (.yesNo(let q), .yesNo(let yes)):
            o = Observation(ts: ts, lemma: q.word, source: q.kind == .spotcheck ? .spotcheck : .test,
                            result: yes ? ObservationResult.yes : ObservationResult.no, rtMs: rtMs,
                            session: sessionID, pseudo: q.kind == .pseudoword ? true : nil, lexicon: lexiconVersion)
        case (.meaningCheck(let q), .meaning(let choice)):
            let result = choice == nil ? ObservationResult.unknown
                : choice == q.correctIndex ? ObservationResult.correct : ObservationResult.wrong
            o = Observation(ts: ts, lemma: q.lemma, source: .verify, result: result, rtMs: rtMs,
                            session: sessionID, lexicon: lexiconVersion)
        default:
            preconditionFailure("answer \(answer) does not fit item \(item)")
        }
        observations.append(o)
        if !meaningChecksAdded && observations.count == meaningPlan.count { addMeaningChecks() }
        return o
    }

    private mutating func addMeaningChecks() {
        meaningChecksAdded = true
        var candidates: [MeaningCheckItem] = []
        for (i, o) in observations.enumerated() where o.result == ObservationResult.yes && o.pseudo != true {
            if let m = meaningPlan[i] { candidates.append(m) }
        }
        candidates.shuffle(using: &rng)
        items += candidates.prefix(config.meaningCheckCount).map(TestItem.meaningCheck)
    }
}

/// Deterministic SplitMix64 (Swift's default generator cannot be seeded).
struct SplitMix64: RandomNumberGenerator, Sendable, Codable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
