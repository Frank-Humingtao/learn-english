import Lexicon

/// Wuggy-style pseudoword generation: take a real template word, split it into alternating
/// consonant / vowel letter clusters, and swap one or two clusters for others of the same kind
/// that occur in the same position (initial / medial / final) in real words, keeping every
/// adjacent cluster pair attested in the lexicon. The result looks English but is not a word
/// of the lexicon (any form) or its supplementary lists.
public struct Pseudowords: Sendable {
    let lexicon: Lexicon
    /// Clusters by (isVowel, position) with at least `minCount` occurrences, most frequent first.
    private let inventory: [Key: [String]]
    private let pairs: Set<String>

    struct Key: Hashable { var vowel: Bool; var position: Position }
    enum Position: Hashable { case initial, medial, final }

    static let minCount = 3

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
        var counts: [Key: [String: Int]] = [:]
        var pairs = Set<String>()
        for e in lexicon.entries {
            let segs = Self.segments(e.lemma)
            guard segs.count >= 2 else { continue }
            for (i, s) in segs.enumerated() {
                let key = Key(vowel: Self.isVowelCluster(s), position: Self.position(i, segs.count))
                counts[key, default: [:]][s, default: 0] += 1
                if i > 0 { pairs.insert(segs[i - 1] + "|" + s) }
            }
        }
        var inventory: [Key: [String]] = [:]
        for (k, c) in counts {
            inventory[k] = c.filter { $0.value >= Self.minCount }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        }
        self.inventory = inventory
        self.pairs = pairs
    }

    /// `count` distinct pseudowords, none in `excluding`. Templates are cycled; when they run out of
    /// usable ones, random lexicon words are used.
    func generate(count: Int, templates: [String], excluding: Set<String>, rng: inout SplitMix64) -> [String] {
        var out: [String] = []
        var seen = excluding
        var attempts = 0
        let entries = lexicon.entries
        while out.count < count && attempts < count * 200 {
            let template = attempts < templates.count * 20 && !templates.isEmpty
                ? templates[attempts % templates.count]
                : entries[Int.random(in: 0..<max(1, entries.count), using: &rng)].lemma
            attempts += 1
            guard let w = mutate(template, rng: &rng), !seen.contains(w), isNonword(w) else { continue }
            seen.insert(w)
            out.append(w)
        }
        return out
    }

    /// Public entry point for callers that manage their own randomness (seeded).
    public func generate(count: Int, templates: [String], excluding: Set<String> = [], seed: UInt64) -> [String] {
        var rng = SplitMix64(seed: seed)
        return generate(count: count, templates: templates, excluding: excluding, rng: &rng)
    }

    func isNonword(_ w: String) -> Bool {
        lexicon.lemma(for: w) == nil && !lexicon.supplementary.contains(w)
    }

    func mutate(_ template: String, rng: inout SplitMix64) -> String? {
        var segs = Self.segments(template.lowercased())
        guard segs.count >= 2, segs.joined().count >= 4 else { return nil }
        let replacements = segs.count <= 3 ? 1 : 2
        var positions = Array(segs.indices)
        positions.shuffle(using: &rng)
        var changed = 0
        for i in positions where changed < replacements {
            let key = Key(vowel: Self.isVowelCluster(segs[i]), position: Self.position(i, segs.count))
            let options = (inventory[key] ?? []).filter { s in
                s != segs[i]
                    && (i == 0 || pairs.contains(segs[i - 1] + "|" + s))
                    && (i == segs.count - 1 || pairs.contains(s + "|" + segs[i + 1]))
            }
            guard !options.isEmpty else { continue }
            segs[i] = options[Int.random(in: 0..<options.count, using: &rng)]
            changed += 1
        }
        guard changed > 0 else { return nil }
        let w = segs.joined()
        guard (4...12).contains(w.count) else { return nil }
        return w
    }

    static func position(_ i: Int, _ n: Int) -> Position {
        i == 0 ? .initial : i == n - 1 ? .final : .medial
    }

    static func isVowelCluster(_ s: String) -> Bool {
        s.first.map { "aeiouy".contains($0) } ?? false
    }

    /// Maximal runs of vowels / consonants, or [] if the word is not plain lowercase a–z.
    /// `y` is a consonant at the start of a word or after a vowel, otherwise a vowel.
    static func segments(_ word: String) -> [String] {
        var segs: [String] = []
        var cur = ""
        var curVowel = false
        var prevVowel = false
        for (i, ch) in word.enumerated() {
            guard ch >= "a" && ch <= "z" else { return [] }
            let vowel = "aeiou".contains(ch) || (ch == "y" && i > 0 && !prevVowel)
            if cur.isEmpty || vowel == curVowel {
                cur.append(ch)
            } else {
                segs.append(cur)
                cur = String(ch)
            }
            curVowel = vowel
            prevVowel = vowel
        }
        if !cur.isEmpty { segs.append(cur) }
        return segs
    }
}
