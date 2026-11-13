import CoreModels
import Lexicon

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Recomputes the Learner Profile from all Observations. Pure: no IO, no clock. The App and
/// GitHub Actions both call this one function.
///
/// Two layers (research 07 §A, ticket 02):
/// - **Knowledge**: each word is known or not, K_w ~ Bernoulli(π_w), π_w = E_u σ(θ − β·x_w − u),
///   u ~ N(0, τ²), with x_w a few word features (`ProfileConfig.features`; the first is the main
///   frequency scale, the rest ridge-regularized toward 0). With one binary state per word, u_w only
///   acts through this average: τ shapes the curve (flatter middle, tails that still fall at the
///   frequency slope) and is estimated with the other parameters under a log-normal prior. Without
///   it, the false-alarm rate absorbed the heavier tail and honest Learners were over-corrected.
/// - **Response**: P(yes | known) = 1 − s; P(yes | unknown real word) = f with
///   logit f = logit f₀ + δ, where f₀ is the pseudoword false-alarm rate (P(yes | pseudoword));
///   P(correct meaning check | known) = 1 − s_v, | unknown = r (guessing among the choices).
///   Guessing never counts as knowing: only π (and its posterior) is published.
///
/// θ, β, τ, f₀, δ and r are fitted jointly (MAP, damped Newton) on the marginal likelihood
/// Π_w [π_w·P(answers_w | known) + (1 − π_w)·P(answers_w | unknown)] × Π_pseudo P(answer).
/// A word's published P is its posterior P(K_w = 1 | its answers); its standard error and the
/// totals' intervals propagate the parameters' posterior covariance (delta method) plus the
/// Bernoulli spread of which words are actually known.
///
/// Evidence weights: decay (half-life), implausibly fast "yes" answers, and a session quality gate
/// (too many pseudoword false alarms or failed meaning checks → the whole session counts less).
/// Answers about a word given in a session after the one where it was first meaning-checked show
/// the state after learning: they update that word's P but not the population curve.
///
/// The reference time `asOf` (decay) is `config.asOf`, else the latest Observation, so the same
/// Observations always give the same profile.
public enum ProfileEngine {
    public static func compute(
        observations: [Observation], lexicon: Lexicon, config: ProfileConfig = ProfileConfig()
    ) -> LearnerProfile {
        let entries = lexicon.entries
        let features = FeatureMatrix(lexicon: lexicon, features: config.features)
        let evidence = Evidence.collect(observations, lexicon: lexicon, config: config)
        let model = Model(features: features, evidence: evidence, config: config)
        let fit = model.fit()

        // Per-word P, logit gradient (for the delta method) and standard error.
        let dim = model.dim
        var p = [Double](repeating: 0, count: entries.count)
        var grads = [Double](repeating: 0, count: entries.count * dim)
        var se = [Double](repeating: 0, count: entries.count)
        let rp = model.response(fit.params)
        var observed: [Int: WordCounts] = [:]
        for w in evidence.words { observed[w.word] = w.all }
        let tau = exp(fit.params[model.tauIndex])
        for i in entries.indices {
            let row = features.row(i)
            var eta = fit.params[0]
            var k = 1
            for x in row { eta -= fit.params[k] * x; k += 1 }
            let cv = Curve(eta: eta, tau: tau)
            // Logit gradient of π_w = E_u σ(η − u).
            let base = i * dim
            let scale = 1 / max(1e-300, cv.p * cv.q)
            grads[base] = cv.dEta * scale
            k = 1
            for x in row { grads[base + k] = -x * cv.dEta * scale; k += 1 }
            grads[base + model.tauIndex] = cv.dLogTau * scale
            var logitP = log(cv.p) - log(cv.q)
            if let c = observed[i] {
                // logit posterior = logit π + log A − log B; A does not depend on the parameters.
                let (la, lb) = rp.logLikelihoods(c)
                logitP += la - lb
                let dB = rp.dLogB(c)
                grads[base + dim - 3] = -dB.f
                grads[base + dim - 2] = -dB.f
                grads[base + dim - 1] = -dB.r
            }
            let pi = sigmoid(logitP)
            p[i] = pi
            se[i] = pi * (1 - pi) * sqrt(max(0, quadratic(fit.covariance, grads, base, dim)))
        }

        func total(_ idx: [Int]) -> Estimate {
            var sum = 0.0, bern = 0.0
            var g = [Double](repeating: 0, count: dim)
            for i in idx {
                let d = p[i] * (1 - p[i])
                sum += p[i]
                bern += d
                let base = i * dim
                for k in 0..<dim { g[k] += d * grads[base + k] }
            }
            let variance = quadratic(fit.covariance, g, 0, dim) + bern
            let half = 1.96 * sqrt(max(0, variance))
            return Estimate(estimate: sum, low: max(0, sum - half), high: min(Double(idx.count), sum + half))
        }
        let lemmaIdx = Array(entries.indices)
        let familyIdx = familyBestIndices(p, lexicon: lexicon)
        let core = { (i: Int) in entries[i].level <= config.coreLevels }
        let vocabulary = VocabularySize(
            lemmas: total(lemmaIdx), families: total(familyIdx),
            lemmaCount: entries.count, familyCount: familyIdx.count,
            core: VocabularyPart(lemmas: total(lemmaIdx.filter(core)), families: total(familyIdx.filter(core))),
            tail: VocabularyPart(lemmas: total(lemmaIdx.filter { !core($0) }),
                                 families: total(familyIdx.filter { !core($0) })))

        // Person fit (lz) of the Yes/No answers to real words. As in IRT, item difficulties are held
        // at the population curve (feature weights fixed at their prior means) and only θ and the
        // response rates are fitted: a fitted curve would bend to any pattern, random answering included.
        var personFit: Double?
        let yesNo = evidence.words.reduce(0.0) { $0 + $1.pre.yesItems + $1.pre.noItems }
        if yesNo >= Double(config.personFitMinItems) {
            let anchored = Model(features: features, evidence: evidence, config: config, anchored: true)
            let af = anchored.fit()
            let arp = anchored.response(af.params)
            var items: [(Double, Double)] = []
            for w in evidence.words {
                var eta = af.params[0]
                var k = 1
                for x in features.row(w.word) { eta -= af.params[k] * x; k += 1 }
                let pi = Curve(eta: eta, tau: exp(af.params[anchored.tauIndex])).p
                let pYes = (1 - config.slipRate) * pi + arp.f * (1 - pi)
                for _ in 0..<Int(w.pre.yesItems) { items.append((1, pYes)) }
                for _ in 0..<Int(w.pre.noItems) { items.append((0, pYes)) }
            }
            personFit = lz(items)
        }

        return LearnerProfile(
            lexicon: lexicon, config: config, asOf: evidence.asOf, theta: fit.params[0],
            weights: Array(fit.params[1...features.width]), wordSD: tau,
            pseudowordFalseAlarmRate: rp.f0, falseAlarmRate: rp.f, verifyGuessRate: rp.r,
            personFit: personFit, sessionWeights: evidence.sessionWeights,
            probabilities: p, standardErrors: se, vocabulary: vocabulary, counts: evidence.counts)
    }

    /// Standardized log-likelihood person-fit statistic lz (Drasgow, Levine and Williams 1985):
    /// about N(0, 1) when answers follow the model; strongly negative (below about −2) for aberrant
    /// patterns such as random answering.
    static func lz(_ items: [(y: Double, p: Double)]) -> Double? {
        var l0 = 0.0, e = 0.0, v = 0.0
        for (y, p0) in items {
            let p = min(max(p0, 1e-9), 1 - 1e-9)
            let lp = log(p), lq = log(1 - p)
            l0 += y * lp + (1 - y) * lq
            e += p * lp + (1 - p) * lq
            v += p * (1 - p) * (lp - lq) * (lp - lq)
        }
        return v > 0 ? (l0 - e) / sqrt(v) : nil
    }

    static func isEvidence(_ s: ObservationSource) -> Bool {
        s == .test || s == .spotcheck || s == .verify
    }
}

// MARK: evidence

/// Weighted answer counts about one word.
struct WordCounts {
    var yes = 0.0, no = 0.0, correct = 0.0, wrong = 0.0
    /// Unweighted Yes/No answers (person fit).
    var yesItems = 0.0, noItems = 0.0

    mutating func add(_ o: WordCounts) {
        yes += o.yes; no += o.no; correct += o.correct; wrong += o.wrong
        yesItems += o.yesItems; noItems += o.noItems
    }
}

struct WordEvidence {
    var word: Int
    /// Answers before the word was meaning-checked in an earlier session: fit the curve.
    var pre = WordCounts()
    /// All answers: the word's posterior.
    var all = WordCounts()
}

/// The Observations reduced to what the model needs.
struct Evidence {
    var words: [WordEvidence] = []
    var pseudoYes = 0.0, pseudoNo = 0.0
    var counts = ObservationCounts()
    var asOf = ""
    var sessionWeights: [String: Double] = [:]

    static func collect(_ observations: [Observation], lexicon: Lexicon, config: ProfileConfig) -> Evidence {
        var ev = Evidence()
        var timed: [(t: Double, i: Int)] = []
        timed.reserveCapacity(observations.count)
        for (i, o) in observations.enumerated() {
            if let t = Timestamp.epochSeconds(o.ts) { timed.append((t, i)) } else { ev.counts.invalid += 1 }
        }
        timed.sort { $0.t != $1.t ? $0.t < $1.t : $0.i < $1.i }
        let latest = timed.last?.t ?? 0
        let asOfSeconds = config.asOf.flatMap(Timestamp.epochSeconds) ?? latest
        ev.asOf = config.asOf ?? timed.last.map { observations[$0.i].ts } ?? ""

        func sessionID(_ o: Observation) -> String { o.session ?? "day-" + String(o.ts.prefix(10)) }

        // Session quality gate (raw, unweighted rates within the session).
        struct Gate { var pseudo = 0, falseAlarms = 0, checks = 0, failed = 0 }
        var gates: [String: Gate] = [:]
        var lastAnswer: [String: Bool] = [:] // session + lemma → last Yes/No answer
        for (_, i) in timed {
            let o = observations[i]
            let s = sessionID(o)
            if o.pseudo == true {
                guard o.result == ObservationResult.yes || o.result == ObservationResult.no else { continue }
                gates[s, default: Gate()].pseudo += 1
                if o.result == ObservationResult.yes { gates[s, default: Gate()].falseAlarms += 1 }
                continue
            }
            let key = s + "\u{1}" + o.lemma.lowercased()
            switch o.source {
            case .test, .spotcheck:
                if o.result == ObservationResult.yes || o.result == ObservationResult.no {
                    lastAnswer[key] = o.result == ObservationResult.yes
                }
            case .verify where lastAnswer[key] == true:
                gates[s, default: Gate()].checks += 1
                if o.result != ObservationResult.correct { gates[s, default: Gate()].failed += 1 }
            default:
                break
            }
        }
        for (s, g) in gates {
            let falseAlarms = g.pseudo >= config.gateMinPseudowords
                && Double(g.falseAlarms) > config.gateFalseAlarmRate * Double(g.pseudo)
            let failedChecks = g.checks >= config.gateMinChecks
                && Double(g.failed) > config.gateVerifyFailRate * Double(g.checks)
            if falseAlarms || failedChecks { ev.sessionWeights[s] = config.gateWeight }
        }

        var byWord: [Int: WordEvidence] = [:]
        var order: [Int] = []
        var checkedIn: [Int: String] = [:] // word → session of its first meaning check
        for (t, i) in timed {
            let o = observations[i]
            let s = sessionID(o)
            let ageDays = max(0, asOfSeconds - t) / 86400
            let weight = pow(0.5, ageDays / config.halfLifeDays) * (ev.sessionWeights[s] ?? 1)
            if o.pseudo == true {
                ev.counts.pseudowords += 1
                if o.result == ObservationResult.yes {
                    ev.pseudoYes += weight
                    ev.counts.falseAlarms += 1
                } else if o.result == ObservationResult.no {
                    ev.pseudoNo += weight
                }
                continue
            }
            guard isEvidenceSource(o.source) else { continue }
            guard let lemma = lexicon.lemma(for: o.lemma), let wi = lexicon.index(of: lemma) else {
                ev.counts.outOfLexicon += 1
                continue
            }
            var c = WordCounts()
            switch o.source {
            case .test, .spotcheck:
                guard o.result == ObservationResult.yes || o.result == ObservationResult.no else { continue }
                if o.result == ObservationResult.yes {
                    var w = weight
                    if let rt = o.rtMs, rt < config.fastYesMs { w *= config.fastYesWeight }
                    c.yes = w
                    c.yesItems = 1
                } else {
                    c.no = weight
                    c.noItems = 1
                }
            default: // verify
                if o.result == ObservationResult.correct { c.correct = weight } else { c.wrong = weight }
            }
            if byWord[wi] == nil {
                byWord[wi] = WordEvidence(word: wi)
                order.append(wi)
            }
            byWord[wi]!.all.add(c)
            if checkedIn[wi] == nil || checkedIn[wi] == s { byWord[wi]!.pre.add(c) }
            if o.source == .verify, checkedIn[wi] == nil { checkedIn[wi] = s }
            ev.counts.evidence += 1
        }
        ev.words = order.sorted().map { byWord[$0]! }
        return ev
    }

    static func isEvidenceSource(_ s: ObservationSource) -> Bool { ProfileEngine.isEvidence(s) }
}

// MARK: model

/// Response-layer rates at given parameters.
struct ResponseRates {
    var s: Double, sv: Double
    /// Pseudoword false-alarm rate, real-word false-alarm rate, meaning-check guessing rate.
    var f0: Double, f: Double, r: Double

    /// log P(answers | known), log P(answers | unknown).
    @inline(__always)
    func logLikelihoods(_ c: WordCounts) -> (Double, Double) {
        var la = 0.0, lb = 0.0
        if c.yes > 0 { la += c.yes * log(1 - s); lb += c.yes * log(f) }
        if c.no > 0 { la += c.no * log(s); lb += c.no * log(1 - f) }
        if c.correct > 0 { la += c.correct * log(1 - sv); lb += c.correct * log(r) }
        if c.wrong > 0 { la += c.wrong * log(sv); lb += c.wrong * log(1 - r) }
        return (la, lb)
    }

    /// ∂ log P(answers | unknown) / ∂ logit f and / ∂ logit r.
    @inline(__always)
    func dLogB(_ c: WordCounts) -> (f: Double, r: Double) {
        (c.yes * (1 - f) - c.no * f, c.correct * (1 - r) - c.wrong * r)
    }
}

/// π = E_u σ(η − u), u ~ N(0, τ²) (9-point Gauss–Hermite), with q = 1 − π and the derivatives
/// ∂π/∂η and ∂π/∂ln τ.
struct Curve {
    var p = 0.0, q = 0.0, dEta = 0.0, dLogTau = 0.0

    /// Probabilists' Gauss–Hermite nodes (z) and weights for E f(z), z ~ N(0, 1).
    static let nodes: [(z: Double, w: Double)] = {
        let x = [0, 0.7235510187528376, 1.4685532892166679, 2.2665805845318431, 3.1909932017815276]
        let w = [0.7202352156060510, 0.4326515590025558, 0.0884745273943766, 0.0049436242755369, 0.0000396069772633]
        var out: [(Double, Double)] = []
        for i in 0..<5 {
            let z = x[i] * 2.0.squareRoot(), wt = w[i] / Double.pi.squareRoot()
            out.append((z, wt))
            if i > 0 { out.append((-z, wt)) }
        }
        return out
    }()

    @inline(__always)
    init(eta: Double, tau: Double) {
        for (z, w) in Curve.nodes {
            let a = eta + tau * z
            let s = sigmoid(a), t = sigmoid(-a)
            p += w * s
            q += w * t
            let d = w * s * t
            dEta += d
            dLogTau += d * tau * z
        }
    }
}

/// Parameters: [θ, β₁…β_K, ln τ, logit f₀, δ, logit r].
struct Model {
    let features: FeatureMatrix
    let evidence: Evidence
    let config: ProfileConfig
    let dim: Int
    /// Index of ln τ (SD of the per-word deviation u_w).
    let tauIndex: Int
    let priorMean: [Double]
    let priorPrecision: [Double]

    init(features: FeatureMatrix, evidence: Evidence, config c: ProfileConfig, anchored: Bool = false) {
        self.features = features
        self.evidence = evidence
        self.config = c
        dim = features.width + 5
        tauIndex = features.width + 1
        var mean = [c.thetaPriorMean, c.mainSlopePriorMean]
        var sd = [c.thetaPriorSD, c.mainSlopePriorSD]
        for _ in 1..<features.width {
            mean.append(0)
            sd.append(c.featurePriorSD)
        }
        mean.append(log(c.wordSDPrior))
        sd.append(c.wordSDPriorSD)
        var f0 = logit(c.pseudowordFalseAlarmPrior)
        if anchored {
            // The population curve and the response layer are held fixed (f₀ from pseudowords alone,
            // δ and r at their prior means): only θ is fitted.
            for k in 1...(features.width + 1) { sd[k] = 1e-4 }
            f0 = Model.pseudowordOnlyLogit(evidence, mean: f0, sd: c.pseudowordFalseAlarmPriorSD)
        }
        mean += [f0, c.realWordExtraPriorMean, logit(c.verifyGuessPrior)]
        sd += [c.pseudowordFalseAlarmPriorSD, c.realWordExtraPriorSD, c.verifyGuessPriorSD]
        if anchored { for k in (dim - 3)..<dim { sd[k] = 1e-4 } }
        priorMean = mean
        priorPrecision = sd.map { 1 / ($0 * $0) }
    }

    /// MAP of logit f₀ from the pseudoword answers and its prior alone.
    static func pseudowordOnlyLogit(_ e: Evidence, mean: Double, sd: Double) -> Double {
        var lo = -20.0, hi = 20.0
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            let f = sigmoid(mid)
            let g = e.pseudoYes * (1 - f) - e.pseudoNo * f - (mid - mean) / (sd * sd)
            if g > 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    func response(_ x: [Double]) -> ResponseRates {
        let a = x[dim - 3], d = x[dim - 2], r = x[dim - 1]
        return ResponseRates(s: config.slipRate, sv: config.verifySlipRate,
                             f0: sigmoid(a), f: sigmoid(a + d), r: sigmoid(r))
    }

    /// Log posterior and its gradient.
    func evaluate(_ x: [Double], gradient: Bool) -> (Double, [Double]) {
        var lp = 0.0
        var g = [Double](repeating: 0, count: gradient ? dim : 0)
        for k in 0..<dim {
            let z = x[k] - priorMean[k]
            lp -= 0.5 * z * z * priorPrecision[k]
            if gradient { g[k] -= z * priorPrecision[k] }
        }
        let rp = response(x)
        // Pseudowords.
        lp += evidence.pseudoYes * log(rp.f0) + evidence.pseudoNo * log(1 - rp.f0)
        if gradient { g[dim - 3] += evidence.pseudoYes * (1 - rp.f0) - evidence.pseudoNo * rp.f0 }
        // Real words: marginal over the knowledge state.
        let tau = exp(x[tauIndex])
        for word in evidence.words {
            let c = word.pre
            let row = features.row(word.word)
            var eta = x[0]
            var k = 1
            for v in row { eta -= x[k] * v; k += 1 }
            let cv = Curve(eta: eta, tau: tau)
            let (la, lb) = rp.logLikelihoods(c)
            let known = log(cv.p) + la, unknown = log(cv.q) + lb
            let m = max(known, unknown)
            let l = m + log(exp(known - m) + exp(unknown - m))
            lp += l
            guard gradient else { continue }
            let post = exp(known - l)
            // ∂ℓ/∂π = post/π − (1 − post)/(1 − π)
            let dPi = post / max(cv.p, 1e-300) - (1 - post) / max(cv.q, 1e-300)
            let dEta = dPi * cv.dEta
            g[0] += dEta
            k = 1
            for v in row { g[k] -= dEta * v; k += 1 }
            g[tauIndex] += dPi * cv.dLogTau
            let dB = rp.dLogB(c)
            g[dim - 3] += (1 - post) * dB.f
            g[dim - 2] += (1 - post) * dB.f
            g[dim - 1] += (1 - post) * dB.r
        }
        return (lp, g)
    }

    struct Fit { var params: [Double]; var covariance: [Double] }

    /// MAP by damped Newton (Levenberg–Marquardt on the analytic gradient and a finite-difference
    /// Hessian); covariance = inverse of the negative Hessian at the mode.
    func fit() -> Fit {
        var x = priorMean
        var (current, g) = evaluate(x, gradient: true)
        var lambda = 1e-3
        for _ in 0..<100 {
            let h = hessian(x)
            var improved = false
            for _ in 0..<30 {
                var a = h.map { -$0 }
                for k in 0..<dim { a[k * dim + k] += lambda * max(1, abs(a[k * dim + k])) }
                guard let step = solve(a, g, dim) else { lambda *= 10; continue }
                let cand = zip(x, step).map { $0 + $1 }
                let (v, cg) = evaluate(cand, gradient: true)
                if v.isFinite && v >= current {
                    let gain = v - current
                    x = cand
                    current = v
                    g = cg
                    lambda = max(1e-9, lambda / 10)
                    improved = gain > 1e-10 || step.allSatisfy { abs($0) < 1e-8 }
                    break
                }
                lambda *= 10
            }
            if !improved || g.allSatisfy({ abs($0) < 1e-7 }) { break }
        }
        let h = hessian(x)
        let cov = invert(h.map { -$0 }, dim) ?? [Double](repeating: 0, count: dim * dim)
        return Fit(params: x, covariance: cov)
    }

    func hessian(_ x: [Double]) -> [Double] {
        var h = [Double](repeating: 0, count: dim * dim)
        let eps = 1e-5
        for j in 0..<dim {
            var xp = x, xm = x
            xp[j] += eps
            xm[j] -= eps
            let gp = evaluate(xp, gradient: true).1, gm = evaluate(xm, gradient: true).1
            for i in 0..<dim { h[i * dim + j] = (gp[i] - gm[i]) / (2 * eps) }
        }
        for i in 0..<dim {
            for j in (i + 1)..<dim where j < dim {
                let m = (h[i * dim + j] + h[j * dim + i]) / 2
                h[i * dim + j] = m
                h[j * dim + i] = m
            }
        }
        return h
    }
}

// MARK: helpers

/// vᵀ·C·v for v = values[base..<base+dim].
@inline(__always)
func quadratic(_ c: [Double], _ v: [Double], _ base: Int, _ dim: Int) -> Double {
    var s = 0.0
    for i in 0..<dim {
        let vi = v[base + i]
        if vi == 0 { continue }
        var row = 0.0
        for j in 0..<dim { row += c[i * dim + j] * v[base + j] }
        s += vi * row
    }
    return s
}

/// Solves A·x = b (row-major n×n) by Gaussian elimination with partial pivoting.
func solve(_ a0: [Double], _ b0: [Double], _ n: Int) -> [Double]? {
    var a = a0, b = b0
    for col in 0..<n {
        var piv = col
        for r in (col + 1)..<max(col + 1, n) where abs(a[r * n + col]) > abs(a[piv * n + col]) { piv = r }
        guard abs(a[piv * n + col]) > 1e-14 else { return nil }
        if piv != col {
            for k in 0..<n { a.swapAt(col * n + k, piv * n + k) }
            b.swapAt(col, piv)
        }
        for r in (col + 1)..<max(col + 1, n) {
            let f = a[r * n + col] / a[col * n + col]
            if f == 0 { continue }
            for k in col..<n { a[r * n + k] -= f * a[col * n + k] }
            b[r] -= f * b[col]
        }
    }
    var x = [Double](repeating: 0, count: n)
    for r in stride(from: n - 1, through: 0, by: -1) {
        var s = b[r]
        for k in (r + 1)..<max(r + 1, n) { s -= a[r * n + k] * x[k] }
        x[r] = s / a[r * n + r]
    }
    return x.allSatisfy(\.isFinite) ? x : nil
}

/// Inverse of a row-major n×n matrix, column by column.
func invert(_ a: [Double], _ n: Int) -> [Double]? {
    var out = [Double](repeating: 0, count: n * n)
    for j in 0..<n {
        var e = [Double](repeating: 0, count: n)
        e[j] = 1
        guard let col = solve(a, e, n) else { return nil }
        for i in 0..<n { out[i * n + j] = col[i] }
    }
    return out
}

/// Index of the best-known member lemma of each family (P(family) = max over members), in
/// order of first appearance.
func familyBestIndices(_ p: [Double], lexicon: Lexicon) -> [Int] {
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

func sigmoid(_ z: Double) -> Double {
    z >= 0 ? 1 / (1 + exp(-z)) : exp(z) / (1 + exp(z))
}

func softplus(_ z: Double) -> Double {
    z > 0 ? z + log1p(exp(-z)) : log1p(exp(z))
}

func logit(_ p: Double) -> Double { log(p / (1 - p)) }

/// Bookkeeping about the input Observations (not published: it would reveal study volume).
public struct ObservationCounts: Sendable, Equatable {
    /// Vocabulary evidence that entered the model.
    public var evidence = 0
    public var pseudowords = 0
    /// Evidence about words not in the lexicon (ignored).
    public var outOfLexicon = 0
    /// Pseudowords answered "yes".
    public var falseAlarms = 0
    /// Unparsable timestamps (ignored).
    public var invalid = 0
}
