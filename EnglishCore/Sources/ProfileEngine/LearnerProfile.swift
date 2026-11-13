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

/// Totals over one part of the lexicon.
public struct VocabularyPart: Sendable, Equatable {
    public var lemmas: Estimate
    public var families: Estimate
}

public struct VocabularySize: Sendable, Equatable {
    /// ΣP over lemmas.
    public var lemmas: Estimate
    /// Σ over BNC/COCA word families of the family's P (max over its member lemmas).
    /// This is the number reported to the outside (Level 6 word families).
    public var families: Estimate
    public var lemmaCount: Int
    public var familyCount: Int
    /// The same totals for BNC/COCA levels ≤ `ProfileConfig.coreLevels` (14k families: what matters
    /// for Coverage) and above (the long tail, where most of the uncertainty is).
    public var core: VocabularyPart
    public var tail: VocabularyPart
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
    /// Ability: logit P(known) of a word at rank 1000 with average other features.
    public let theta: Double
    /// Difficulty weights of `config.features` (one per feature column).
    public let weights: [Double]
    /// Fitted SD τ of the per-word deviation u_w.
    public let wordSD: Double
    public let counts: ObservationCounts
    /// Response layer: P("yes" | pseudoword) …
    public let pseudowordFalseAlarmRate: Double
    /// … P("yes" | real word not known) (never counted as knowing) …
    public let falseAlarmRate: Double
    /// … and P(meaning check right | word not known).
    public let verifyGuessRate: Double
    /// Person-fit statistic lz of the Yes/No answers (about 0 when consistent with the model; below
    /// about −2 the answers look careless or random). nil with too few answers.
    public let personFit: Double?
    /// Sessions the quality gate down-weighted, with their weight.
    public let sessionWeights: [String: Double]
    /// P(known) per lexicon entry, in `lexicon.entries` order: the knowledge layer only (the
    /// posterior for words with answers), no guessing.
    public let probabilities: [Double]
    /// Standard error of each P from the uncertainty of the fitted parameters.
    public let standardErrors: [Double]
    /// Word Band per lexicon entry, in `lexicon.entries` order.
    public let bands: [WordBand]
    public let vocabulary: VocabularySize
    public let bandCounts: BandCounts
    /// Mean family P per BNC/COCA 1000-family level (frequency-band mastery).
    public let levelMastery: [LevelMastery]

    init(lexicon: Lexicon, config: ProfileConfig, asOf: String, theta: Double, weights: [Double], wordSD: Double,
         pseudowordFalseAlarmRate: Double, falseAlarmRate: Double, verifyGuessRate: Double, personFit: Double?,
         sessionWeights: [String: Double], probabilities p: [Double], standardErrors: [Double],
         vocabulary: VocabularySize, counts: ObservationCounts) {
        self.lexicon = lexicon
        self.config = config
        self.asOf = asOf
        self.theta = theta
        self.weights = weights
        self.wordSD = wordSD
        self.pseudowordFalseAlarmRate = pseudowordFalseAlarmRate
        self.falseAlarmRate = falseAlarmRate
        self.verifyGuessRate = verifyGuessRate
        self.personFit = personFit
        self.sessionWeights = sessionWeights
        self.probabilities = p
        self.standardErrors = standardErrors
        self.vocabulary = vocabulary
        self.counts = counts

        let entries = lexicon.entries
        let best = familyBestIndices(p, lexicon: lexicon)

        // Word Bands.
        let window = Double(config.targetWindow) + vocabulary.lemmas.estimate
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
