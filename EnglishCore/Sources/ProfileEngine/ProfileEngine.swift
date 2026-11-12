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
/// θ and slope are fitted jointly (MAP, Newton) on all decayed evidence, i.e. the word
/// difficulty is regressed on log frequency rank rather than hand-calibrated. Each
/// observed word additionally gets its own deviation `u_w ~ N(0, wordSD²)`, so direct
/// evidence about a word moves that word's P beyond what its frequency predicts.
public enum ProfileEngine {
    public static func compute(
        observations: [Observation], lexicon: Lexicon, config: ProfileConfig = ProfileConfig(),
        activeCards: Set<String>? = nil
    ) -> LearnerProfile {
        let entries = lexicon.entries
        let n = entries.count
        let lnRef = log(config.referenceRank)
        let x = entries.map { log(Double($0.rank)) - lnRef }

        // 1. Timestamps, ordering, reference time.
        var stats = ObservationStats(total: observations.count)
        var timed: [(t: Double, i: Int)] = []
        timed.reserveCapacity(observations.count)
        for (i, o) in observations.enumerated() {
            if let t = Timestamp.epochSeconds(o.ts) { timed.append((t, i)) } else { stats.invalid += 1 }
        }
        timed.sort { $0.t != $1.t ? $0.t < $1.t : $0.i < $1.i }
        let latest = timed.last?.t ?? 0
        let asOfSeconds = config.asOf.flatMap(Timestamp.epochSeconds) ?? latest
        let asOfString = config.asOf ?? timed.last.map { observations[$0.i].ts } ?? ""

        // 2. Evidence. Yes/No answers are "guessable": the Learner may say yes to a word
        // they don't know, at the false-alarm rate measured on pseudowords.
        struct Evidence { var word: Int; var y: Double; var w: Double; var guessable: Bool }
        var evidence: [Evidence] = []
        var reviewed: [Int: (first: String, lapses: Int)] = [:]
        var pseudoYes = 0.0, pseudoAll = 0.0
        for (t, i) in timed {
            let o = observations[i]
            let ageDays = max(0, asOfSeconds - t) / 86400
            let decay = pow(0.5, ageDays / config.halfLifeDays)
            if o.pseudo == true {
                stats.pseudo += 1
                if o.result == ObservationResult.yes || o.result == ObservationResult.no {
                    pseudoAll += decay
                    if o.result == ObservationResult.yes { pseudoYes += decay; stats.falseAlarms += 1 }
                }
                continue
            }
            guard let lemma = lexicon.lemma(for: o.lemma), let wi = lexicon.index(of: lemma) else {
                if isEvidence(o.source) { stats.outOfLexicon += 1 }
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
                guessable = true
            case .verify:
                known = o.result == ObservationResult.correct
                weight = config.verifyWeight
            case .review:
                let isFirst = reviewed[wi] == nil
                var card = reviewed[wi] ?? (o.result, 0)
                if o.result == ObservationResult.again { card.lapses += 1 }
                reviewed[wi] = card
                known = o.result != ObservationResult.again
                weight = (isFirst && o.result == ObservationResult.easy) ? config.firstEasyWeight : config.reviewWeight
            default:
                continue
            }
            evidence.append(Evidence(word: wi, y: known ? 1 : 0, w: weight * decay, guessable: guessable))
            stats.used += 1
        }
        // Posterior mean of the false-alarm rate under a Beta prior.
        let a = config.falseAlarmPriorMean * config.falseAlarmPriorStrength
        let guess = (pseudoYes + a) / (pseudoAll + config.falseAlarmPriorStrength)

        // 3. Global fit of (θ, slope).
        let fit = fitGlobal(evidence.map { Datum(x: x[$0.word], y: $0.y, w: $0.w, g: $0.guessable ? guess : 0,
                                                    s: $0.guessable ? config.slipRate : 0) },
                            config: config)

        // 4. Per-word deviation for observed words.
        var byWord: [Int: [Datum]] = [:]
        for e in evidence {
            byWord[e.word, default: []].append(Datum(x: 0, y: e.y, w: e.w, g: e.guessable ? guess : 0,
                                               s: e.guessable ? config.slipRate : 0))
        }
        var eta = x.map { fit.theta - fit.slope * $0 }
        for wi in byWord.keys.sorted() {
            eta[wi] += fitWordDeviation(prior: eta[wi], evidence: byWord[wi]!, sd: config.wordSD)
        }
        let p = eta.map(sigmoid)

        // 5. Active cards.
        let active: Set<String> = activeCards ?? Set(reviewed.compactMap { wi, card in
            card.first == ObservationResult.easy || card.lapses >= config.leechLapses ? nil : entries[wi].lemma
        })

        return LearnerProfile(lexicon: lexicon, config: config, asOf: asOfString, theta: fit.theta,
                              slope: fit.slope, covariance: fit.covariance, falseAlarmRate: guess, x: x, p: p,
                              activeCards: active, stats: stats, count: n)
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

/// Bookkeeping about the input Observations.
public struct ObservationStats: Sendable, Equatable {
    public var total: Int
    /// Vocabulary evidence that entered the model.
    public var used = 0
    public var pseudo = 0
    /// Evidence about words not in the lexicon (ignored).
    public var outOfLexicon = 0
    /// Pseudowords answered "yes".
    public var falseAlarms = 0
    /// Unparsable timestamps (ignored).
    public var invalid = 0
}
