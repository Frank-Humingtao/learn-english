import Lexicon

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum WordBand: String, Sendable, CaseIterable {
    case mastered = "Mastered"
    case target = "Target"
    case distant = "Distant"
}

/// A point estimate with a 95% interval.
public struct Estimate: Sendable, Equatable {
    public var estimate: Double
    public var low: Double
    public var high: Double
}

public struct VocabularySize: Sendable, Equatable {
    /// ΣP over lemmas.
    public var lemmas: Estimate
    /// Σ over BNC/COCA word families of the family's P (max over its member lemmas).
    /// This is the number reported to the outside (Level 6 word families).
    public var families: Estimate
    public var lemmaCount: Int
    public var familyCount: Int
}

public struct BandCounts: Sendable, Equatable {
    public var mastered = 0
    public var target = 0
    public var distant = 0
}

public struct LevelMastery: Sendable, Equatable {
    /// BNC/COCA 1000-family level.
    public var level: Int
    /// Mean family P within the level.
    public var mastery: Double
    public var families: Int
}

/// The system's current picture of the Learner's vocabulary (see GLOSSARY.md).
public struct LearnerProfile: Sendable {
    public let lexicon: Lexicon
    public let config: ProfileConfig
    /// Reference time of the computation (ISO 8601).
    public let asOf: String
    /// Ability on the logit scale, relative to a word at `config.referenceRank`.
    public let theta: Double
    /// Difficulty per unit of ln(rank).
    public let slope: Double
    public let counts: ObservationCounts
    /// Estimated rate of "yes" to unknown words: pseudoword false alarms (decayed, Beta prior),
    /// raised by meaning checks failed after a "yes".
    public let falseAlarmRate: Double
    /// Person-fit statistic lz of the Yes/No answers (about 0 when consistent with the model; below
    /// about −2 the answers look careless or random). nil with too few answers.
    public let personFit: Double?
    /// P(known) per lexicon entry, in `lexicon.entries` order.
    public let probabilities: [Double]
    /// Word Band per lexicon entry, in `lexicon.entries` order.
    public let bands: [WordBand]
    public let vocabulary: VocabularySize
    public let bandCounts: BandCounts
    public let levelMastery: [LevelMastery]

    init(lexicon: Lexicon, config: ProfileConfig, asOf: String, theta: Double, slope: Double,
         covariance: (Double, Double, Double), falseAlarmRate: Double, personFit: Double?, x: [Double], p: [Double],
         counts: ObservationCounts, count: Int) {
        self.lexicon = lexicon
        self.config = config
        self.asOf = asOf
        self.theta = theta
        self.slope = slope
        self.falseAlarmRate = falseAlarmRate
        self.personFit = personFit
        self.probabilities = p
        self.counts = counts

        let entries = lexicon.entries
        let (ctt, ctb, cbb) = covariance

        // Variance of a sum of P: parameter uncertainty (delta method on θ, slope)
        // plus the Bernoulli spread of which words are actually known.
        func interval(_ ps: [Double], _ xs: [Double]) -> Estimate {
            var sum = 0.0, gt = 0.0, gb = 0.0, bern = 0.0
            for (pi, xi) in zip(ps, xs) {
                let d = pi * (1 - pi)
                sum += pi
                gt += d
                gb -= d * xi
                bern += d
            }
            let variance = gt * gt * ctt + 2 * gt * gb * ctb + gb * gb * cbb + bern
            let half = 1.96 * sqrt(max(0, variance))
            return Estimate(estimate: sum, low: max(0, sum - half), high: min(Double(ps.count), sum + half))
        }
        let lemmaSize = interval(p, x)

        // Families: P(family) = max over member lemmas.
        var familyBest: [String: Int] = [:]
        var familyOrder: [String] = []
        for (i, e) in entries.enumerated() {
            if let j = familyBest[e.family] {
                if p[i] > p[j] { familyBest[e.family] = i }
            } else {
                familyBest[e.family] = i
                familyOrder.append(e.family)
            }
        }
        let best = familyOrder.map { familyBest[$0]! }
        let familySize = interval(best.map { p[$0] }, best.map { x[$0] })
        vocabulary = VocabularySize(lemmas: lemmaSize, families: familySize, lemmaCount: entries.count,
                                    familyCount: familyOrder.count)

        // Word Bands.
        let window = Double(config.targetWindow) + lemmaSize.estimate
        var counts = BandCounts()
        bands = entries.enumerated().map { i, e in
            let band: WordBand
            if p[i] >= config.masteredThreshold {
                band = .mastered
            } else if Double(e.rank) <= window {
                band = .target
            } else {
                band = .distant
            }
            switch band {
            case .mastered: counts.mastered += 1
            case .target: counts.target += 1
            case .distant: counts.distant += 1
            }
            return band
        }
        bandCounts = counts

        // Level mastery.
        var levelSum: [Int: (Double, Int)] = [:]
        for i in best {
            let level = entries[i].level
            let cur = levelSum[level] ?? (0, 0)
            levelSum[level] = (cur.0 + p[i], cur.1 + 1)
        }
        levelMastery = levelSum.keys.sorted().map {
            LevelMastery(level: $0, mastery: levelSum[$0]!.0 / Double(levelSum[$0]!.1), families: levelSum[$0]!.1)
        }
    }

    /// P(known) of a lemma (or any form of it).
    public func probability(of word: String) -> Double? {
        lexicon.lemma(for: word).flatMap(lexicon.index(of:)).map { probabilities[$0] }
    }

    /// P(known) of a word family (by headword): the best-known member lemma.
    public func familyProbability(of headword: String) -> Double? {
        var best: Double?
        for (i, e) in lexicon.entries.enumerated() where e.family == headword {
            best = max(best ?? 0, probabilities[i])
        }
        return best
    }

    /// Word Band of a lemma (or any form of it).
    public func band(of word: String) -> WordBand? {
        lexicon.lemma(for: word).flatMap(lexicon.index(of:)).map { bands[$0] }
    }
}
