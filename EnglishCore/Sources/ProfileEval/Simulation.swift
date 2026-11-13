import CoreModels
import Foundation
import Lexicon
import TestEngine

/// How a simulated Learner answers.
public enum AnswerStyle: String, Codable, Sendable, CaseIterable {
    /// Says "yes" to unknown words and pseudowords only by mis-tap.
    case honest
    /// Says "yes" to many unknown real words that merely look familiar, and to some pseudowords.
    case overclaiming

    /// P("yes" | real word not known).
    var yesIfUnknown: Double { self == .honest ? 0.03 : 0.25 }
    /// P("yes" | pseudoword).
    var pseudowordYes: Double { self == .honest ? 0.03 : 0.08 }
}

/// Parameters of the simulated Learners. Defaults mimic the real Baseline Test plus one short test.
public struct SimulationOptions: Sendable, Equatable {
    public var seed: UInt64 = 1
    /// Ability (logit at rank 1000) of each setting; each runs with every `AnswerStyle`.
    public var thetas: [Double] = [0.5, 2.0, 3.5]
    public var learnersPerSetting = 2
    /// True knowledge: P(know w) = σ(θ − slope·ln(rank/1000) + ε_w), ε_w ~ N(0, wordSD²).
    public var slope = 1.6
    public var wordSD = 1.0
    /// Real Yes/No items of the baseline and of the short test (stratified over 25 ln-rank strata).
    public var baselineItems = 450
    public var shortItems = 250
    /// Share of pseudowords among Yes/No items.
    public var pseudowordShare = 0.15
    /// P(meaning check after a "yes").
    public var verifyShare = 0.10
    /// P(slip): "no" to a known word.
    public var slip = 0.03
    /// P(correct meaning check | word not known) (four choices plus "不认识").
    public var verifyGuess = 0.3
    /// P(correct meaning check | word known).
    public var verifyKnown = 0.95
    /// How the tests choose items. `.stratified` uses `baselineItems` / `shortItems` real words;
    /// the other flows run the 450 + 300 Yes/No items of `TestConfig.baseline` / `.short`.
    public var flow: SimulatedFlow = .stratified
    /// Test Engine settings of the baseline and the short test (`.engine` flow; `.legacy` uses only
    /// their Yes/No counts).
    public var baselineTest = TestConfig.baseline
    public var shortTest = TestConfig.short

    public init() {}
}

/// A simulated Learner with a known true knowledge state and the Observations it produced.
public struct SimulatedLearner: Sendable {
    public var label: String
    public var style: AnswerStyle
    public var theta: Double
    /// True knowledge per lexicon entry.
    public var knows: [Bool]
    public var observations: [Observation]
    /// What the test flow did (flows other than `.stratified`).
    public var flowStats: FlowStats?

    public var trueLemmas: Int { knows.filter { $0 }.count }

    /// Families whose most frequent member (lowest rank) is known. Every model publishes
    /// P(family) = max over its members, i.e. the chance of knowing the family's best-known word;
    /// "any member known" would count a family through a rare derived form drawn independently of
    /// its base, which the simulation allows but no real Learner does (ticket 02).
    public func trueFamilies(_ lexicon: Lexicon) -> Int {
        var seen = Set<String>()
        var count = 0
        for (i, e) in lexicon.entries.enumerated() where seen.insert(e.family).inserted {
            if knows[i] { count += 1 } // entries are in rank order: the first member seen is the most frequent
        }
        return count
    }

    /// Generates one Learner and its baseline + short test.
    public static func generate(lexicon: Lexicon, theta: Double, style: AnswerStyle, seed: UInt64,
                                label: String, options o: SimulationOptions) -> SimulatedLearner {
        var rng = SeededRNG(seed: seed)
        let entries = lexicon.entries
        let knows = entries.map { e -> Bool in
            let eta = theta - o.slope * log(Double(e.rank) / 1000) + o.wordSD * rng.gaussian()
            return rng.uniform() < 1 / (1 + exp(-eta))
        }
        if o.flow != .stratified {
            let answerer = SimulatedAnswerer(knows: knows, style: style, options: o, lexicon: lexicon)
            let (observations, stats) = FlowSimulation.run(o.flow, answerer: answerer, label: label, rng: &rng)
            return SimulatedLearner(label: label, style: style, theta: theta, knows: knows, observations: observations,
                                    flowStats: stats)
        }

        // 25 strata equally wide in ln(position).
        let strataCount = 25
        let lnN = log(Double(entries.count))
        var strata = [[Int]](repeating: [], count: strataCount)
        for i in entries.indices {
            strata[min(strataCount - 1, Int(log(Double(i + 1)) / lnN * Double(strataCount)))].append(i)
        }

        var tested = Set<Int>()
        var observations: [Observation] = []
        let start = 1_767_571_200.0 // 2026-01-05T00:00:00Z
        for (s, items) in [o.baselineItems, o.shortItems].enumerated() where items > 0 {
            let session = "sim-\(label)-\(s + 1)"
            var t = start + Double(s) * 86400
            // Sample real words: equal share per stratum, without replacement across sessions; a
            // stratum too small for its share (the first few hold only a handful of words) passes
            // the rest on to the next.
            var picked: [Int] = []
            var carry = 0
            for (h, stratum) in strata.enumerated() {
                let want = items / strataCount + (h < items % strataCount ? 1 : 0) + carry
                var pool = stratum.filter { !tested.contains($0) }
                partialShuffle(&pool, count: want, rng: &rng)
                let take = min(want, pool.count)
                picked += pool.prefix(take)
                carry = want - take
            }
            partialShuffle(&picked, count: picked.count, rng: &rng)
            let pseudoTotal = Int((Double(picked.count) * o.pseudowordShare / (1 - o.pseudowordShare)).rounded())
            func add(_ lemma: String, _ source: ObservationSource, _ result: String, pseudo: Bool? = nil) {
                observations.append(Observation(ts: Timestamp.iso(t), lemma: lemma, source: source, result: result,
                                                rtMs: 1500, session: session, pseudo: pseudo,
                                                lexicon: lexicon.version))
                t += 4
            }
            for (k, i) in picked.enumerated() {
                tested.insert(i)
                let u = rng.uniform()
                let yes = knows[i] ? u >= o.slip : u < style.yesIfUnknown
                add(entries[i].lemma, .test, yes ? ObservationResult.yes : ObservationResult.no)
                if yes && rng.uniform() < o.verifyShare {
                    let correct = rng.uniform() < (knows[i] ? o.verifyKnown : o.verifyGuess)
                    add(entries[i].lemma, .verify, correct ? ObservationResult.correct : ObservationResult.wrong)
                }
                if picked.count > 0 && (k + 1) * pseudoTotal / picked.count > k * pseudoTotal / picked.count {
                    let yesP = rng.uniform() < style.pseudowordYes
                    add("qzx\(s)p\(k)", .test, yesP ? ObservationResult.yes : ObservationResult.no, pseudo: true)
                }
            }
        }
        return SimulatedLearner(label: label, style: style, theta: theta, knows: knows, observations: observations)
    }

    /// The Learners of `options`, in a fixed order.
    public static func population(lexicon: Lexicon, options o: SimulationOptions) -> [SimulatedLearner] {
        var out: [SimulatedLearner] = []
        var k: UInt64 = 0
        for theta in o.thetas {
            for style in AnswerStyle.allCases {
                for r in 0..<o.learnersPerSetting {
                    let label = "\(style.rawValue)-t\(theta)-\(r + 1)"
                    out.append(generate(lexicon: lexicon, theta: theta, style: style,
                                        seed: o.seed &* 1_000_003 &+ k, label: label, options: o))
                    k += 1
                }
            }
        }
        return out
    }
}

/// Fisher–Yates on the first `count` positions (platform-independent, unlike `shuffle(using:)`'s
/// unspecified algorithm).
func partialShuffle(_ a: inout [Int], count: Int, rng: inout SeededRNG) {
    guard a.count > 1 else { return }
    for i in 0..<min(count, a.count - 1) {
        let j = i + Int(rng.next() % UInt64(a.count - i))
        a.swapAt(i, j)
    }
}
