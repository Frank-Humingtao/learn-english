import CoreModels
import Lexicon

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A cheap running estimate during a Vocabulary Test (ticket 03): the vocabulary number that moves
/// after every answer, and the per-word P the item selector picks from.
///
/// The full fit (`ProfileEngine.compute`) takes about half a second on the full lexicon, far too
/// slow per answer. Here the population curve (feature weights β, word SD τ) and the response
/// parameters δ, r stay at the values fitted before the test; only the ability θ and the
/// pseudoword false-alarm rate (logit f₀) are updated, warm-started from their previous values, by
/// a 2-D Newton step on this session's answers with the pre-test posterior as a Gaussian prior.
/// Answers about words seen before this session only update those words' own P.
///
/// The test result still comes from the full fit, which also refits β and τ (stratified long-tail
/// items mostly move those), so the final number can differ somewhat from the last live one.
public struct LiveEstimate: Sendable {
    /// Everything that changes during the session, plus the pre-test fit it starts from. Codable
    /// so a resumed test continues exactly where it stopped.
    public struct State: Sendable, Codable, Equatable {
        var features: [WordFeature]
        var weights: [Double]
        var tau: Double
        var theta0: Double, thetaVariance: Double
        var a0: Double, aVariance: Double
        var delta: Double, logitR: Double
        var slip: Double, verifySlip: Double
        var fastYesMs: Int, fastYesWeight: Double
        /// log P(answers | known) − log P(answers | unknown) of each word answered before this session.
        var historyLLR: [Int: Double]
        /// This session's answers per word (lexicon index) and to pseudowords.
        var session: [Int: WordCounts] = [:]
        var pseudoYes = 0.0, pseudoNo = 0.0
        /// Current θ and logit f₀.
        var theta: Double, a: Double
        var thetaPosteriorVariance: Double
    }

    public private(set) var state: State
    let offsets: [Double]
    /// Index of each family's best-known member before the session.
    let familyBest: [Int]

    /// Starts from the profile fitted on everything before the test.
    public init(profile: LearnerProfile) {
        let c = profile.config
        let width = FeatureMatrix(lexicon: profile.lexicon, features: c.features).width
        let dim = width + 5
        var x = profile.fitParameters
        var cov = profile.fitCovariance
        if x.count != dim {
            // A profile built without a fit (should not happen): fall back to the priors.
            x = [c.thetaPriorMean, c.mainSlopePriorMean] + Array(repeating: 0, count: width - 1)
                + [log(c.wordSDPrior), logit(c.pseudowordFalseAlarmPrior), c.realWordExtraPriorMean, logit(c.verifyGuessPrior)]
            cov = []
        }
        func variance(_ k: Int, _ fallback: Double) -> Double {
            cov.count == dim * dim && cov[k * dim + k] > 0 ? cov[k * dim + k] : fallback
        }
        let rates = ResponseRates(s: c.slipRate, sv: c.verifySlipRate, f0: sigmoid(x[dim - 3]),
                                  f: sigmoid(x[dim - 3] + x[dim - 2]), r: sigmoid(x[dim - 1]))
        var llr: [Int: Double] = [:]
        for (i, counts) in profile.observedCounts {
            let (la, lb) = rates.logLikelihoods(counts)
            llr[i] = la - lb
        }
        let thetaVar = variance(0, c.thetaPriorSD * c.thetaPriorSD)
        state = State(features: c.features, weights: Array(x[1...width]), tau: exp(x[width + 1]),
                      theta0: x[0], thetaVariance: thetaVar,
                      a0: x[dim - 3], aVariance: variance(dim - 3, c.pseudowordFalseAlarmPriorSD * c.pseudowordFalseAlarmPriorSD),
                      delta: x[dim - 2], logitR: x[dim - 1], slip: c.slipRate, verifySlip: c.verifySlipRate,
                      fastYesMs: c.fastYesMs, fastYesWeight: c.fastYesWeight, historyLLR: llr,
                      theta: x[0], a: x[dim - 3], thetaPosteriorVariance: thetaVar)
        (offsets, familyBest) = Self.runtime(state, lexicon: profile.lexicon)
    }

    /// Restores a running estimate (e.g. from a test checkpoint) on the same lexicon.
    public init(state: State, lexicon: Lexicon) {
        self.state = state
        (offsets, familyBest) = Self.runtime(state, lexicon: lexicon)
    }

    static func runtime(_ s: State, lexicon: Lexicon) -> ([Double], [Int]) {
        let fm = FeatureMatrix(lexicon: lexicon, features: s.features)
        var offsets = [Double](repeating: 0, count: lexicon.entries.count)
        for i in lexicon.entries.indices {
            var b = 0.0
            var k = 0
            for v in fm.row(i) { b += s.weights[k] * v; k += 1 }
            offsets[i] = b
        }
        // Family best members at the pre-test θ.
        let tmp = LiveEstimate(state: s, offsets: offsets, familyBest: [])
        let p0 = lexicon.entries.indices.map { tmp.probability($0) }
        return (offsets, familyBestIndices(p0, lexicon: lexicon))
    }

    private init(state: State, offsets: [Double], familyBest: [Int]) {
        self.state = state
        self.offsets = offsets
        self.familyBest = familyBest
    }

    // MARK: reading

    /// Current ability θ (logit P(known) at rank 1000 with average other features).
    public var theta: Double { state.theta }
    /// Current P("yes" | pseudoword).
    public var pseudowordFalseAlarmRate: Double { sigmoid(state.a) }

    var rates: ResponseRates {
        ResponseRates(s: state.slip, sv: state.verifySlip, f0: sigmoid(state.a), f: sigmoid(state.a + state.delta),
                      r: sigmoid(state.logitR))
    }

    /// Whether the word was answered before this session or in it.
    public func hasEvidence(_ i: Int) -> Bool { state.historyLLR[i] != nil || state.session[i] != nil }
    /// Whether the word was answered before this session.
    public func answeredBefore(_ i: Int) -> Bool { state.historyLLR[i] != nil }

    /// P(known) of lexicon entry `i` now (posterior for answered words).
    public func probability(_ i: Int) -> Double {
        let cv = Curve(eta: state.theta - offsets[i], tau: state.tau)
        var logitP = log(max(cv.p, 1e-300)) - log(max(cv.q, 1e-300))
        if let h = state.historyLLR[i] { logitP += h }
        if let c = state.session[i] {
            let (la, lb) = rates.logLikelihoods(c)
            logitP += la - lb
        }
        return sigmoid(logitP)
    }

    /// Fast approximation of the population curve π_w at the current θ for words without answers
    /// (probit approximation of the logistic-normal integral; within about 0.02 of `probability`).
    @inline(__always)
    public func priorProbability(_ i: Int) -> Double {
        let scale = 1 / (1 + Double.pi * state.tau * state.tau / 8).squareRoot()
        return sigmoid((state.theta - offsets[i]) * scale)
    }

    /// Word families known now, with an approximate 95% interval (θ uncertainty plus which words
    /// are known; the curve's own uncertainty is only in the full fit).
    public var families: Estimate {
        var sum = 0.0, bern = 0.0, slope = 0.0
        for i in familyBest {
            let p = probability(i)
            sum += p
            bern += p * (1 - p)
            if !hasEvidence(i) {
                let cv = Curve(eta: state.theta - offsets[i], tau: state.tau)
                slope += cv.dEta
            }
        }
        let half = 1.96 * (slope * slope * state.thetaPosteriorVariance + bern).squareRoot()
        return Estimate(estimate: sum, low: max(0, sum - half), high: min(Double(familyBest.count), sum + half))
    }

    // MARK: updating

    /// Adds one answer of this session and re-estimates θ and f₀.
    public mutating func record(_ o: Observation, lexicon: Lexicon) {
        if o.pseudo == true {
            if o.result == ObservationResult.yes { state.pseudoYes += 1 } else if o.result == ObservationResult.no { state.pseudoNo += 1 }
            refit()
            return
        }
        guard ProfileEngine.isEvidence(o.source), let lemma = lexicon.lemma(for: o.lemma),
              let i = lexicon.index(of: lemma) else { return }
        var c = state.session[i] ?? WordCounts()
        switch o.source {
        case .test, .spotcheck:
            if o.result == ObservationResult.yes {
                let fast = (o.rtMs ?? .max) < state.fastYesMs
                c.yes += fast ? state.fastYesWeight : 1
                c.yesItems += 1
            } else if o.result == ObservationResult.no {
                c.no += 1
                c.noItems += 1
            } else {
                return
            }
        default:
            if o.result == ObservationResult.correct { c.correct += 1 } else { c.wrong += 1 }
        }
        state.session[i] = c
        if state.historyLLR[i] == nil { refit() }
    }

    /// Log posterior of (θ, a) over this session's fresh words and pseudowords.
    func logPosterior(_ theta: Double, _ a: Double) -> Double {
        let s = state
        var lp = -0.5 * (theta - s.theta0) * (theta - s.theta0) / s.thetaVariance
            - 0.5 * (a - s.a0) * (a - s.a0) / s.aVariance
        let f0 = sigmoid(a)
        lp += s.pseudoYes * log(f0) + s.pseudoNo * log(1 - f0)
        let rp = ResponseRates(s: s.slip, sv: s.verifySlip, f0: f0, f: sigmoid(a + s.delta), r: sigmoid(s.logitR))
        for (i, c) in s.session where s.historyLLR[i] == nil {
            let cv = Curve(eta: theta - offsets[i], tau: s.tau)
            let (la, lb) = rp.logLikelihoods(c)
            let known = log(max(cv.p, 1e-300)) + la, unknown = log(max(cv.q, 1e-300)) + lb
            let m = max(known, unknown)
            lp += m + log(exp(known - m) + exp(unknown - m))
        }
        return lp
    }

    /// Damped 2-D Newton from the current values (finite differences; a handful of iterations).
    mutating func refit() {
        var x = (state.theta, state.a)
        let h = 1e-4
        var current = logPosterior(x.0, x.1)
        var hess = (0.0, 0.0, 0.0)
        for _ in 0..<20 {
            let fpp = logPosterior(x.0 + h, x.1), fmp = logPosterior(x.0 - h, x.1)
            let fpa = logPosterior(x.0, x.1 + h), fma = logPosterior(x.0, x.1 - h)
            let fpq = logPosterior(x.0 + h, x.1 + h), fmq = logPosterior(x.0 - h, x.1 - h)
            let g0 = (fpp - fmp) / (2 * h), g1 = (fpa - fma) / (2 * h)
            let h00 = (fpp - 2 * current + fmp) / (h * h)
            let h11 = (fpa - 2 * current + fma) / (h * h)
            let h01 = (fpq - fpp - fpa + 2 * current - fmp - fma + fmq) / (2 * h * h)
            hess = (h00, h01, h11)
            // Solve (−H) step = g, with damping if −H is not positive definite.
            var a00 = -h00, a11 = -h11
            let a01 = -h01
            var det = a00 * a11 - a01 * a01
            if !(a00 > 0 && det > 0) {
                a00 = max(abs(a00), 1) * 2
                a11 = max(abs(a11), 1) * 2
                det = a00 * a11 - a01 * a01
            }
            var s0 = (a11 * g0 - a01 * g1) / det
            var s1 = (a00 * g1 - a01 * g0) / det
            var next = logPosterior(x.0 + s0, x.1 + s1)
            var halvings = 0
            while !(next >= current) && halvings < 10 {
                s0 /= 2
                s1 /= 2
                next = logPosterior(x.0 + s0, x.1 + s1)
                halvings += 1
            }
            guard next >= current else { break }
            x = (x.0 + s0, x.1 + s1)
            let gain = next - current
            current = next
            if gain < 1e-9 || (abs(s0) < 1e-6 && abs(s1) < 1e-6) { break }
        }
        state.theta = x.0
        state.a = x.1
        // Marginal variance of θ from the 2×2 negative Hessian.
        let (h00, h01, h11) = hess
        let det = h00 * h11 - h01 * h01
        if h00 < 0 && det > 0 { state.thetaPosteriorVariance = -h11 / det }
    }
}
