import CoreModels
import Lexicon

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// What the legacy engine estimates (kept only for the offline evaluation's comparison).
public struct LegacyProfile: Sendable {
    public var probabilities: [Double]
    /// Guessing rate of Yes/No answers.
    public var falseAlarmRate: Double
    public var slipRate: Double
    public var lemmas: Estimate
    public var families: Estimate
}

/// The Profile Engine before ticket 02, frozen so the offline evaluation can compare against it.
/// Not used by the App or Actions.
///
/// Model: `P(known w) = σ(θ − δ_w + u_w)` with `δ_w = slope · ln(rank_w / referenceRank)`.
/// θ and slope are fitted jointly (MAP, Newton) on the decayed Vocabulary Test evidence (Yes/No
/// answers and meaning checks), i.e. the word difficulty is regressed on log frequency rank rather
/// than hand-calibrated. Each observed word additionally gets its own deviation `u_w ~ N(0, wordSD²)`,
/// so direct evidence about a word moves that word's P beyond what its frequency predicts.
///
/// Correction signals on Yes/No answers: the guessing rate comes from pseudoword false alarms,
/// raised when meaning checks after a "yes" fail more often than expected; implausibly fast "yes"
/// answers count less; a person-fit statistic (lz) flags answer patterns the model can't explain.
///
/// The reference time `asOf` (decay) is `config.asOf`, else the latest
/// Observation, so the same Observations always give the same profile (App and Actions alike).
public enum LegacyProfileEngine {
    public static func compute(
        observations: [Observation], lexicon: Lexicon, config: LegacyProfileConfig = LegacyProfileConfig()
    ) -> LegacyProfile {
        let entries = lexicon.entries
        let n = entries.count
        let lnRef = log(config.referenceRank)
        let x = entries.map { log(Double($0.rank)) - lnRef }

        // 1. Timestamps, ordering, reference time.
        var counts = ObservationCounts()
        var timed: [(t: Double, i: Int)] = []
        timed.reserveCapacity(observations.count)
        for (i, o) in observations.enumerated() {
            if let t = Timestamp.epochSeconds(o.ts) { timed.append((t, i)) } else { counts.invalid += 1 }
        }
        timed.sort { $0.t != $1.t ? $0.t < $1.t : $0.i < $1.i }
        let latest = timed.last?.t ?? 0
        let asOfSeconds = config.asOf.flatMap(Timestamp.epochSeconds) ?? latest
        let asOfString = config.asOf ?? timed.last.map { observations[$0.i].ts } ?? ""

        // 2. Evidence. Yes/No answers are "guessable": the Learner may say yes to a word
        // they don't know, at the false-alarm rate measured on pseudowords.
        struct Evidence { var word: Int; var y: Double; var w: Double; var guessable: Bool }
        var evidence: [Evidence] = []
        var pseudoYes = 0.0, pseudoAll = 0.0
        var lastYesNo: [Int: Bool] = [:]
        var checkedAfterYes = 0.0, failedAfterYes = 0.0
        for (t, i) in timed {
            let o = observations[i]
            let ageDays = max(0, asOfSeconds - t) / 86400
            let decay = pow(0.5, ageDays / config.halfLifeDays)
            if o.pseudo == true {
                counts.pseudowords += 1
                if o.result == ObservationResult.yes || o.result == ObservationResult.no {
                    pseudoAll += decay
                    if o.result == ObservationResult.yes { pseudoYes += decay; counts.falseAlarms += 1 }
                }
                continue
            }
            guard let lemma = lexicon.lemma(for: o.lemma), let wi = lexicon.index(of: lemma) else {
                if ProfileEngine.isEvidence(o.source) { counts.outOfLexicon += 1 }
                continue
            }
            var known: Bool
            var weight: Double
            var guessable = false
            switch o.source {
            case .test, .spotcheck:
                guard o.result == ObservationResult.yes || o.result == ObservationResult.no else { continue }
                known = o.result == ObservationResult.yes
                weight = config.testWeight
                if known, let rt = o.rtMs, rt < config.fastYesMs { weight *= config.fastYesWeight }
                guessable = true
                lastYesNo[wi] = known
            case .verify:
                known = o.result == ObservationResult.correct
                weight = config.verifyWeight
                if lastYesNo[wi] == true {
                    checkedAfterYes += decay
                    if !known { failedAfterYes += decay }
                }
            default:
                continue
            }
            evidence.append(Evidence(word: wi, y: known ? 1 : 0, w: weight * decay, guessable: guessable))
            counts.evidence += 1
        }
        // Posterior mean of the false-alarm rate under a Beta prior, raised by meaning checks that
        // fail after a "yes" more often than the prior expects (over-claiming).
        let a = config.falseAlarmPriorMean * config.falseAlarmPriorStrength
        let pseudoGuess = (pseudoYes + a) / (pseudoAll + config.falseAlarmPriorStrength)
        let overclaim = (failedAfterYes + config.overclaimPriorMean * config.overclaimPriorStrength)
            / (checkedAfterYes + config.overclaimPriorStrength)
        let guess = min(config.maxGuessRate,
                        pseudoGuess + config.overclaimGuessWeight * max(0, overclaim - config.overclaimPriorMean))

        func datum(_ e: Evidence, x: Double) -> Datum {
            Datum(x: x, y: e.y, w: e.w, g: e.guessable ? guess : 0, s: e.guessable ? config.slipRate : 0)
        }

        // 3. Global fit of (θ, slope) on Vocabulary Test evidence only.
        let fit = fitGlobal(evidence.map { datum($0, x: x[$0.word]) }, config: config)

        // 4. Per-word deviation for observed words.
        var byWord: [Int: [Datum]] = [:]
        for e in evidence { byWord[e.word, default: []].append(datum(e, x: 0)) }
        let prior = x.map { fit.theta - fit.slope * $0 }
        var eta = prior
        for wi in byWord.keys.sorted() {
            eta[wi] += fitWordDeviation(prior: eta[wi], evidence: byWord[wi]!, sd: config.wordSD)
        }
        let p = eta.map(sigmoid)

        let lemmas = sumEstimate(p, x, fit.covariance)
        let best = familyBestIndices(p, lexicon: lexicon)
        let families = sumEstimate(best.map { p[$0] }, best.map { x[$0] }, fit.covariance)
        return LegacyProfile(probabilities: p, falseAlarmRate: guess, slipRate: config.slipRate,
                             lemmas: lemmas, families: families)
    }

    /// ΣP with a 95% interval: delta method on (θ, slope) plus the Bernoulli spread.
    static func sumEstimate(_ ps: [Double], _ xs: [Double], _ cov: (Double, Double, Double)) -> Estimate {
        var sum = 0.0, gt = 0.0, gb = 0.0, bern = 0.0
        for (pi, xi) in zip(ps, xs) {
            let d = pi * (1 - pi)
            sum += pi
            gt += d
            gb -= d * xi
            bern += d
        }
        let variance = gt * gt * cov.0 + 2 * gt * gb * cov.1 + gb * gb * cov.2 + bern
        let half = 1.96 * sqrt(max(0, variance))
        return Estimate(estimate: sum, low: max(0, sum - half), high: min(Double(ps.count), sum + half))
    }

    struct GlobalFit { var theta: Double; var slope: Double; var covariance: (Double, Double, Double) }

    /// One weighted answer: `y` (1 known) at log-rank offset `x`, with guessing rate `g`
    /// and slip rate `s`: P(y = 1) = g + (1 − g − s)·σ(η).
    struct Datum { var x: Double; var y: Double; var w: Double; var g: Double; var s: Double = 0 }

    /// Log-likelihood of one datum at logit `eta`, its derivative, and its Fisher information.
    @inline(__always)
    static func term(_ d: Datum, _ eta: Double) -> (l: Double, d1: Double, info: Double) {
        if d.g == 0 && d.s == 0 {
            let pr = sigmoid(eta)
            return (d.w * (d.y * eta - softplus(eta)), d.w * (d.y - pr), d.w * pr * (1 - pr))
        }
        let pr = sigmoid(eta)
        let span = 1 - d.g - d.s
        let q = min(max(d.g + span * pr, 1e-300), 1 - 1e-16)
        let dq = span * pr * (1 - pr)
        let l = d.y * log(q) + (1 - d.y) * log(1 - q)
        return (d.w * l, d.w * (d.y - q) / (q * (1 - q)) * dq, d.w * dq * dq / (q * (1 - q)))
    }

    /// MAP estimate of (θ, slope), η = θ − slope·x, by Fisher scoring with step halving.
    static func fitGlobal(_ data: [Datum], config c: LegacyProfileConfig) -> GlobalFit {
        var th = c.thetaPriorMean, b = c.slopePriorMean
        let vt = c.thetaPriorSD * c.thetaPriorSD, vb = c.slopePriorSD * c.slopePriorSD

        func logPost(_ th: Double, _ b: Double) -> Double {
            var l = -(th - c.thetaPriorMean) * (th - c.thetaPriorMean) / (2 * vt)
                - (b - c.slopePriorMean) * (b - c.slopePriorMean) / (2 * vb)
            for d in data { l += term(d, th - b * d.x).l }
            return l
        }
        /// Gradient and (negative) expected information matrix.
        func derivatives(_ th: Double, _ b: Double) -> (g: (Double, Double), h: (Double, Double, Double)) {
            var gt = -(th - c.thetaPriorMean) / vt, gb = -(b - c.slopePriorMean) / vb
            var htt = -1 / vt, htb = 0.0, hbb = -1 / vb
            for d in data {
                let t = term(d, th - b * d.x)
                gt += t.d1
                gb -= t.d1 * d.x
                htt -= t.info
                htb += t.info * d.x
                hbb -= t.info * d.x * d.x
            }
            return ((gt, gb), (htt, htb, hbb))
        }

        var current = logPost(th, b)
        for _ in 0..<200 {
            let (g, h) = derivatives(th, b)
            let det = h.0 * h.2 - h.1 * h.1
            guard det != 0 else { break }
            let dt = -(h.2 * g.0 - h.1 * g.1) / det
            let db = -(-h.1 * g.0 + h.0 * g.1) / det
            var step = 1.0
            var accepted = false
            for _ in 0..<40 {
                let cand = logPost(th + step * dt, b + step * db)
                if cand >= current { current = cand; accepted = true; break }
                step /= 2
            }
            guard accepted else { break }
            th += step * dt
            b += step * db
            if abs(step * dt) < 1e-10 && abs(step * db) < 1e-10 { break }
        }
        let h = derivatives(th, b).h
        let det = h.0 * h.2 - h.1 * h.1
        // Covariance = (−H)^{-1}
        return GlobalFit(theta: th, slope: b, covariance: (-h.2 / det, h.1 / det, -h.0 / det))
    }

    /// MAP of a word's deviation u given its prior logit and its own evidence.
    static func fitWordDeviation(prior: Double, evidence: [Datum], sd: Double) -> Double {
        // Each likelihood term is non-decreasing (y = 1) or non-increasing (y = 0) in u and
        // the posterior is unimodal in practice, so bisect on the gradient (robust where plain
        // Newton overshoots with heavy weights).
        let v = sd * sd
        func gradient(_ u: Double) -> Double {
            var g = -u / v
            for e in evidence { g += term(e, prior + u).d1 }
            return g
        }
        var lo = -60.0, hi = 60.0
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if gradient(mid) > 0 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}
