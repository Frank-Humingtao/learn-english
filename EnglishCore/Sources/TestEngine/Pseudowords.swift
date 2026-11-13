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
        lexicon.lemma(for: w) == nil && !lexicon.supplementary.contains(w) && !looksDerived(w)
    }

    /// A real word plus a regular ending (`stemful`, `stemness`, `stems`): it reads as a real
    /// derived or inflected form, so a "yes" to it says nothing about over-claiming.
    public func looksDerived(_ w: String) -> Bool {
        for suffix in Self.suffixes where w.count > suffix.count + 2 && w.hasSuffix(suffix) {
            let stem = String(w.dropLast(suffix.count))
            if isKnownForm(stem) || isKnownForm(stem + "e") { return true }
            // Doubled consonant (`stopping`).
            if let last = stem.last, stem.dropLast().last == last, isKnownForm(String(stem.dropLast())) { return true }
            // y → i (`happiness`).
            if stem.hasSuffix("i"), isKnownForm(String(stem.dropLast()) + "y") { return true }
        }
        return false
    }

    static let suffixes = ["s", "es", "ed", "ing", "er", "ers", "est", "ly", "ness", "ful", "less", "ment", "able",
                           "ish", "ist", "ism", "ity", "ise", "ize", "al", "ally", "ion", "y"]

    func isKnownForm(_ w: String) -> Bool { lexicon.lemma(for: w) != nil || lexicon.supplementary.contains(w) }

    /// Orthographic neighbourhood size (Coltheart's N): lexicon words one substitution, insertion
    /// or deletion away.
    public func neighbors(_ word: String) -> Int {
        let w = Array(word.lowercased())
        var found = Set<String>()
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        func check(_ c: [Character]) {
            let s = String(c)
            if s != word && isKnownForm(s) { found.insert(s) }
        }
        for i in w.indices {
            var d = w
            d.remove(at: i)
            check(d)
            for l in letters where l != w[i] {
                var c = w
                c[i] = l
                check(c)
            }
        }
        for i in 0...w.count {
            for l in letters {
                var c = w
                c.insert(l, at: i)
                check(c)
            }
        }
        return found.count
    }

    /// The shape class item analysis groups pseudowords by.
    public func shape(_ w: String) -> PseudowordShape {
        let n = neighbors(w)
        let suffixLike = Self.suffixes.contains { $0.count >= 2 && w.hasSuffix($0) }
        return PseudowordShape(neighbors: min(n, 2), suffixLike: suffixLike)
    }

    /// One pseudoword matched to `template`: length within `lengthTolerance` letters and
    /// orthographic neighbourhood within `neighborTolerance` of the template's; not in `excluding`,
    /// not of a retired shape. Matching is relaxed step by step if nothing fits.
    func matched(to template: String, excluding: Set<String>, retired: Set<PseudowordShape>, lengthTolerance: Int,
                 neighborTolerance: Int = 2, rng: inout SplitMix64) -> String? {
        let t = template.lowercased()
        let tn = neighbors(t)
        for relax in 0..<3 {
            for _ in 0..<40 {
                guard let w = mutate(t, rng: &rng), !excluding.contains(w) else { continue }
                if relax < 2 && abs(w.count - t.count) > lengthTolerance { continue }
                guard isNonword(w) else { continue }
                if relax < 1 && abs(neighbors(w) - tn) > neighborTolerance { continue }
                if !retired.isEmpty && retired.contains(shape(w)) { continue }
                return w
            }
        }
        return nil
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

/// What item analysis groups pseudowords by: orthographic neighbourhood size (0, 1, 2 or more)
/// and whether the word ends like a common suffix.
public struct PseudowordShape: Sendable, Hashable, Codable, CustomStringConvertible {
    public var neighbors: Int
    public var suffixLike: Bool
    public var description: String { "N=\(neighbors == 2 ? "2+" : String(neighbors))\(suffixLike ? " 词缀形" : "")" }
}
