import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import TestEngine

let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

func fixtureLexicon() -> Lexicon {
    try! Lexicon.load(directory: fixtures.appendingPathComponent("lexicon"))
}

/// Synthetic lexicon of real-looking English words: `count` lemmas, one family each.
/// Lemmas are built from syllables so the pseudoword generator has segments to work with.
/// Parts of speech rotate n / v / adj; translations are `<pos>. 义<rank>`.
func syntheticLexicon(count: Int) -> Lexicon {
    let onsets = ["b", "c", "d", "f", "g", "l", "m", "n", "p", "r", "s", "t", "v", "br", "pl", "st", "tr", "gr"]
    let vowels = ["a", "e", "i", "o", "u", "ea", "ou"]
    let codas = ["", "n", "r", "t", "nd", "st", "ck", "m"]
    var seen = Set<String>()
    var entries: [LexiconEntry] = []
    var k = 0
    while entries.count < count {
        // Deterministic enumeration of 2-syllable words.
        let a = k % onsets.count, b = (k / onsets.count) % vowels.count
        let c = (k / (onsets.count * vowels.count)) % onsets.count
        let d = (k / (onsets.count * vowels.count * onsets.count)) % vowels.count
        let e = (k / (onsets.count * vowels.count * onsets.count * vowels.count)) % codas.count
        k += 1
        let w = onsets[a] + vowels[b] + onsets[c] + vowels[d] + codas[e]
        guard seen.insert(w).inserted else { continue }
        let rank = entries.count + 1
        let pos = ["n", "v", "adj"][rank % 3]
        let zhPos = ["n.", "vt.", "a."][rank % 3]
        entries.append(LexiconEntry(lemma: w, rank: rank, family: w, familyRank: rank, level: (rank - 1) / 1000 + 1,
                                    pos: "", translation: "\(zhPos) 义\(rank)"))
        _ = pos
    }
    return Lexicon(version: "syn-1", entries: entries)
}

/// Deterministic SplitMix64 for simulated answers.
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

/// `2026-11-<day>T12:<minute>:<second>Z`.
func stamp(day: Int, second: Int) -> String {
    func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return "2026-11-\(two(day))T\(two(12 + second / 3600)):\(two(second / 60 % 60)):\(two(second % 60))Z"
}

/// A learner who knows exactly the words with rank <= `knownUpTo`, never says yes to pseudowords
/// unless `falseAlarmEvery` > 0, and picks the right meaning for known words.
struct ThresholdLearner {
    var knownUpTo: Int
    var falseAlarmEvery = 0
    var pseudoSeen = 0

    mutating func answer(_ item: TestItem, lexicon: Lexicon) -> TestAnswer {
        switch item {
        case .yesNo(let q):
            if q.kind == .pseudoword {
                pseudoSeen += 1
                return .yesNo(falseAlarmEvery > 0 && pseudoSeen % falseAlarmEvery == 0)
            }
            return .yesNo((lexicon.entry(lemma: q.word)?.rank ?? .max) <= knownUpTo)
        case .meaningCheck(let q):
            let known = (lexicon.entry(lemma: q.lemma)?.rank ?? .max) <= knownUpTo
            return .meaning(known ? q.correctIndex : nil)
        }
    }
}

/// Runs one whole session with `learner`, one answer every 2 seconds on `day`.
func runSession(_ session: inout TestSession, learner: inout ThresholdLearner, lexicon: Lexicon, day: Int) {
    var second = 0
    while let item = session.current {
        second += 2
        session.answer(learner.answer(item, lexicon: lexicon), rtMs: 1500, at: stamp(day: day, second: second))
    }
}
