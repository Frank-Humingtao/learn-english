import CoreModels
import Lexicon
import ProfileEngine

/// A synthetic lexicon: `count` lemmas named `w00001`..., one family each,
/// 1000 families per level. Optional extra derived members join a family.
func syntheticLexicon(count: Int, derived: [(member: String, family: String)] = []) -> Lexicon {
    var entries: [LexiconEntry] = []
    var familyRankOf: [String: Int] = [:]
    for i in 1...count {
        let name = word(i)
        familyRankOf[name] = i
        entries.append(LexiconEntry(lemma: name, rank: i, family: name, familyRank: i, level: (i - 1) / 1000 + 1))
    }
    // Derived members get ranks after all headwords so headword ranks stay 1...count.
    for (k, d) in derived.enumerated() {
        let fr = familyRankOf[d.family]!
        entries.append(LexiconEntry(lemma: d.member, rank: count + k + 1, family: d.family, familyRank: fr,
                                    level: (fr - 1) / 1000 + 1))
    }
    return Lexicon(version: "test-1", entries: entries)
}

func word(_ i: Int) -> String {
    let s = String(i)
    return "w" + String(repeating: "0", count: max(0, 5 - s.count)) + s
}

/// Day `d` (0-based) of November 2026, at noon UTC, plus `minute` minutes.
func ts(day d: Int, minute: Int = 0) -> String {
    let dayOfMonth = d + 1
    precondition(dayOfMonth <= 30)
    let dd = dayOfMonth < 10 ? "0\(dayOfMonth)" : "\(dayOfMonth)"
    let h = 12 + minute / 60, m = minute % 60
    let mm = m < 10 ? "0\(m)" : "\(m)"
    return "2026-11-\(dd)T\(h):\(mm):00Z"
}

func obs(_ lemma: String, _ source: ObservationSource, _ result: String, day: Int = 0, minute: Int = 0) -> Observation {
    Observation(ts: ts(day: day, minute: minute), lemma: lemma, source: source, result: result, session: "s\(day)")
}

/// Deterministic SplitMix64.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
