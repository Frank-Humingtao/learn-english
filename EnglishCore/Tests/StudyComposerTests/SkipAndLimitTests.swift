import CoreModels
import Foundation
import StudyComposer
import Testing

@Suite struct SkipAndLimitTests {
    let composer = StudyComposer()

    func compose(_ obs: [Observation], plan: StudyPlan?, limit: Int = 20, mastered: Set<String> = [],
                 known: @escaping (String) -> Bool = { _ in true }, now: Date) -> StudySession {
        composer.compose(observations: obs, plan: plan, dailyNewLimit: limit, isMastered: { mastered.contains($0) },
                         isKnownLemma: known, now: now, calendar: utc)
    }

    @Test func newCardCountIsTheSmallerOfPlanAndLimit() {
        let words = (1...10).map { "w\($0)" }
        #expect(compose([], plan: plan(words, dailyNew: 3), limit: 5, now: at(day: 1)).newCards == ["w1", "w2", "w3"])
        #expect(compose([], plan: plan(words, dailyNew: 8), limit: 2, now: at(day: 1)).newCards == ["w1", "w2"])
    }

    @Test func cardsStartedEarlierTodayUseUpTheLimit() {
        let obs = [review("w1", .good, at(day: 1, hour: 7)), review("w2", .again, at(day: 1, hour: 7))]
        let p = plan(["w1", "w2", "w3", "w4", "w5"], dailyNew: 3)
        #expect(compose(obs, plan: p, now: at(day: 1, hour: 20)).newCards == ["w3"])
        // Yesterday's cards don't count today.
        #expect(compose(obs, plan: p, now: at(day: 2, hour: 20)).newCards == ["w3", "w4", "w5"])
    }

    @Test func planWordsWithACardMasteredTooEasyOrNotInTheLexiconAreSkipped() {
        let obs = [review("tooeasy", .easy, at(day: 1))] + learned("hascard", on: 1)
        let p = plan(["hascard", "mastered", "tooeasy", "unknown", "fresh", "fresh", "next", "later"], dailyNew: 5)
        let s = compose(obs, plan: p, mastered: ["mastered"], known: { $0 != "unknown" }, now: at(day: 2))
        #expect(s.newCards == ["fresh", "next", "later"])
    }

    @Test func tooEasyOnFirstSightDoesNotUseUpTheLimit() {
        let obs = [review("tooeasy", .easy, at(day: 1)), review("started", .good, at(day: 1))]
        let s = compose(obs, plan: plan(["a", "b", "c"], dailyNew: 2), now: at(day: 1, hour: 20))
        #expect(s.newCards == ["a"])
    }

    @Test func aCardOnAMasteredWordIsPaused() {
        let obs = learned("alpha", on: 1)
        #expect(compose(obs, plan: nil, now: at(day: 12)).reviews == ["alpha"])
        #expect(compose(obs, plan: nil, mastered: ["alpha"], now: at(day: 12)).reviews == [])
    }

    @Test func dailyLimitComesFromTheLatestSettingObservation() {
        #expect(StudySettings.dailyNewLimit(from: []) == StudySettings.defaultDailyNewLimit)
        let obs = [StudyObservations.dailyNewLimit(15, at: at(day: 1)), StudyObservations.dailyNewLimit(7, at: at(day: 2))]
        #expect(StudySettings.dailyNewLimit(from: obs) == 7)
        #expect(obs[1].source == .setting && obs[1].lemma == SettingKey.dailyNewLimit && obs[1].result == "7")
    }

    @Test func addingAWordIsAWishObservationAndCreatesNoCard() {
        let wish = StudyObservations.wish("serendipity", at: at(day: 1), lexiconVersion: "lex-1")
        #expect(wish == Observation(ts: "2026-11-01T09:00:00.000Z", lemma: "serendipity", source: .wish,
                                    result: "add", lexicon: "lex-1"))
        #expect(composer.ledger(observations: [wish], now: at(day: 2)).cards.isEmpty)
    }
}
