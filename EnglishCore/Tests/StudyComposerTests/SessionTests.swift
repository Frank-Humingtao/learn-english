import CoreModels
import FSRS
import Foundation
import StudyComposer
import Testing

@Suite struct SessionTests {
    let composer = StudyComposer()

    func compose(_ obs: [Observation], plan: StudyPlan?, now: Date) -> StudySession {
        composer.compose(observations: obs, plan: plan, dailyNewLimit: 20, isMastered: { _ in false },
                         now: now, calendar: utc, sessionID: "s1", lexiconVersion: "lex-test")
    }

    @Test func reviewsThenStopPointThenNewCardsThenDone() {
        var s = compose(learned("alpha", on: 1), plan: plan(["b"], dailyNew: 1), now: at(day: 12))
        #expect(s.phase == .review("alpha"))
        _ = s.rate(.good, rtMs: 900, at: at(day: 12))
        #expect(s.phase == .separator(newCount: 1))
        s.startNewCards()
        #expect(s.phase == .newCard("b"))
        // A new card rated 想起 comes back after its 10-minute learning step, then graduates.
        _ = s.rate(.good, rtMs: 900, at: at(day: 12, minute: 1))
        #expect(s.phase == .newCard("b"))
        _ = s.rate(.good, rtMs: 900, at: at(day: 12, minute: 12))
        #expect(s.phase == .done)
        #expect(s.summary == StudySession.Summary(reviewed: 1, learned: 1, tooEasy: 0, ratings: 3))
    }

    @Test func theLearnerCanStopAtTheSeparator() {
        var s = compose(learned("alpha", on: 1), plan: plan(["b"], dailyNew: 1), now: at(day: 12))
        _ = s.rate(.good, rtMs: nil, at: at(day: 12))
        s.finish()
        #expect(s.phase == .done)
    }

    @Test func tooEasyOnANewCardPausesItAndTakesTheNextPlanWord() {
        var s = compose([], plan: plan(["a", "b", "c"], dailyNew: 1), now: at(day: 1))
        #expect(s.newCards == ["a"])
        _ = s.rate(.easy, rtMs: nil, at: at(day: 1))
        #expect(s.phase == .newCard("b"))
        #expect(s.newCards == ["a", "b"])
        #expect(s.summary.tooEasy == 1)
        // The paused card stays out of later sessions; the replacement used today's slot.
        let obs = [review("a", .easy, at(day: 1)), review("b", .good, at(day: 1))]
        let later = compose(obs, plan: plan(["a", "b", "c"], dailyNew: 1), now: at(day: 1, hour: 22))
        #expect(later.newCards == [])
        #expect(composer.ledger(observations: obs, now: at(day: 1, hour: 22)).cards["a"]?.suspended == .firstEasy)
    }

    @Test func buttonIntervalsAreWhatSwiftFSRSComputes() throws {
        let now = at(day: 12)
        let s = compose(learned("alpha", on: 1), plan: nil, now: now)
        // Independent replay with swift-fsrs directly.
        let fsrs = FSRS(parameters: FSRSParameters(requestRetention: 0.9, w: FSRSDefaults.defaultWv6,
                                                   enableFuzz: false, enableShortTerm: true,
                                                   learningSteps: ["1m", "10m"], relearningSteps: ["10m"]))
        var card = FSRSDefaults().createEmptyCard(now: at(day: 1, hour: 8))
        card = try fsrs.next(card: card, now: at(day: 1, hour: 8), grade: .good).card
        card = try fsrs.next(card: card, now: at(day: 1, hour: 8, minute: 15), grade: .good).card
        let preview = try fsrs.repeat(card: card, now: now)
        let intervals = s.intervals(at: now)
        #expect(intervals.count == 4)
        for (g, r) in [(Grade.again, Rating.again), (.hard, .hard), (.good, .good), (.easy, .easy)] {
            #expect(intervals[g] == preview[r]!.card.due.timeIntervalSince(now))
        }
        // Sanity: 忘了 is minutes away, 太简单 is days away and further than 想起.
        #expect(intervals[.again]! == 600)
        #expect(intervals[.easy]! > intervals[.good]! && intervals[.good]! >= 86400)
    }

    @Test func aRatingBecomesAReviewObservationWithRevlogFields() throws {
        let now = at(day: 12)
        var s = compose(learned("alpha", on: 1), plan: nil, now: now)
        let good = s.intervals(at: now)[.good]!
        let rated = s.rate(.good, rtMs: 1234, at: now)
        let o = try #require(rated)
        #expect(o.lemma == "alpha" && o.source == .review && o.result == "good")
        #expect(o.rtMs == 1234 && o.session == "s1" && o.lexicon == "lex-test")
        #expect(o.ts == "2026-11-12T09:00:00.000Z")
        let log = try #require(o.review)
        #expect(log.ease == 3)
        #expect(log.type == 1) // review
        #expect(log.time == 1234)
        #expect(log.ivl == Int(good / 86400))
        #expect(log.lastIvl! >= 1)
        #expect(log.stability! > 0 && log.difficulty! > 0)
        #expect(log.due == Timestamp.iso(now.timeIntervalSince1970 + good))
    }

    @Test func replayingRecordedObservationsGivesTheSameSchedule() {
        // What the session schedules must match what the ledger rebuilds from its Observations.
        var s = compose([], plan: plan(["a"], dailyNew: 1), now: at(day: 1))
        var obs: [Observation] = []
        var t = at(day: 1)
        for g in [Grade.hard, .again, .good, .hard, .good] where s.current != nil {
            obs.append(s.rate(g, rtMs: nil, at: t)!)
            t += 700
        }
        #expect(obs.count == 5)
        let card = composer.ledger(observations: obs, now: t).cards["a"]!
        #expect(Timestamp.iso(card.memory.due.timeIntervalSince1970) == obs.last!.review!.due)
    }
}
