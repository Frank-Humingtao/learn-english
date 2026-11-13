import CoreModels
import Lexicon
import ProfileEngine

/// Size and mix of one Vocabulary Test. Baseline and short tests share the flow and differ only in
/// length. Every number here is a starting point to be tuned with the offline evaluation.
public struct TestConfig: Sendable, Equatable, Codable {
    /// How the real words of a test are chosen (fractions of the real Yes/No items; they are
    /// normalized, so they need not add up to exactly 1).
    public struct Allocation: Sendable, Equatable, Codable {
        /// Stratified over BNC/COCA 1000-family levels with Neyman allocation (n_h ∝ N_h·S_h at the
        /// current P): the total, including the long tail.
        public var stratified = 0.40
        /// Highest P(1 − P) weighted by corpus token frequency: per-word accuracy where Coverage needs it.
        public var uncertain = 0.40
        /// P closest to 0.5: the Learner's level θ.
        public var boundary = 0.15
        /// Words answered in earlier tests: retest consistency and forgetting.
        public var retest = 0.05

        public init(stratified: Double = 0.40, uncertain: Double = 0.40, boundary: Double = 0.15, retest: Double = 0.05) {
            self.stratified = stratified
            self.uncertain = uncertain
            self.boundary = boundary
            self.retest = retest
        }
    }

    /// Yes/No items, including pseudowords (meaning checks come on top).
    public var yesNoCount: Int
    /// Share of Yes/No items that are freshly generated pseudowords.
    public var pseudowordFraction = 0.15
    /// Share of "yes" answers to real words followed at once by a meaning check. The next check
    /// comes after a random 1…(2/fraction − 1) further "yes" answers, so the share stays close to
    /// this while the Learner cannot predict which word is checked.
    public var verifyFraction = 0.10
    /// Aim meaning checks at unexpected "yes" answers: the chance after a "yes" scales with
    /// 1 − P(word) relative to the mean over this session's "yes" answers so far (same average).
    /// Off by default: in simulation it biased over-claimers' totals further than random checks
    /// (it also trips the Profile Engine's failed-check session gate more often).
    public var verifyTargeted = false
    public var allocation = Allocation()
    /// Every frequency level gets at least this many stratified items (when it has eligible words).
    public var minPerStratum = 2
    /// Boundary items are drawn at random among this many words with P closest to 0.5.
    public var boundaryPool = 8
    /// Uncertain items are drawn with weight P(1 − P)·freq^exponent.
    public var frequencyExponent = 1.0
    /// Pseudowords keep the length of a real word of the session within this many letters.
    public var pseudowordLengthTolerance = 1

    public init(yesNoCount: Int) {
        self.yesNoCount = yesNoCount
    }

    /// Short test, at most 10 minutes.
    public static let short = TestConfig(yesNoCount: 300)
    /// Baseline Test, at most 15 minutes.
    public static let baseline = TestConfig(yesNoCount: 450)

    /// Time budget assumptions: the Learner's measured pace was 1.4 s per Yes/No item (710 items in
    /// 17 minutes); 1.6 s leaves room for feedback. A meaning check takes about 5 s.
    public static let secondsPerYesNo = 1.6
    public static let secondsPerMeaningCheck = 5.0
    /// Share of real words answered "yes" assumed for the expected number of meaning checks.
    static let expectedYesShare = 0.6

    var realCount: Int { yesNoCount - pseudowordCount }
    var pseudowordCount: Int { Int((Double(yesNoCount) * pseudowordFraction).rounded()) }

    /// Expected meaning checks.
    public var expectedMeaningChecks: Double { Double(realCount) * Self.expectedYesShare * verifyFraction }

    /// Expected duration in minutes.
    public var expectedMinutes: Double {
        (Double(yesNoCount) * Self.secondsPerYesNo + expectedMeaningChecks * Self.secondsPerMeaningCheck) / 60
    }
}

public struct YesNoItem: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// A generated nonword; "yes" is a false alarm.
        case pseudoword
        /// Real word from the stratified sample over frequency levels.
        case stratified
        /// Real word the model is least sure about, weighted by token frequency.
        case uncertain
        /// Real word with P ≈ 0.5.
        case boundary
        /// Real word answered in an earlier test.
        case retest

        public var isReal: Bool { self != .pseudoword }
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

/// Immediate judgment of one answer. Real-word Yes/No answers are never judged (the Learner's
/// own report is the evidence); pseudowords and meaning checks have a right answer.
public enum Feedback: Sendable, Equatable {
    case neutral
    case correct
    case wrong(Correction)

    public enum Correction: Sendable, Equatable {
        /// The word was a pseudoword: the right answer was "不认识".
        case pseudoword
        /// The right meaning.
        case meaning(String)
    }
}

/// What answering one item produced.
public struct AnswerOutcome: Sendable, Equatable {
    /// The Observation to store.
    public var observation: Observation
    public var feedback: Feedback
}

/// One run of a Vocabulary Test. Items are chosen one at a time: pseudowords, stratified and retest
/// words follow a plan fixed when the test is created; uncertain and boundary words are picked from
/// the live estimate as answers come in, and about one "yes" in ten is followed at once by a
/// meaning check of that word. Everything is a deterministic function of the seed and the answers,
/// so an interrupted test replayed from its checkpoint continues exactly as it would have.
///
/// Codable for checkpoints. A decoded session must be attached to the lexicon (`attach(_:)`)
/// before it is answered or replayed.
public struct TestSession: Sendable {
    public let sessionID: String
    public let config: TestConfig
    public let lexiconVersion: String
    /// Items shown so far, the current one last until it is answered.
    public private(set) var items: [TestItem] = []
    public private(set) var observations: [Observation] = []

    var rng: SplitMix64
    /// Kind of each Yes/No slot, in order; `slot` is the next one to fill.
    var schedule: [YesNoItem.Kind]
    var slot = 0
    /// Planned stratified and retest words (lexicon indices), consumed front to back.
    var stratifiedQueue: [Int]
    var retestQueue: [Int]
    /// Real words used in this session.
    var used: Set<Int> = []
    /// Pseudowords never to show again (earlier tests and this one).
    var usedPseudowords: Set<String>
    var retiredShapes: Set<PseudowordShape>
    /// Real-word "yes" answers so far and the sum of their 1 − P (targeted verification).
    var yesCount = 0
    var yesSurprise = 0.0
    /// "Yes" answers left until the next meaning check (untargeted mode).
    var yesUntilCheck = 0
    /// Live estimate state while detached (decoded and not yet attached).
    private var detachedLive: LiveEstimate.State?
    private var runtime: Runtime?

    /// Lexicon-derived data, rebuilt on `attach` (not encoded).
    struct Runtime: Sendable {
        let lexicon: Lexicon
        var live: LiveEstimate
        let selector: ItemSelector
    }

    /// `profile` is the Learner Profile from `history` (everything before this test).
    public init(lexicon: Lexicon, profile: LearnerProfile, history: [Observation], config: TestConfig,
                sessionID: String, seed: UInt64) {
        self.sessionID = sessionID
        self.config = config
        self.lexiconVersion = lexicon.version
        var rng = SplitMix64(seed: seed)
        let live = LiveEstimate(profile: profile)
        let selector = ItemSelector(lexicon: lexicon, config: config)
        let plan = selector.plan(profile: profile, live: live, config: config, rng: &rng)
        schedule = plan.schedule
        stratifiedQueue = plan.stratified
        retestQueue = plan.retest
        usedPseudowords = Set(history.filter { $0.pseudo == true }.map { $0.lemma.lowercased() })
        retiredShapes = PseudowordAnalysis(history: history, generator: selector.pseudowords).retired
        self.rng = rng
        runtime = Runtime(lexicon: lexicon, live: live, selector: selector)
        yesUntilCheck = drawCheckGap()
        appendNext(after: nil)
    }

    /// Rebuilds the lexicon-derived state of a decoded session (no-op when already attached).
    public mutating func attach(_ lexicon: Lexicon) {
        guard runtime == nil, let state = detachedLive else { return }
        precondition(lexicon.version == lexiconVersion, "session \(sessionID) was made with lexicon \(lexiconVersion)")
        runtime = Runtime(lexicon: lexicon, live: LiveEstimate(state: state, lexicon: lexicon),
                          selector: ItemSelector(lexicon: lexicon, config: config))
        detachedLive = nil
    }

    public var isAttached: Bool { runtime != nil }

    /// Next unanswered item, or nil when the test is complete.
    public var current: TestItem? {
        observations.count < items.count ? items[observations.count] : nil
    }

    public var isFinished: Bool { current == nil }

    /// Answered so far / expected total (meaning checks are estimated until the end).
    public var progress: (answered: Int, total: Int) {
        let checks = items.reduce(0) { n, item in if case .meaningCheck = item { return n + 1 } else { return n } }
        let remainingReal = schedule[min(slot, schedule.count)...].filter(\.isReal).count
        let expectedMore = Double(remainingReal) * TestConfig.expectedYesShare * config.verifyFraction
        let total = schedule.count + checks + Int(expectedMore.rounded())
        return (observations.count, isFinished ? observations.count : max(total, observations.count + 1))
    }

    /// Live vocabulary estimate (word families) after the answers so far; nil while detached.
    public var estimate: Estimate? { runtime?.live.families }

    /// Records the answer to `current`; returns the Observation to store and the judgment to show.
    @discardableResult
    public mutating func answer(_ answer: TestAnswer, rtMs: Int, at ts: String) -> AnswerOutcome {
        guard let item = current else { preconditionFailure("test already finished") }
        precondition(runtime != nil, "attach the lexicon before answering")
        let o: Observation
        let feedback: Feedback
        switch (item, answer) {
        case (.yesNo(let q), .yesNo(let yes)):
            o = Observation(ts: ts, lemma: q.word, source: q.kind == .retest ? .spotcheck : .test,
                            result: yes ? ObservationResult.yes : ObservationResult.no, rtMs: rtMs,
                            session: sessionID, pseudo: q.kind == .pseudoword ? true : nil, lexicon: lexiconVersion)
            feedback = q.kind == .pseudoword ? (yes ? .wrong(.pseudoword) : .correct) : .neutral
        case (.meaningCheck(let q), .meaning(let choice)):
            let result = choice == nil ? ObservationResult.unknown
                : choice == q.correctIndex ? ObservationResult.correct : ObservationResult.wrong
            o = Observation(ts: ts, lemma: q.lemma, source: .verify, result: result, rtMs: rtMs,
                            session: sessionID, lexicon: lexiconVersion)
            switch result {
            case ObservationResult.correct: feedback = .correct
            case ObservationResult.wrong: feedback = .wrong(.meaning(q.options[q.correctIndex]))
            default: feedback = .neutral
            }
        default:
            preconditionFailure("answer \(answer) does not fit item \(item)")
        }
        apply(o)
        return AnswerOutcome(observation: o, feedback: feedback)
    }

    /// Resumes an interrupted test: re-applies Observations already stored for this session, in
    /// order, to a session restored from its checkpoint (as created, before any answer). Stops at
    /// the first Observation that does not fit the next item. Returns how many were applied.
    ///
    /// The stored Observations are kept as they are (not re-created), so nothing is duplicated
    /// or lost, and the items that follow are the same as in an uninterrupted run.
    @discardableResult
    public mutating func replay(_ stored: [Observation]) -> Int {
        precondition(runtime != nil, "attach the lexicon before replaying")
        var applied = 0
        for o in stored {
            guard let item = current, o.session == sessionID else { break }
            switch item {
            case .yesNo(let q):
                let source: ObservationSource = q.kind == .retest ? .spotcheck : .test
                guard o.lemma == q.word, o.source == source,
                      o.result == ObservationResult.yes || o.result == ObservationResult.no else { return applied }
            case .meaningCheck(let q):
                guard o.lemma == q.lemma, o.source == .verify else { return applied }
            }
            apply(o)
            applied += 1
        }
        return applied
    }

    private mutating func apply(_ o: Observation) {
        guard var rt = runtime else { return }
        observations.append(o)
        rt.live.record(o, lexicon: rt.lexicon)
        runtime = rt
        appendNext(after: o)
    }

    /// Appends the next item: a meaning check right after some "yes" answers, else the next slot.
    private mutating func appendNext(after o: Observation?) {
        guard let rt = runtime else { return }
        if let o, o.pseudo != true, o.source != .verify, o.result == ObservationResult.yes {
            let check: Bool
            if config.verifyTargeted, let i = rt.lexicon.index(of: o.lemma) {
                // P from the population curve: what the model expected before this answer.
                let surprise = 1 - rt.live.priorProbability(i)
                yesCount += 1
                yesSurprise += surprise
                let mean = max(0.05, yesSurprise / Double(yesCount))
                check = rng.uniform() < min(0.9, config.verifyFraction * surprise / mean)
            } else {
                yesUntilCheck -= 1
                check = yesUntilCheck <= 0
            }
            if check, let item = MeaningChecks.item(for: o.lemma, lexicon: rt.lexicon, glosses: rt.selector.glosses,
                                                    rng: &rng) {
                yesUntilCheck = drawCheckGap()
                items.append(.meaningCheck(item))
                return
            }
        }
        while slot < schedule.count {
            let kind = schedule[slot]
            slot += 1
            if let item = pick(kind, rt) {
                items.append(.yesNo(item))
                return
            }
        }
    }

    private mutating func drawCheckGap() -> Int {
        guard config.verifyFraction > 0 else { return .max }
        let maxGap = max(1, Int((2 / config.verifyFraction).rounded()) - 1)
        return 1 + Int(rng.next() % UInt64(maxGap))
    }

    private mutating func pick(_ kind: YesNoItem.Kind, _ rt: Runtime) -> YesNoItem? {
        let entries = rt.lexicon.entries
        func real(_ i: Int, _ k: YesNoItem.Kind) -> YesNoItem {
            used.insert(i)
            return YesNoItem(word: entries[i].lemma, kind: k)
        }
        func pop(_ queue: inout [Int]) -> Int? {
            while !queue.isEmpty {
                let i = queue.removeFirst()
                if !used.contains(i) { return i }
            }
            return nil
        }
        switch kind {
        case .pseudoword:
            // Template: a real word of this session (so pseudowords match the session's words).
            let pool = used.isEmpty ? Array(stratifiedQueue.prefix(20)) : used.sorted()
            for _ in 0..<5 {
                let template = pool.isEmpty ? entries[Int(rng.next() % UInt64(max(1, entries.count)))].lemma
                    : entries[pool[Int(rng.next() % UInt64(pool.count))]].lemma
                if let w = rt.selector.pseudowords.matched(to: template, excluding: usedPseudowords, retired: retiredShapes,
                                                           lengthTolerance: config.pseudowordLengthTolerance, rng: &rng) {
                    usedPseudowords.insert(w)
                    return YesNoItem(word: w, kind: .pseudoword)
                }
            }
            return pick(.boundary, rt)
        case .stratified:
            if let i = pop(&stratifiedQueue) { return real(i, .stratified) }
            return pick(.boundary, rt)
        case .retest:
            if let i = pop(&retestQueue) { return real(i, .retest) }
            return pick(.stratified, rt)
        case .boundary:
            return rt.selector.boundary(live: rt.live, used: used, pool: config.boundaryPool, rng: &rng).map { real($0, .boundary) }
        case .uncertain:
            return rt.selector.uncertain(live: rt.live, used: used, rng: &rng).map { real($0, .uncertain) }
        }
    }
}

extension TestSession: Codable {
    enum CodingKeys: String, CodingKey {
        case sessionID, config, lexiconVersion, items, observations, rng, schedule, slot, stratifiedQueue, retestQueue
        case used, usedPseudowords, retiredShapes, live, yesCount, yesSurprise, yesUntilCheck
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        config = try c.decode(TestConfig.self, forKey: .config)
        lexiconVersion = try c.decode(String.self, forKey: .lexiconVersion)
        items = try c.decode([TestItem].self, forKey: .items)
        observations = try c.decode([Observation].self, forKey: .observations)
        rng = try c.decode(SplitMix64.self, forKey: .rng)
        schedule = try c.decode([YesNoItem.Kind].self, forKey: .schedule)
        slot = try c.decode(Int.self, forKey: .slot)
        stratifiedQueue = try c.decode([Int].self, forKey: .stratifiedQueue)
        retestQueue = try c.decode([Int].self, forKey: .retestQueue)
        used = try c.decode(Set<Int>.self, forKey: .used)
        usedPseudowords = try c.decode(Set<String>.self, forKey: .usedPseudowords)
        retiredShapes = try c.decode(Set<PseudowordShape>.self, forKey: .retiredShapes)
        detachedLive = try c.decode(LiveEstimate.State.self, forKey: .live)
        yesCount = try c.decode(Int.self, forKey: .yesCount)
        yesSurprise = try c.decode(Double.self, forKey: .yesSurprise)
        yesUntilCheck = try c.decode(Int.self, forKey: .yesUntilCheck)
        runtime = nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(config, forKey: .config)
        try c.encode(lexiconVersion, forKey: .lexiconVersion)
        try c.encode(items, forKey: .items)
        try c.encode(observations, forKey: .observations)
        try c.encode(rng, forKey: .rng)
        try c.encode(schedule, forKey: .schedule)
        try c.encode(slot, forKey: .slot)
        try c.encode(stratifiedQueue, forKey: .stratifiedQueue)
        try c.encode(retestQueue, forKey: .retestQueue)
        try c.encode(used.sorted(), forKey: .used)
        try c.encode(usedPseudowords.sorted(), forKey: .usedPseudowords)
        try c.encode(retiredShapes.sorted { $0.description < $1.description }, forKey: .retiredShapes)
        try c.encode(runtime?.live.state ?? detachedLive, forKey: .live)
        try c.encode(yesCount, forKey: .yesCount)
        try c.encode(yesSurprise, forKey: .yesSurprise)
        try c.encode(yesUntilCheck, forKey: .yesUntilCheck)
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

    /// Uniform in [0, 1).
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
