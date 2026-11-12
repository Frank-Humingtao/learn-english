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
    /// Review-only scheduling fields, aligned with Anki's revlog.
    public var review: ReviewLog?

    public init(
        ts: String, lemma: String, source: ObservationSource, result: String,
        rtMs: Int? = nil, session: String? = nil, pseudo: Bool? = nil,
        lexicon: String? = nil, review: ReviewLog? = nil
    ) {
        self.ts = ts
        self.lemma = lemma
        self.source = source
        self.result = result
        self.rtMs = rtMs
        self.session = session
        self.pseudo = pseudo
        self.lexicon = lexicon
        self.review = review
    }

    enum CodingKeys: String, CodingKey {
        case ts, lemma, source, result, session, pseudo, lexicon, review
        case rtMs = "rt_ms"
    }
}

/// Where an Observation came from. String-backed so unknown future sources decode.
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
    /// Card review. Result: `again` / `hard` / `good` / `easy`.
    public static let review = ObservationSource(rawValue: "review")
    /// Setting change (e.g. daily new-card limit). Not vocabulary evidence.
    public static let setting = ObservationSource(rawValue: "setting")
    /// "I want to learn this word". Not vocabulary evidence.
    public static let wish = ObservationSource(rawValue: "wish")
}

/// Canonical `result` strings.
public enum ObservationResult {
    public static let yes = "yes"
    public static let no = "no"
    public static let correct = "correct"
    public static let wrong = "wrong"
    public static let unknown = "unknown"
    public static let again = "again"
    public static let hard = "hard"
    public static let good = "good"
    public static let easy = "easy"
}

/// Review fields aligned with Anki's revlog table, plus FSRS memory state.
public struct ReviewLog: Codable, Sendable, Equatable {
    /// 1 again, 2 hard, 3 good, 4 easy.
    public var ease: Int
    /// New interval in days.
    public var ivl: Int?
    public var lastIvl: Int?
    /// 0 learn, 1 review, 2 relearn, 3 filtered, 4 manual.
    public var type: Int?
    /// Answer time in milliseconds.
    public var time: Int?
    public var stability: Double?
    public var difficulty: Double?
    public var due: String?

    public init(ease: Int, ivl: Int? = nil, lastIvl: Int? = nil, type: Int? = nil, time: Int? = nil,
                stability: Double? = nil, difficulty: Double? = nil, due: String? = nil) {
        self.ease = ease
        self.ivl = ivl
        self.lastIvl = lastIvl
        self.type = type
        self.time = time
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
    }

    enum CodingKeys: String, CodingKey {
        case ease, ivl, type, time, stability, difficulty, due
        case lastIvl = "last_ivl"
    }
}
