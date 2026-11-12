import CoreModels
import Foundation
import StudyComposer
import Testing

/// The 学习 tab's plan warnings: stale (> 3 days old), running low (< 2 days of new words left),
/// used up (only reviews), no plan yet.
@Suite struct PlanStatusTests {
    let composer = StudyComposer()

    func status(_ obs: [Observation] = [], plan: StudyPlan?, limit: Int = 10, mastered: Set<String> = [],
                now: Date) -> PlanStatus {
        composer.compose(observations: obs, plan: plan, dailyNewLimit: limit, isMastered: { mastered.contains($0) },
                         now: now, calendar: utc).planStatus
    }

    func plan(_ n: Int, dailyNew: Int, generated: String = "2026-11-10T07:30:00+08:00") -> StudyPlan {
        StudyPlan(schemaVersion: 1, generatedAt: generated, dailyNew: dailyNew,
                  newWords: (1...max(n, 1)).prefix(n).map { PlannedWord(lemma: "w\($0)", note: "") },
                  focusTargets: [], summary: "本期排 \(n) 词", instruction: nil)
    }

    @Test func aFreshPlanWithEnoughWordsShowsNothing() {
        #expect(status(plan: plan(35, dailyNew: 5), now: at(day: 11)) == .current)
    }

    @Test func aPlanOlderThanThreeDaysIsStale() {
        // generated 2026-11-09T23:30Z
        #expect(status(plan: plan(35, dailyNew: 5), now: at(day: 12, hour: 23)) == .current)
        #expect(status(plan: plan(35, dailyNew: 5), now: at(day: 13, hour: 0)) == .stale(days: 3))
        #expect(status(plan: plan(35, dailyNew: 5), now: at(day: 15, hour: 9)) == .stale(days: 5))
    }

    @Test func fewerThanTwoDaysOfNewWordsIsRunningLow() {
        #expect(status(plan: plan(10, dailyNew: 5), now: at(day: 11)) == .current)
        #expect(status(plan: plan(9, dailyNew: 5), now: at(day: 11)) == .runningLow(remaining: 9))
    }

    @Test func aDayIsTheSmallerOfPlanAndLimit() {
        #expect(status(plan: plan(4, dailyNew: 5), limit: 2, now: at(day: 11)) == .current)
        #expect(status(plan: plan(3, dailyNew: 5), limit: 2, now: at(day: 11)) == .runningLow(remaining: 3))
    }

    @Test func wordsWithACardOrMasteredAreNotLeft() {
        let obs = learned("w1", on: 10) + learned("w2", on: 10)
        #expect(status(obs, plan: plan(12, dailyNew: 5), mastered: ["w3"], now: at(day: 11))
                == .runningLow(remaining: 9))
    }

    @Test func aUsedUpPlanLeavesOnlyReviews() {
        let obs = learned("w1", on: 5) + learned("w2", on: 5)
        let p = plan(2, dailyNew: 5)
        #expect(status(obs, plan: p, now: at(day: 11)) == .usedUp)
        let s = composer.compose(observations: obs, plan: p, dailyNewLimit: 10, isMastered: { _ in false },
                                 now: at(day: 20), calendar: utc)
        #expect(s.newCards.isEmpty)
        #expect(s.reviews == ["w1", "w2"])
    }

    @Test func usedUpWinsOverStale() {
        let obs = learned("w1", on: 5)
        #expect(status(obs, plan: plan(1, dailyNew: 5), now: at(day: 25)) == .usedUp)
    }

    @Test func staleWinsOverRunningLow() {
        #expect(status(plan: plan(3, dailyNew: 5), now: at(day: 20)) == .stale(days: 10))
    }

    @Test func noPlanYet() {
        #expect(status(plan: nil, now: at(day: 11)) == .missing)
    }
}

@Suite struct StudyPlanDecodingTests {
    @Test func aWordPlanFileWithNullInstructionDecodes() throws {
        let json = """
        {"schema_version": 1, "generated_at": "2026-11-13T07:30:00+08:00", "daily_new": 2,
         "new_words": [{"lemma": "ambiguous", "note": "想学"}], "focus_targets": ["ambiguous"],
         "summary": "本期排 14 词。", "instruction": null}
        """
        let p = try JSONDecoder().decode(StudyPlan.self, from: Data(json.utf8))
        #expect(p.instruction == nil)
        #expect(p.newWords == [PlannedWord(lemma: "ambiguous", note: "想学")])
    }
}
