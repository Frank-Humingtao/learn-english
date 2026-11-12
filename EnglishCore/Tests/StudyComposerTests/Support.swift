import CoreModels
import Foundation
import Lexicon
import StudyComposer

/// UTC calendar so "today" is the same on every machine.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-11-<day> <hour>:<minute> UTC.
func at(day: Int, hour: Int = 9, minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

func iso(_ d: Date) -> String { Timestamp.iso(d.timeIntervalSince1970) }

/// A bare review Observation (only what the card ledger replays: lemma, time, rating).
func review(_ lemma: String, _ grade: Grade, _ date: Date) -> Observation {
    Observation(ts: iso(date), lemma: lemma, source: .review, result: grade.result)
}

func relearn(_ lemma: String, _ date: Date) -> Observation {
    Observation(ts: iso(date), lemma: lemma, source: .relearn, result: ObservationResult.reset)
}

func plan(_ lemmas: [String], dailyNew: Int) -> StudyPlan {
    StudyPlan(schemaVersion: 1, generatedAt: "2026-11-01T07:30:00Z", dailyNew: dailyNew,
              newWords: lemmas.map { PlannedWord(lemma: $0, note: "") }, focusTargets: [],
              summary: "", instruction: "")
}

/// A new card rated `good` through both learning steps (1m, 10m) on `day`, so it graduates
/// to review and is due again a few days later.
func learned(_ lemma: String, on day: Int) -> [Observation] {
    [review(lemma, .good, at(day: day, hour: 8)),
     review(lemma, .good, at(day: day, hour: 8, minute: 15))]
}
