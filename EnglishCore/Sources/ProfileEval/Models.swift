import CoreModels
import Foundation
import Lexicon
import ProfileEngine

/// What a scored answer was: a Yes/No item (`test` / `spotcheck`) or a meaning check (`verify`).
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case yesNo
    case verify
}

/// A total with its 95% interval.
public struct Interval: Codable, Sendable, Equatable {
    public var estimate: Double
    public var low: Double
    public var high: Double

    public init(estimate: Double, low: Double, high: Double) {
        self.estimate = rounded(estimate)
        self.low = rounded(low)
        self.high = rounded(high)
    }

    public init(_ e: Estimate) { self.init(estimate: e.estimate, low: e.low, high: e.high) }

    public var halfWidth: Double { (high - low) / 2 }
    /// Half width relative to the estimate (0.2 = ±20%).
    public var relativeHalfWidth: Double { estimate > 0 ? halfWidth / estimate : .infinity }
    /// Standard error implied by the interval (normal approximation).
    public var standardError: Double { halfWidth / 1.96 }
    public func contains(_ v: Double) -> Bool { low <= v && v <= high }
}

/// A model fitted on some Observations: what the evaluation needs from it.
public struct ModelFit {
    /// P(known) per lexicon entry, in `lexicon.entries` order. This is what gets published.
    public var knowledge: [Double]
    public var lemmas: Interval
    public var families: Interval
    /// Families at BNC/COCA levels ≤ 14 and above, when the model reports them.
    public var coreFamilies: Interval?
    public var tailFamilies: Interval?
    /// Predicted probability of the observed outcome of an item about lexicon entry `entry`:
    /// P("yes") for a Yes/No item, P(correct) for a meaning check. Models with a response layer
    /// (guessing, slips) put it here; it must not leak into `knowledge`.
    public var respond: (_ entry: Int, _ kind: ItemKind) -> Double

    public init(knowledge: [Double], lemmas: Interval, families: Interval,
                respond: @escaping (_ entry: Int, _ kind: ItemKind) -> Double) {
        self.knowledge = knowledge
        self.lemmas = lemmas
        self.families = families
        self.respond = respond
    }

    public init(knowledge: [Double], lemmas: Interval, families: Interval, coreFamilies: Interval?,
                tailFamilies: Interval?, respond: @escaping (_ entry: Int, _ kind: ItemKind) -> Double) {
        self.init(knowledge: knowledge, lemmas: lemmas, families: families, respond: respond)
        self.coreFamilies = coreFamilies
        self.tailFamilies = tailFamilies
    }
}

/// The seam between the evaluation and a model implementation. A model is a pure function of
/// Observations and the lexicon; the evaluation decides which Observations it gets to see.
public protocol VocabularyModel {
    /// Short name used in reports.
    var name: String { get }
    func fit(observations: [Observation], lexicon: Lexicon) -> ModelFit
}

/// The Profile Engine before ticket 02 (ADR 0002 baseline, frozen as `LegacyProfileEngine`): Rasch
/// on ln rank with per-word deviations and a guessing floor from pseudowords.
public struct LegacyProfileModel: VocabularyModel {
    public var name: String
    public var config: LegacyProfileConfig

    public init(name: String = "legacy", config: LegacyProfileConfig = LegacyProfileConfig()) {
        self.name = name
        self.config = config
    }

    public func fit(observations: [Observation], lexicon: Lexicon) -> ModelFit {
        let profile = LegacyProfileEngine.compute(observations: observations, lexicon: lexicon, config: config)
        let p = profile.probabilities
        let g = profile.falseAlarmRate
        let s = profile.slipRate
        return ModelFit(knowledge: p, lemmas: Interval(profile.lemmas), families: Interval(profile.families)) { i, kind in
            // Mirrors the engine's own likelihood: Yes/No answers carry guessing and slips,
            // meaning checks are taken at face value.
            kind == .yesNo ? g + (1 - g - s) * p[i] : p[i]
        }
    }
}

/// The Profile Engine (`ProfileEngine.compute`, ticket 02): knowledge layer σ(θ − β·x_w) over word
/// features, response layer with slips, false alarms and meaning-check guessing.
public struct TwoLayerModel: VocabularyModel {
    public var name: String
    public var config: ProfileConfig

    public init(name: String = "twolayer", config: ProfileConfig = ProfileConfig()) {
        self.name = name
        self.config = config
    }

    public func fit(observations: [Observation], lexicon: Lexicon) -> ModelFit {
        let profile = ProfileEngine.compute(observations: observations, lexicon: lexicon, config: config)
        let p = profile.probabilities
        let f = profile.falseAlarmRate, r = profile.verifyGuessRate
        let s = config.slipRate, sv = config.verifySlipRate
        return ModelFit(knowledge: p, lemmas: Interval(profile.vocabulary.lemmas),
                        families: Interval(profile.vocabulary.families),
                        coreFamilies: Interval(profile.vocabulary.core.families),
                        tailFamilies: Interval(profile.vocabulary.tail.families)) { i, kind in
            let yes = (1 - s) * p[i] + f * (1 - p[i])
            switch kind {
            case .yesNo: return yes
            case .verify:
                // A meaning check is only asked after a "yes": P(correct | yes).
                return ((1 - s) * (1 - sv) * p[i] + f * r * (1 - p[i])) / yes
            }
        }
    }
}

/// "Frequency only" reference model: one logistic regression of the answer on ln rank,
/// `P = σ(a − b·(ln rank − ln 1000))`, fitted on all real-word answers (Yes/No and meaning
/// checks alike, no decay), with no per-word deviation and no response layer. Pseudowords are
/// ignored. Any model worth shipping should beat it on held-out prediction.
public struct FrequencyBaselineModel: VocabularyModel {
    public var name: String
    public var referenceRank: Double
    /// Weak Gaussian priors keep the fit finite on tiny or one-sided data.
    public var interceptPrior: (mean: Double, sd: Double) = (0, 5)
    public var slopePrior: (mean: Double, sd: Double) = (1, 5)

    public init(name: String = "frequency", referenceRank: Double = 1000) {
        self.name = name
        self.referenceRank = referenceRank
    }

    public func fit(observations: [Observation], lexicon: Lexicon) -> ModelFit {
        let lnRef = log(referenceRank)
        let x = lexicon.entries.map { log(Double($0.rank)) - lnRef }
        let items = ScoredItem.extract(observations, lexicon: lexicon)
        let data = items.map { (x: x[$0.entry], y: $0.y) }
        let (a, b, cov) = Self.logistic(data, intercept: interceptPrior, slope: slopePrior)
        let p = x.map { sigmoid(a - b * $0) }
        let families = familyBest(p, lexicon: lexicon)
        return ModelFit(knowledge: p, lemmas: sumInterval(p, x, cov),
                        families: sumInterval(families.map { p[$0] }, families.map { x[$0] }, cov)) { i, _ in p[i] }
    }

    /// MAP of (a, b) in P(y=1) = σ(a − b·x) by Newton with step halving; returns the
    /// posterior covariance (cov_aa, cov_ab, cov_bb).
    static func logistic(_ data: [(x: Double, y: Double)], intercept: (mean: Double, sd: Double),
                         slope: (mean: Double, sd: Double)) -> (Double, Double, (Double, Double, Double)) {
        var a = intercept.mean, b = slope.mean
        let va = intercept.sd * intercept.sd, vb = slope.sd * slope.sd
        func logPost(_ a: Double, _ b: Double) -> Double {
            var l = -(a - intercept.mean) * (a - intercept.mean) / (2 * va) - (b - slope.mean) * (b - slope.mean) / (2 * vb)
            for d in data {
                let eta = a - b * d.x
                l += d.y * eta - softplus(eta)
            }
            return l
        }
        func derivatives(_ a: Double, _ b: Double) -> (ga: Double, gb: Double, haa: Double, hab: Double, hbb: Double) {
            var ga = -(a - intercept.mean) / va, gb = -(b - slope.mean) / vb
            var haa = -1 / va, hab = 0.0, hbb = -1 / vb
            for d in data {
                let p = sigmoid(a - b * d.x)
                let r = d.y - p, w = p * (1 - p)
                ga += r
                gb -= r * d.x
                haa -= w
                hab += w * d.x
                hbb -= w * d.x * d.x
            }
            return (ga, gb, haa, hab, hbb)
        }
        var current = logPost(a, b)
        for _ in 0..<100 {
            let d = derivatives(a, b)
            let det = d.haa * d.hbb - d.hab * d.hab
            guard det != 0 else { break }
            let da = -(d.hbb * d.ga - d.hab * d.gb) / det
            let db = -(-d.hab * d.ga + d.haa * d.gb) / det
            var step = 1.0, accepted = false
            for _ in 0..<40 {
                let cand = logPost(a + step * da, b + step * db)
                if cand >= current { current = cand; accepted = true; break }
                step /= 2
            }
            guard accepted else { break }
            a += step * da
            b += step * db
            if abs(step * da) < 1e-10 && abs(step * db) < 1e-10 { break }
        }
        let d = derivatives(a, b)
        let det = d.haa * d.hbb - d.hab * d.hab
        return (a, b, (-d.hbb / det, d.hab / det, -d.haa / det))
    }
}

/// Index of the best-known member lemma of each family (P(family) = max over members),
/// in order of first appearance.
func familyBest(_ p: [Double], lexicon: Lexicon) -> [Int] {
    var best: [String: Int] = [:]
    var order: [String] = []
    for (i, e) in lexicon.entries.enumerated() {
        if let j = best[e.family] {
            if p[i] > p[j] { best[e.family] = i }
        } else {
            best[e.family] = i
            order.append(e.family)
        }
    }
    return order.map { best[$0]! }
}

/// ΣP with a 95% interval: delta method on (a, b) of η = a − b·x plus the Bernoulli spread.
func sumInterval(_ ps: [Double], _ xs: [Double], _ cov: (Double, Double, Double)) -> Interval {
    var sum = 0.0, ga = 0.0, gb = 0.0, bern = 0.0
    for (p, x) in zip(ps, xs) {
        let d = p * (1 - p)
        sum += p
        ga += d
        gb -= d * x
        bern += d
    }
    let variance = ga * ga * cov.0 + 2 * ga * gb * cov.1 + gb * gb * cov.2 + bern
    let half = 1.96 * sqrt(max(0, variance))
    return Interval(estimate: sum, low: max(0, sum - half), high: min(Double(ps.count), sum + half))
}

func sigmoid(_ z: Double) -> Double {
    z >= 0 ? 1 / (1 + exp(-z)) : exp(z) / (1 + exp(z))
}

func softplus(_ z: Double) -> Double {
    z > 0 ? z + log1p(exp(-z)) : log1p(exp(z))
}

/// Rounds to 6 decimals so reports are short and stable.
func rounded(_ x: Double) -> Double {
    x.isFinite ? (x * 1e6).rounded() / 1e6 : x
}
