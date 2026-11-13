import CoreModels
import Foundation
import StudyComposer
import Testing

@Suite struct CompositionTests {
    let composer = StudyComposer()

    func compose(_ obs: [Observation], plan: StudyPlan?, limit: Int = 20, mastered: Set<String> = [],
                 now: Date) -> StudySession {
        composer.compose(observations: obs, plan: plan, dailyNewLimit: limit,
                         isMastered: { mastered.contains($0) }, now: now, calendar: utc)
    }

    @Test func dueReviewsComeBeforeNewCards() {
        let obs = learned("alpha", on: 1) + learned("beta", on: 12)
        let s = compose(obs, plan: plan(["gamma", "delta"], dailyNew: 5), now: at(day: 12, hour: 20))
        #expect(s.reviews == ["alpha"])
        #expect(s.newCards == ["gamma", "delta"])
        #expect(s.phase == .review("alpha"))
    }
}
