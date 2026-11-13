import Lexicon

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A word property that enters the difficulty regression b_w = β·x_w. Each feature gives one or
/// two columns of x_w; columns grow with difficulty where that has a natural direction.
public enum WordFeature: String, Sendable, CaseIterable, Codable {
    /// ln(lemma rank / 1000). The lexicon's lemma rank orders by BNC/COCA family level first, then
    /// by member frequency, so it mixes family and lemma frequency.
    case rank
    /// ln(family rank / 1000): BNC/COCA family-level frequency.
    case familyRank
    /// −ln((freq + 1) / 1000): the lemma's own frequency in the BNC/COCA family lists.
    case freq
    /// ln(rank / 1000) in ECDICT's contemporary-corpus (COCA) list, plus a "not ranked" indicator.
    case coca
    /// The same for ECDICT's BNC rank.
    case bnc
    /// ECDICT exam tags as the earliest exam whose syllabus lists the word
    /// (zk < gk < cet4 < cet6 < ky < toefl/ielts < gre): an "untagged" indicator and the ordinal level.
    case examTags
    /// 1 when the lemma is not its family's headword (a derived member).
    case derived
    /// (letters − 7) / 3.
    case length

    /// The feature set chosen with the offline evaluation (ticket 02).
    public static let defaultSet: [WordFeature] = [.rank, .examTags]

    var columns: Int {
        switch self {
        case .coca, .bnc, .examTags: return 2
        default: return 1
        }
    }

    /// Exams in syllabus order; toefl and ielts share a level.
    static let examLevels: [String: Int] = ["zk": 0, "gk": 1, "cet4": 2, "cet6": 3, "ky": 4, "toefl": 5, "ielts": 5, "gre": 6]

    /// Earliest exam level of `tags`, or nil when untagged.
    static func earliestExam(_ tags: String) -> Int? {
        tags.split(separator: " ").compactMap { examLevels[String($0)] }.min()
    }

    func values(_ e: LexiconEntry) -> [Double] {
        switch self {
        case .rank: return [log(Double(max(1, e.rank)) / 1000)]
        case .familyRank: return [log(Double(max(1, e.familyRank)) / 1000)]
        case .freq: return [-log((Double(max(0, e.freq)) + 1) / 1000)]
        case .coca: return Self.ranked(e.cocaRank)
        case .bnc: return Self.ranked(e.bncRank)
        case .examTags:
            guard let level = Self.earliestExam(e.tags) else { return [1, 0] }
            return [0, (Double(level) - 2) / 2]
        case .derived: return [e.lemma == e.family ? 0 : 1]
        case .length: return [(Double(e.lemma.count) - 7) / 3]
        }
    }

    /// Unranked words get the rank just past ECDICT's lists plus the indicator.
    static func ranked(_ r: Int) -> [Double] {
        r > 0 ? [log(Double(r) / 1000), 0] : [log(60.0), 1]
    }
}

/// The feature matrix of a lexicon: row-major, `width` columns per entry. Every column but the
/// first (the main frequency scale, kept on its natural ln-rank scale so θ is the logit at rank
/// 1000) is centered on its lexicon mean, so θ keeps that meaning whatever features are added.
struct FeatureMatrix {
    let width: Int
    let values: [Double]

    init(lexicon: Lexicon, features: [WordFeature]) {
        let feats = features.isEmpty ? [WordFeature.rank] : features
        width = feats.reduce(0) { $0 + $1.columns }
        var v = [Double]()
        v.reserveCapacity(lexicon.entries.count * width)
        for e in lexicon.entries {
            for f in feats { v += f.values(e) }
        }
        let n = Double(max(1, lexicon.entries.count))
        for c in 1..<max(1, width) {
            var mean = 0.0
            for i in 0..<lexicon.entries.count { mean += v[i * width + c] }
            mean /= n
            for i in 0..<lexicon.entries.count { v[i * width + c] -= mean }
        }
        values = v
    }

    @inline(__always)
    func row(_ i: Int) -> ArraySlice<Double> { values[(i * width)..<((i + 1) * width)] }
}
