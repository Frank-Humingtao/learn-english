/// One lemma of the reference lexicon.
public struct LexiconEntry: Sendable, Equatable {
    public var lemma: String
    /// 1-based frequency rank among all lemmas (1 = most frequent).
    public var rank: Int
    /// Headword of the BNC/COCA word family this lemma belongs to.
    public var family: String
    /// 1-based rank of the family among all families.
    public var familyRank: Int
    /// BNC/COCA 1000-family level (1 = first 1000 families ... 25).
    public var level: Int
    public var phonetic: String
    public var pos: String
    /// ECDICT exam tags, space separated (e.g. `cet4 cet6 ky`).
    public var tags: String
    /// English definition (ECDICT).
    public var definition: String
    /// Chinese translation (ECDICT).
    public var translation: String
    /// One example sentence (Wiktextract), may be empty.
    public var example: String
    /// Pronunciation audio URL (Wiktextract), may be empty.
    public var audio: String

    public init(lemma: String, rank: Int, family: String, familyRank: Int, level: Int,
                phonetic: String = "", pos: String = "", tags: String = "", definition: String = "",
                translation: String = "", example: String = "", audio: String = "") {
        self.lemma = lemma
        self.rank = rank
        self.family = family
        self.familyRank = familyRank
        self.level = level
        self.phonetic = phonetic
        self.pos = pos
        self.tags = tags
        self.definition = definition
        self.translation = translation
        self.example = example
        self.audio = audio
    }
}

/// The versioned, read-only reference lexicon shared by the App and Actions.
public struct Lexicon: Sendable {
    public let version: String
    /// Entries sorted by `rank`.
    public let entries: [LexiconEntry]
    /// Lower-cased word form -> lemma.
    public let forms: [String: String]
    /// Lower-cased words from the BNC/COCA supplementary lists (proper names,
    /// marginal words, transparent compounds, acronyms). Counted as known for Coverage.
    public let supplementary: Set<String>
    private let index: [String: Int]

    public init(version: String, entries: [LexiconEntry], forms: [String: String] = [:],
                supplementary: Set<String> = []) {
        self.version = version
        self.entries = entries.sorted { $0.rank < $1.rank }
        var idx: [String: Int] = [:]
        for (i, e) in self.entries.enumerated() { idx[e.lemma] = i }
        self.index = idx
        self.forms = forms
        self.supplementary = supplementary
    }

    /// Position of `lemma` in `entries`.
    public func index(of lemma: String) -> Int? { index[lemma] }

    /// The entry for `lemma` exactly (no lemmatization).
    public func entry(lemma: String) -> LexiconEntry? {
        index[lemma].map { entries[$0] }
    }

    /// Lemmatizes `word` (any inflected/derived form, any case) and returns its lemma.
    public func lemma(for word: String) -> String? {
        let w = word.lowercased()
        if index[w] != nil { return w }
        if let l = forms[w], index[l] != nil { return l }
        return nil
    }

    /// Lemmatizing lookup.
    public func lookup(_ word: String) -> LexiconEntry? {
        lemma(for: word).flatMap { entry(lemma: $0) }
    }
}
