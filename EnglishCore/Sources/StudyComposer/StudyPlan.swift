/// A Study Plan file, `plan/YYYY-MM-DD.json` in `english-data` (see GLOSSARY.md and ticket 08).
/// The only source of new Cards.
public struct StudyPlan: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: String
    /// Suggested new cards per day; the session takes min(this, the daily limit setting).
    public var dailyNew: Int
    /// Ordered; new cards are taken from the front, skipping words that already have a card or are Mastered.
    public var newWords: [PlannedWord]
    /// ≤ 50 words to focus on (copied into `recent.json` by Actions).
    public var focusTargets: [String]
    /// 1–3 sentences of Chinese, shown on the 学习 tab.
    public var summary: String
    public var instruction: String

    public init(schemaVersion: Int, generatedAt: String, dailyNew: Int, newWords: [PlannedWord],
                focusTargets: [String], summary: String, instruction: String) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.dailyNew = dailyNew
        self.newWords = newWords
        self.focusTargets = focusTargets
        self.summary = summary
        self.instruction = instruction
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case dailyNew = "daily_new"
        case newWords = "new_words"
        case focusTargets = "focus_targets"
        case summary, instruction
    }

    /// The note Word Planning wrote for `lemma`, if any (empty notes count as none).
    public func note(for lemma: String) -> String? {
        newWords.first { $0.lemma == lemma }.map(\.note).flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct PlannedWord: Codable, Sendable, Equatable {
    public var lemma: String
    /// Why this word, in Chinese, ≤ 40 characters.
    public var note: String

    public init(lemma: String, note: String) {
        self.lemma = lemma
        self.note = note
    }
}
