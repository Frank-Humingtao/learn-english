import CoreModels
import Lexicon
import ProfileEngine
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// End-to-end check with simulated Learners whose true knowledge is known.
@Suite struct SimulatedLearnerTests {
    static let lexiconSize = 20000
    let lexicon = syntheticLexicon(count: SimulatedLearnerTests.lexiconSize)

    /// A Learner whose knowledge of each word is drawn once from a Rasch model with
    /// per-word noise (so the fitted model is not exactly the generating one), answering
    /// with occasional slips and guesses.
    struct SimulatedLearner {
        let knows: [Bool] // by rank - 1
        var rng: SeededRNG
        let slip = 0.03
        let guess: Double

        init(theta: Double, slope: Double, seed: UInt64, count: Int, guess: Double = 0.03) {
            self.guess = guess
            var rng = SeededRNG(seed: seed)
            knows = (1...count).map { r in
                let noise = gaussian(&rng)
                let p = 1 / (1 + exp(-(theta - slope * log(Double(r) / 1000) + noise)))
                return Double.random(in: 0..<1, using: &rng) < p
            }
            self.rng = rng
        }

        var trueSize: Int { knows.filter { $0 }.count }

        mutating func answer(rank: Int) -> Bool {
            let u = Double.random(in: 0..<1, using: &rng)
            return knows[rank - 1] ? u > slip : u < guess
        }

        mutating func answerPseudoword() -> Bool {
            Double.random(in: 0..<1, using: &rng) < guess
        }
    }

    static func gaussian(_ rng: inout SeededRNG) -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &rng), 1e-12)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    /// Baseline: 150 items spread evenly over log rank. Then `shortTests` tests of 60
    /// untested items whose current P is closest to 0.5 (randomized among the best 3×).
    /// Every third real word is followed by a pseudoword (pseudowords ≈ 1/4 of Yes/No items).
    func run(_ learner: inout SimulatedLearner, shortTests: Int, seed: UInt64) -> LearnerProfile {
        var rng = SeededRNG(seed: seed)
        var tested = Set<Int>()
        var observations: [Observation] = []
        var minute = 0
        func record(_ rank: Int, day: Int) {
            tested.insert(rank)
            minute += 1
            observations.append(obs(word(rank), .test, learner.answer(rank: rank) ? "yes" : "no",
                                    day: day, minute: minute % 600))
            if tested.count % 3 == 0 {
                observations.append(Observation(ts: ts(day: day, minute: minute % 600), lemma: "zz\(tested.count)",
                                                source: .test, result: learner.answerPseudoword() ? "yes" : "no",
                                                pseudo: true))
            }
        }
        for k in 0..<150 {
            let r = Int(exp(log(Double(Self.lexiconSize)) * (Double(k) + 0.5) / 150).rounded())
            if !tested.contains(r) { record(max(1, r), day: 0) }
        }
        for t in 1...max(1, shortTests) where shortTests > 0 {
            let profile = ProfileEngine.compute(observations: observations, lexicon: lexicon)
            let candidates = (1...Self.lexiconSize).filter { !tested.contains($0) }
                .sorted { abs(profile.probabilities[$0 - 1] - 0.5) < abs(profile.probabilities[$1 - 1] - 0.5) }
            var pool = Array(candidates.prefix(180))
            pool.shuffle(using: &rng)
            for r in pool.prefix(60) { record(r, day: t * 2) }
        }
        return ProfileEngine.compute(observations: observations, lexicon: lexicon)
    }

    @Test(arguments: [
        (theta: 0.0, slope: 2.5, seed: UInt64(4)),   // true size ~2k lemmas
        (theta: 3.0, slope: 2.0, seed: UInt64(1)),   // ~8k
        (theta: 2.0, slope: 1.2, seed: UInt64(2)),   // ~6k, flat curve
        (theta: 4.5, slope: 1.5, seed: UInt64(3)),   // ~14k
    ])
    func estimateLandsNearTheTrueSize(theta: Double, slope: Double, seed: UInt64) {
        var learner = SimulatedLearner(theta: theta, slope: slope, seed: seed, count: Self.lexiconSize)
        let truth = Double(learner.trueSize)
        let profile = run(&learner, shortTests: 10, seed: seed &+ 100)
        let v = profile.vocabulary.lemmas
        let relativeError = abs(v.estimate - truth) / truth
        // The contract is the interval: the model now also estimates the real-word false-alarm rate,
        // which this design (few long-tail items) pins down only loosely, so a point estimate can be
        // off by up to about a third while the interval still covers the truth.
        #expect(relativeError < 0.35, "f0 \(profile.pseudowordFalseAlarmRate) f \(profile.falseAlarmRate) weights \(profile.weights) theta \(profile.theta) truth \(truth) estimate \(v.estimate) [\(v.low), \(v.high)]")
        #expect(v.low <= truth && truth <= v.high, "truth \(truth) outside [\(v.low), \(v.high)]")
    }
}
