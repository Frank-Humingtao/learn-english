import CoreModels
import Lexicon

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Recomputes the Learner Profile from all Observations. Pure: no IO, no clock.
///
/// Model: `P(known w) = σ(θ − δ_w + u_w)` with `δ_w = slope · ln(rank_w / referenceRank)`.
/// θ and slope are fitted jointly (MAP, Newton) on the decayed Vocabulary Test evidence (Yes/No
/// answers and meaning checks), i.e. the word difficulty is regressed on log frequency rank rather
/// than hand-calibrated. Each observed word additionally gets its own deviation `u_w ~ N(0, wordSD²)`,
/// so direct evidence about a word moves that word's P beyond what its frequency predicts.
///
/// Card reviews only move `u_w` of the reviewed word: they have no guessing term and are selected
/// (only planned words get cards), so letting them into (θ, slope) would inflate the whole curve.
///
/// Correction signals on Yes/No answers: the guessing rate comes from pseudoword false alarms,
/// raised when meaning checks after a "yes" fail more often than expected; implausibly fast "yes"
/// answers count less; a person-fit statistic (lz) flags answer patterns the model can't explain.
///
/// The reference time `asOf` (decay, Leech cooldown) is `config.asOf`, else the latest
/// Observation, so the same Observations always give the same profile (App and Actions alike).
public enum ProfileEngine {
    public static func compute(
        observations: [Observation], lexicon: Lexicon, config: ProfileConfig = ProfileConfig()
    ) -> LearnerProfile {
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
        struct Evidence { var word: Int; var y: Double; var w: Double; var guessable: Bool; var global: Bool }
        var evidence: [Evidence] = []
        var reviewed = Set<Int>()
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
                if isEvidence(o.source) { counts.outOfLexicon += 1 }
                continue
            }
            var known: Bool
            var weight: Double
            var guessable = false
            var global = true
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
            case .review:
                let isFirst = reviewed.insert(wi).inserted
                known = o.result != ObservationResult.again
                weight = (isFirst && o.result == ObservationResult.easy) ? config.firstEasyWeight : config.reviewWeight
                global = false
            default:
                continue
            }
            evidence.append(Evidence(word: wi, y: known ? 1 : 0, w: weight * decay, guessable: guessable, global: global))
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
        let fit = fitGlobal(evidence.filter(\.global).map { datum($0, x: x[$0.word]) }, config: config)

        // 4. Per-word deviation for observed words (all evidence, reviews included).
        var byWord: [Int: [Datum]] = [:]
        for e in evidence { byWord[e.word, default: []].append(datum(e, x: 0)) }
        let prior = x.map { fit.theta - fit.slope * $0 }
        var eta = prior
        for wi in byWord.keys.sorted() {
            eta[wi] += fitWordDeviation(prior: eta[wi], evidence: byWord[wi]!, sd: config.wordSD)
        }
        let p = eta.map(sigmoid)

        // 5. Person fit (lz) of the Yes/No answers to real words. As in IRT, item difficulties are
        // held at the population curve (slope fixed at its prior mean) and only θ is fitted: a fitted
        // slope would bend to any pattern, random answering included, and hide it.
        let guessable = evidence.filter(\.guessable)
        var personFit: Double?
        if guessable.count >= config.personFitMinItems {
            var fixedSlope = config
            fixedSlope.slopePriorSD = 1e-6
            let anchored = fitGlobal(guessable.map { datum($0, x: x[$0.word]) }, config: fixedSlope)
            personFit = lz(guessable.map {
                ($0.y, guess + (1 - guess - config.slipRate) * sigmoid(anchored.theta - anchored.slope * x[$0.word]))
            })
        }

        // 6. Active cards: the shared card replay (first rating, Leech, cooldown, 重新学) at asOf.
        let active = CardReplay(observations: observations, rule: config.leech, asOf: asOfSeconds).activeLemmas

        return LearnerProfile(lexicon: lexicon, config: config, asOf: asOfString, theta: fit.theta,
                              slope: fit.slope, covariance: fit.covariance, falseAlarmRate: guess, personFit: personFit,
                              x: x, p: p, activeCards: active, counts: counts, count: n)
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
        s == .test || s == .spotcheck || s == .verify || s == .review
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
    static func fitGlobal(_ data: [Datum], config c: ProfileConfig) -> GlobalFit {
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

func sigmoid(_ z: Double) -> Double {
    z >= 0 ? 1 / (1 + exp(-z)) : exp(z) / (1 + exp(z))
}

func softplus(_ z: Double) -> Double {
    z > 0 ? z + log1p(exp(-z)) : log1p(exp(z))
}

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
