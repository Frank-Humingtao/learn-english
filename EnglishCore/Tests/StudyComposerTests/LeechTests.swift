import CoreModels
import Foundation
import StudyComposer
import Testing

@Suite struct LeechTests {
    let composer = StudyComposer()

    /// "leech" forgotten 8 times on `day` (10 minutes apart), i.e. a Leech since then.
    func forgottenEightTimes(_ lemma: String, day: Int) -> [Observation] {
        (0..<8).map { review(lemma, .again, at(day: day, hour: 8 + $0 / 6, minute: $0 % 6 * 10)) }
    }

    func compose(_ obs: [Observation], plan: StudyPlan?, limit: Int = 20, now: Date) -> StudySession {
        composer.compose(observations: obs, plan: plan, dailyNewLimit: limit, isMastered: { _ in false },
                         now: now, calendar: utc)
    }

    @Test func aLeechIsPausedAndListed() {
        let obs = forgottenEightTimes("leech", day: 1)
        let s = compose(obs, plan: nil, now: at(day: 2))
        #expect(s.reviews == [])
        let leeches = composer.ledger(observations: obs, now: at(day: 2)).leeches
        #expect(leeches.map(\.lemma) == ["leech"])
        #expect(leeches[0].lapses == 8)
        #expect(leeches[0].reintroduceAt == at(day: 31, hour: 9, minute: 10))
        // Seven lapses is not a Leech yet.
        #expect(composer.ledger(observations: Array(obs.dropLast()), now: at(day: 2)).leeches.isEmpty)
    }

    @Test func afterThirtyDaysALeechComesBackFirstAmongNewCardsAndCountsTowardTheLimit() {
        let obs = forgottenEightTimes("leech", day: 1)
        let p = plan(["a", "b", "c"], dailyNew: 2)
        #expect(compose(obs, plan: p, now: at(day: 30)).newCards == ["a", "b"])
        let back = compose(obs, plan: p, now: at(day: 31, hour: 12))
        #expect(back.newCards == ["leech", "a"])
        #expect(composer.ledger(observations: obs, now: at(day: 31, hour: 12)).leeches.isEmpty)
    }

    @Test func relearnRestartsALeechAtOnce() {
        let obs = forgottenEightTimes("leech", day: 1) + [relearn("leech", at(day: 3))]
        #expect(StudyObservations.relearn("leech", at: at(day: 3)) == relearn("leech", at(day: 3)))
        let s = compose(obs, plan: plan(["a", "b", "c"], dailyNew: 2), now: at(day: 3, hour: 12))
        #expect(s.newCards == ["leech", "a"])
        #expect(s.phase == .newCard("leech"))
        // Once restarted, its old lapses no longer count: one more "忘了" is not a Leech again.
        let more = obs + [review("leech", .again, at(day: 3, hour: 13))]
        #expect(composer.ledger(observations: more, now: at(day: 4)).leeches.isEmpty)
    }

    @Test func aRestartedLeechStartedTodayUsesUpTheLimit() {
        let obs = forgottenEightTimes("leech", day: 1) + [relearn("leech", at(day: 3)),
                                                          review("leech", .good, at(day: 3, hour: 10))]
        let s = compose(obs, plan: plan(["a", "b", "c"], dailyNew: 2), now: at(day: 3, hour: 12))
        #expect(s.newCards == ["a"])
    }
}
