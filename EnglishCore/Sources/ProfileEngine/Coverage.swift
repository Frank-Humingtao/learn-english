/// Share of a text's running words the Learner already knows.
public struct Coverage: Sendable, Equatable {
    /// Counted tokens (lexicon words plus supplementary words like proper names).
    public var tokens: Int
    /// Expected known share: mean P over counted tokens (supplementary words count as known).
    public var known: Double
    /// Share of counted tokens whose lemma is Mastered (or supplementary).
    public var mastered: Double
    /// Word tokens neither in the lexicon nor in the supplementary lists; not counted.
    public var outOfLexicon: Int
}

extension LearnerProfile {
    /// Tokenizes `text`, lemmatizes each word via the lexicon and returns Coverage.
    /// Numbers and punctuation are skipped. Words from the BNC/COCA supplementary lists
    /// (proper names, marginal words, compounds, acronyms) count as known, as in Nation's
    /// coverage studies. Other unknown-to-lexicon words are excluded and reported.
    public func coverage(of text: String) -> Coverage {
        var tokens = 0, outside = 0
        var knownSum = 0.0, masteredCount = 0
        for raw in Self.words(in: text) {
            var w = raw.lowercased()
            var idx = lexicon.lemma(for: w).flatMap(lexicon.index(of:))
            if idx == nil, w.hasSuffix("'s") {
                w = String(w.dropLast(2))
                idx = lexicon.lemma(for: w).flatMap(lexicon.index(of:))
            }
            if let i = idx {
                tokens += 1
                knownSum += probabilities[i]
                if bands[i] == .mastered { masteredCount += 1 }
            } else if lexicon.supplementary.contains(w) {
                tokens += 1
                knownSum += 1
                masteredCount += 1
            } else {
                outside += 1
            }
        }
        let n = Double(max(tokens, 1))
        return Coverage(tokens: tokens, known: tokens == 0 ? 0 : knownSum / n,
                        mastered: tokens == 0 ? 0 : Double(masteredCount) / n, outOfLexicon: outside)
    }

    /// Runs of ASCII letters, allowing inner apostrophes (don't, cat's). Hyphens split.
    static func words(in text: String) -> [String] {
        var out: [String] = []
        var cur: [UInt8] = []
        func flush() {
            while cur.last == 39 { cur.removeLast() }
            while cur.first == 39 { cur.removeFirst() }
            if !cur.isEmpty { out.append(String(decoding: cur, as: UTF8.self)) }
            cur.removeAll()
        }
        for scalar in text.unicodeScalars {
            var v = scalar.value
            if v == 0x2019 { v = 39 } // typographic apostrophe
            if (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || (v == 39 && !cur.isEmpty) {
                cur.append(UInt8(v))
            } else {
                flush()
            }
        }
        flush()
        return out
    }
}
