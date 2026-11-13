/// One immutable record of the Learner's response to one word (see GLOSSARY.md).
///
/// Stored as one JSON object per line in `observations/<writer>/YYYY-MM.jsonl`.
/// Field names on disk are snake_case; unknown fields are ignored so later
/// tickets can add fields without breaking older readers.
public struct Observation: Codable, Sendable, Equatable {
    /// UTC timestamp, ISO 8601 (`2026-11-12T08:30:00Z`, fractional seconds allowed).
    public var ts: String
    /// The lemma shown. For pseudowords this is the generated nonword.
    public var lemma: String
    public var source: ObservationSource
    /// Source-specific outcome, see `ObservationResult`.
    public var result: String
    public var rtMs: Int?
    public var session: String?
    /// True when `lemma` is a generated pseudoword (Vocabulary Test only).
    public var pseudo: Bool?
    /// Version of the reference lexicon the writer used.
    public var lexicon: String?

    public init(
        ts: String, lemma: String, source: ObservationSource, result: String,
        rtMs: Int? = nil, session: String? = nil, pseudo: Bool? = nil,
        lexicon: String? = nil
    ) {
        self.ts = ts
        self.lemma = lemma
        self.source = source
        self.result = result
        self.rtMs = rtMs
        self.session = session
        self.pseudo = pseudo
        self.lexicon = lexicon
    }

    enum CodingKeys: String, CodingKey {
        case ts, lemma, source, result, session, pseudo, lexicon
        case rtMs = "rt_ms"
    }
}

/// Where an Observation came from. String-backed so unknown sources (including the retired
/// card-study ones, `review` / `setting` / `wish` / `relearn`, in older files) still decode; they are ignored.
public struct ObservationSource: RawRepresentable, Codable, Sendable, Hashable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    /// Yes/No item in a Vocabulary Test. Result: `yes` / `no`.
    public static let test = ObservationSource(rawValue: "test")
    /// Yes/No item probing an already-Mastered word. Result: `yes` / `no`.
    public static let spotcheck = ObservationSource(rawValue: "spotcheck")
    /// Chinese four-choice meaning check. Result: `correct` / `wrong` / `unknown`.
    public static let verify = ObservationSource(rawValue: "verify")
}

/// Canonical `result` strings.
public enum ObservationResult {
    public static let yes = "yes"
    public static let no = "no"
    public static let correct = "correct"
    public static let wrong = "wrong"
    public static let unknown = "unknown"
}
