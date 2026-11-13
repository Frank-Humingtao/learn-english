import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import TestEngine

/// How the simulated Learners' tests choose their items.
public enum SimulatedFlow: String, Codable, Sendable, CaseIterable {
    /// Idealized: equal share per ln-rank stratum, verification after 10% of "yes" (ticket 01's
    /// default, independent of any selector).
    case stratified
    /// The Test Engine before ticket 03 at the same Yes/No budget: untested words closest to
    /// P = 0.5 (randomesque), 25% pseudowords, 10% spot checks of Mastered words, meaning checks of
    /// random "yes" words at the end (30 per 680 Yes/No items).
    case legacy
    /// The Test Engine (`TestSession`): Neyman-stratified / uncertain / boundary / retest real
    /// words, matched pseudowords, inline verification.
    case engine
}

/// What a simulated flow did, for the report.
public struct FlowStats: Codable, Sendable, Equatable {
    /// Real-word Yes/No items, those beyond lemma rank 8000, meaning checks and pseudowords.
    public var realItems = 0
    public var beyond8k = 0
    public var meaningChecks = 0
    public var pseudowords = 0
    /// Engine only: mean and max time per answer (record + live estimate) in ms, and the last live
    /// estimate of each test against the full fit right after it.
    public var answerMeanMs: Double?
    public var answerMaxMs: Double?
    public var liveVsFullRelativeGap: Double?
}

/// Answers of a simulated Learner.
struct SimulatedAnswerer {
    let knows: [Bool]
    let style: AnswerStyle
    let options: SimulationOptions
    let lexicon: Lexicon

    func known(_ word: String) -> Bool {
        lexicon.lemma(for: word).flatMap(lexicon.index(of:)).map { knows[$0] } ?? false
    }

    func yes(_ word: String, pseudo: Bool, rng: inout SeededRNG) -> Bool {
        let u = rng.uniform()
        if pseudo { return u < style.pseudowordYes }
        return known(word) ? u >= options.slip : u < style.yesIfUnknown
    }

    func meaningCorrect(_ word: String, rng: inout SeededRNG) -> Bool {
        rng.uniform() < (known(word) ? options.verifyKnown : options.verifyGuess)
    }
}

enum FlowSimulation {
    /// Baseline + short test through `flow`; returns the Observations and stats.
    static func run(_ flow: SimulatedFlow, answerer: SimulatedAnswerer, label: String, rng: inout SeededRNG)
        -> ([Observation], FlowStats) {
        let lexicon = answerer.lexicon
        var observations: [Observation] = []
        var stats = FlowStats()
        var times: [Double] = []
        var gaps: [Double] = []
        let start = 1_767_571_200.0 // 2026-01-05T00:00:00Z
        for (s, config) in [answerer.options.baselineTest, answerer.options.shortTest].enumerated() {
            let size = config.yesNoCount
            let session = "sim-\(label)-\(s + 1)"
            var t = start + Double(s) * 86400
            let profile = ProfileEngine.compute(observations: observations, lexicon: lexicon)
            func stamp() -> String {
                defer { t += 4 }
                return Timestamp.iso(t)
            }
            switch flow {
            case .stratified:
                preconditionFailure("handled by SimulatedLearner.generate")
            case .legacy:
                observations += legacySession(size: size, profile: profile, history: observations, answerer: answerer,
                                              session: session, stamp: stamp, rng: &rng)
            case .engine:
                var ts = TestSession(lexicon: lexicon, profile: profile, history: observations, config: config,
                                     sessionID: session, seed: rng.next())
                let clock = ContinuousClock()
                while let item = ts.current {
                    let answer: TestAnswer
                    switch item {
                    case .yesNo(let q): answer = .yesNo(answerer.yes(q.word, pseudo: q.kind == .pseudoword, rng: &rng))
                    case .meaningCheck(let q):
                        let ok = answerer.meaningCorrect(q.lemma, rng: &rng)
                        answer = .meaning(ok ? q.correctIndex : (q.correctIndex + 1) % 4)
                    }
                    let at = stamp()
                    let elapsed = clock.measure {
                        ts.answer(answer, rtMs: 1500, at: at)
                        _ = ts.estimate
                    }
                    times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
                }
                let full = ProfileEngine.compute(observations: observations + ts.observations, lexicon: lexicon)
                if let live = ts.estimate?.estimate, full.vocabulary.families.estimate > 0 {
                    gaps.append(abs(live - full.vocabulary.families.estimate) / full.vocabulary.families.estimate)
                }
                observations += ts.observations
            }
        }
        for o in observations {
            if o.pseudo == true { stats.pseudowords += 1; continue }
            if o.source == .verify { stats.meaningChecks += 1; continue }
            stats.realItems += 1
            if (lexicon.entry(lemma: o.lemma)?.rank ?? 0) > 8000 { stats.beyond8k += 1 }
        }
        if !times.isEmpty {
            stats.answerMeanMs = rounded(times.reduce(0, +) / Double(times.count))
            stats.answerMaxMs = rounded(times.max()!)
        }
        if !gaps.isEmpty { stats.liveVsFullRelativeGap = rounded(gaps.reduce(0, +) / Double(gaps.count)) }
        return (observations, stats)
    }

    /// The pre-ticket-03 selector (`ItemSelector` as of PR #17), kept here only for comparison.
    static func legacySession(size: Int, profile: LearnerProfile, history: [Observation], answerer: SimulatedAnswerer,
                              session: String, stamp: () -> String, rng: inout SeededRNG) -> [Observation] {
        let lexicon = answerer.lexicon
        let entries = lexicon.entries
        let p = profile.probabilities
        var tested = Set<Int>()
        for o in history where o.pseudo != true {
            if let l = lexicon.lemma(for: o.lemma), let i = lexicon.index(of: l) { tested.insert(i) }
        }
        let eligible = { (i: Int) in MeaningChecks.gloss(entries[i]) != nil }
        let pseudoCount = Int((Double(size) * 0.25).rounded())
        var mastered = entries.indices.filter { profile.bands[$0] == .mastered && eligible($0) }
        partialShuffle(&mastered, count: mastered.count, rng: &rng)
        let spot = Array(mastered.prefix(Int((Double(size) * 0.10).rounded())))
        let realCount = size - pseudoCount - spot.count
        let excluded = tested.union(spot)
        let candidates = entries.indices.filter { !excluded.contains($0) && eligible($0) }
            .sorted { abs(p[$0] - 0.5) != abs(p[$1] - 0.5) ? abs(p[$0] - 0.5) < abs(p[$1] - 0.5) : $0 < $1 }
        var pool = Array(candidates.prefix(realCount * 3))
        partialShuffle(&pool, count: pool.count, rng: &rng)
        // (index or -1 for a pseudoword, is spot check)
        var items: [(Int, Bool)] = pool.prefix(realCount).map { ($0, false) } + spot.map { ($0, true) }
            + Array(repeating: (-1, false), count: pseudoCount)
        // Fisher–Yates on positions.
        var order = Array(items.indices)
        partialShuffle(&order, count: order.count, rng: &rng)
        items = order.map { items[$0] }

        var out: [Observation] = []
        var yes: [String] = []
        for (k, (i, isSpot)) in items.enumerated() {
            if i < 0 {
                let y = answerer.yes("", pseudo: true, rng: &rng)
                out.append(Observation(ts: stamp(), lemma: "qzx\(session)p\(k)", source: .test,
                                       result: y ? ObservationResult.yes : ObservationResult.no, rtMs: 1500,
                                       session: session, pseudo: true, lexicon: lexicon.version))
                continue
            }
            let w = entries[i].lemma
            let y = answerer.yes(w, pseudo: false, rng: &rng)
            if y { yes.append(w) }
            out.append(Observation(ts: stamp(), lemma: w, source: isSpot ? .spotcheck : .test,
                                   result: y ? ObservationResult.yes : ObservationResult.no, rtMs: 1500,
                                   session: session, lexicon: lexicon.version))
        }
        var checkIdx = Array(yes.indices)
        partialShuffle(&checkIdx, count: checkIdx.count, rng: &rng)
        for j in checkIdx.prefix(Int((Double(size) * 30 / 680).rounded())) {
            let ok = answerer.meaningCorrect(yes[j], rng: &rng)
            out.append(Observation(ts: stamp(), lemma: yes[j], source: .verify,
                                   result: ok ? ObservationResult.correct : ObservationResult.wrong, rtMs: 3000,
                                   session: session, lexicon: lexicon.version))
        }
        return out
    }
}
