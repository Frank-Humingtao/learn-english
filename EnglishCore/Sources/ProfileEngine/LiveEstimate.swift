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
/// slow per answer. Here the word SD τ, the secondary feature weights and the meaning-check guessing
/// rate r stay at the values fitted before the test; the ability θ, the main frequency slope β₁,
/// the pseudoword false-alarm rate (logit f₀) and the real-word extra δ are re-estimated after every
/// answer, warm-started from their previous values, by a small Newton step on this session's
/// answers with the pre-test posterior of those four as a Gaussian prior. (With δ frozen, an
/// over-claiming Learner's live number ran far above the full fit.) Answers about words seen before this session
/// only update those words' own P.
///
/// The test result still comes from the full fit, so the final number can differ somewhat from
/// the last live one (`profile-engine eval --sim-flow engine` reports by how much).
public struct LiveEstimate: Sendable {
    /// Everything that changes during the session, plus the pre-test fit it starts from. Codable
    /// so a resumed test continues exactly where it stopped.
    public struct State: Sendable, Codable, Equatable {
        var features: [WordFeature]
        /// Pre-test feature weights; the first (main slope) is re-estimated as `x[1]`.
        var weights: [Double]
        var tau: Double
        /// Pre-test posterior of x = (θ, β₁, logit f₀, δ): mean and precision (row-major 4×4).
        var mean0: [Double]
        var precision0: [Double]
        var logitR: Double
        var slip: Double, verifySlip: Double
        var fastYesMs: Int, fastYesWeight: Double
        /// log P(answers | known) − log P(answers | unknown) of each word answered before this session.
        var historyLLR: [Int: Double]
        /// This session's answers per word (lexicon index) and to pseudowords.
        var session: [Int: WordCounts] = [:]
        var pseudoYes = 0.0, pseudoNo = 0.0
        /// Current x and its posterior covariance.
        var x: [Double]
        var covariance: [Double]
    }

    public private(set) var state: State
    /// Main feature column x₁ and the fixed rest of the difficulty β₂…·x₂… per entry.
    let main: [Double]
    let rest: [Double]
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
        let idx = [0, 1, dim - 3, dim - 2]
        let n = Self.n
        var sub = [Double](repeating: 0, count: n * n)
        let fallback = [c.thetaPriorSD * c.thetaPriorSD, c.mainSlopePriorSD * c.mainSlopePriorSD,
                        c.pseudowordFalseAlarmPriorSD * c.pseudowordFalseAlarmPriorSD,
                        c.realWordExtraPriorSD * c.realWordExtraPriorSD]
        for (r, i) in idx.enumerated() {
            for (k, j) in idx.enumerated() {
                sub[r * n + k] = cov.count == dim * dim ? cov[i * dim + j] : (r == k ? fallback[r] : 0)
            }
        }
        var diagonal = [Double](repeating: 0, count: n * n)
        for r in 0..<n { diagonal[r * n + r] = 1 / fallback[r] }
        let precision = invert(sub, n) ?? diagonal
        let rates = ResponseRates(s: c.slipRate, sv: c.verifySlipRate, f0: sigmoid(x[dim - 3]),
                                  f: sigmoid(x[dim - 3] + x[dim - 2]), r: sigmoid(x[dim - 1]))
        var llr: [Int: Double] = [:]
        for (i, counts) in profile.observedCounts {
            let (la, lb) = rates.logLikelihoods(counts)
            llr[i] = la - lb
        }
        let mean = [x[0], x[1], x[dim - 3], x[dim - 2]]
        state = State(features: c.features, weights: Array(x[1...width]), tau: exp(x[width + 1]),
                      mean0: mean, precision0: precision, logitR: x[dim - 1],
                      slip: c.slipRate, verifySlip: c.verifySlipRate,
                      fastYesMs: c.fastYesMs, fastYesWeight: c.fastYesWeight, historyLLR: llr,
                      x: mean, covariance: sub)
        (main, rest, familyBest) = Self.runtime(state, lexicon: profile.lexicon)
    }

    /// Restores a running estimate (e.g. from a test checkpoint) on the same lexicon.
    public init(state: State, lexicon: Lexicon) {
        self.state = state
        (main, rest, familyBest) = Self.runtime(state, lexicon: lexicon)
    }

    static func runtime(_ s: State, lexicon: Lexicon) -> ([Double], [Double], [Int]) {
        let fm = FeatureMatrix(lexicon: lexicon, features: s.features)
        let n = lexicon.entries.count
        var main = [Double](repeating: 0, count: n)
        var rest = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var b = 0.0
            var k = 0
            for v in fm.row(i) {
                if k == 0 { main[i] = v } else { b += s.weights[k] * v }
                k += 1
            }
            rest[i] = b
        }
        // Family best members at the pre-test parameters (the same whenever the state is restored).
        var pre = s
        pre.x = s.mean0
        pre.session = [:]
        let tmp = LiveEstimate(state: pre, main: main, rest: rest, familyBest: [])
        let p0 = (0..<n).map { tmp.probability($0) }
        return (main, rest, familyBestIndices(p0, lexicon: lexicon))
    }

    /// Number of re-estimated parameters.
    static let n = 4

    private init(state: State, main: [Double], rest: [Double], familyBest: [Int]) {
        self.state = state
        self.main = main
        self.rest = rest
        self.familyBest = familyBest
    }

    // MARK: reading

    /// Current ability θ (logit P(known) at rank 1000 with average other features).
    public var theta: Double { state.x[0] }
    /// Current main frequency slope.
    public var slope: Double { state.x[1] }
    /// Current P("yes" | pseudoword).
    public var pseudowordFalseAlarmRate: Double { sigmoid(state.x[2]) }

    @inline(__always)
    func eta(_ i: Int, _ x: [Double]) -> Double { x[0] - x[1] * main[i] - rest[i] }

    func rates(_ x: [Double]) -> ResponseRates {
        ResponseRates(s: state.slip, sv: state.verifySlip, f0: sigmoid(x[2]), f: sigmoid(x[2] + x[3]),
                      r: sigmoid(state.logitR))
    }

    /// Whether the word was answered before this session or in it.
    public func hasEvidence(_ i: Int) -> Bool { state.historyLLR[i] != nil || state.session[i] != nil }
    /// Whether the word was answered before this session.
    public func answeredBefore(_ i: Int) -> Bool { state.historyLLR[i] != nil }

    /// P(known) of lexicon entry `i` now (posterior for answered words).
    public func probability(_ i: Int) -> Double {
        let cv = Curve(eta: eta(i, state.x), tau: state.tau)
        var logitP = log(max(cv.p, 1e-300)) - log(max(cv.q, 1e-300))
        if let h = state.historyLLR[i] { logitP += h }
        if let c = state.session[i] {
            let (la, lb) = rates(state.x).logLikelihoods(c)
            logitP += la - lb
        }
        return sigmoid(logitP)
    }

    /// Fast approximation of the population curve π_w now, for words without answers (probit
    /// approximation of the logistic-normal integral; within about 0.02 of `probability`).
    @inline(__always)
    public func priorProbability(_ i: Int) -> Double {
        let scale = 1 / (1 + Double.pi * state.tau * state.tau / 8).squareRoot()
        return sigmoid(eta(i, state.x) * scale)
    }

    /// Word families known now, with an approximate 95% interval (uncertainty of θ and β₁ plus
    /// which words are known; τ and the other weights are only uncertain in the full fit).
    public var families: Estimate {
        // Unanswered words (nearly all) use the one-sigmoid probit approximation: a 9-point
        // quadrature over 25,000 families is too slow per answer in an unoptimized build.
        var sum = 0.0, bern = 0.0, dTheta = 0.0, dSlope = 0.0
        let scale = 1 / (1 + Double.pi * state.tau * state.tau / 8).squareRoot()
        for i in familyBest {
            if hasEvidence(i) {
                let p = probability(i)
                sum += p
                bern += p * (1 - p)
            } else {
                let p = sigmoid(eta(i, state.x) * scale)
                sum += p
                let v = p * (1 - p)
                bern += v
                dTheta += v * scale
                dSlope -= v * scale * main[i]
            }
        }
        let c = state.covariance
        let n = Self.n
        let v = dTheta * dTheta * c[0] + 2 * dTheta * dSlope * c[1] + dSlope * dSlope * c[n + 1]
        let half = 1.96 * (max(0, v) + bern).squareRoot()
        return Estimate(estimate: sum, low: max(0, sum - half), high: min(Double(familyBest.count), sum + half))
    }

    // MARK: updating

    /// Adds one answer of this session and re-estimates θ, β₁, f₀ and δ.
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

    /// Log posterior of x over this session's fresh words and pseudowords, and its gradient.
    func evaluate(_ x: [Double], gradient: Bool = true) -> (Double, [Double]) {
        let s = state
        let n = Self.n
        var lp = 0.0
        var g = [Double](repeating: 0, count: n)
        for r in 0..<n {
            var row = 0.0
            for k in 0..<n { row += s.precision0[r * n + k] * (x[k] - s.mean0[k]) }
            lp -= 0.5 * (x[r] - s.mean0[r]) * row
            g[r] -= row
        }
        let f0 = sigmoid(x[2])
        lp += s.pseudoYes * log(f0) + s.pseudoNo * log(1 - f0)
        g[2] += s.pseudoYes * (1 - f0) - s.pseudoNo * f0
        let rp = rates(x)
        for (i, c) in s.session where s.historyLLR[i] == nil {
            let cv = Curve(eta: eta(i, x), tau: s.tau)
            let (la, lb) = rp.logLikelihoods(c)
            let known = log(max(cv.p, 1e-300)) + la, unknown = log(max(cv.q, 1e-300)) + lb
            let m = max(known, unknown)
            let l = m + log(exp(known - m) + exp(unknown - m))
            lp += l
            guard gradient else { continue }
            let post = exp(known - l)
            let dEta = (post / max(cv.p, 1e-300) - (1 - post) / max(cv.q, 1e-300)) * cv.dEta
            g[0] += dEta
            g[1] -= dEta * main[i]
            let df = (1 - post) * rp.dLogB(c).f
            g[2] += df
            g[3] += df
        }
        return (lp, g)
    }

    func logPosterior(_ x: [Double]) -> Double { evaluate(x, gradient: false).0 }

    /// Hessian by forward differences of the analytic gradient (symmetrized).
    func hessian(_ x: [Double], _ g0: [Double]) -> [Double] {
        let n = Self.n
        let h = 1e-5
        var hess = [Double](repeating: 0, count: n * n)
        for k in 0..<n {
            var xp = x
            xp[k] += h
            let gp = evaluate(xp).1
            for r in 0..<n { hess[r * n + k] = (gp[r] - g0[r]) / h }
        }
        for r in 0..<n {
            for k in (r + 1)..<n {
                let v = (hess[r * n + k] + hess[k * n + r]) / 2
                hess[r * n + k] = v
                hess[k * n + r] = v
            }
        }
        return hess
    }

    /// Damped Newton from the current values (usually one or two steps).
    mutating func refit() {
        let n = Self.n
        var x = state.x
        var (current, g) = evaluate(x)
        var negH = [Double](repeating: 0, count: n * n)
        for _ in 0..<20 {
            negH = hessian(x, g).map { -$0 }
            var lambda = 0.0
            var accepted = false
            // Levenberg–Marquardt damping until the step improves the posterior.
            for _ in 0..<12 {
                var a = negH
                if lambda > 0 { for k in 0..<n { a[k * n + k] += lambda * max(1, abs(negH[k * n + k])) } }
                lambda = lambda == 0 ? 1e-3 : lambda * 10
                guard let st = solve(a, g, n) else { continue }
                let cand = zip(x, st).map { $0 + $1 }
                let (v, cg) = evaluate(cand)
                if v.isFinite && v >= current {
                    let gain = v - current
                    x = cand
                    current = v
                    g = cg
                    accepted = true
                    if gain < 1e-9 || st.allSatisfy({ abs($0) < 1e-6 }) {
                        state.x = x
                        return finish(negH)
                    }
                    break
                }
            }
            if !accepted { break }
        }
        state.x = x
        finish(negH)
    }

    private mutating func finish(_ negH: [Double]) {
        if let c = invert(negH, Self.n), c[0] > 0, c[Self.n + 1] > 0 { state.covariance = c }
    }
}
