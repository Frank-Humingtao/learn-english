import CoreModels
import Lexicon
import ProfileEngine
import Testing

@Suite struct EvidenceTests {
    let lexicon = syntheticLexicon(count: 10000)

    // A shared background so the global fit has something to work with.
    func background() -> [Observation] {
        var out: [Observation] = []
        for i in stride(from: 100, through: 9000, by: 100) {
            out.append(obs(word(i), .test, i <= 3000 ? "yes" : "no", day: 0, minute: i / 100))
        }
        return out
    }

    func p(_ lemma: String, _ extra: [Observation]) -> Double {
        var config = ProfileConfig()
        config.asOf = ts(day: 5) // fixed, so extra Observations don't shift the decay clock
        return ProfileEngine.compute(observations: background() + extra, lexicon: lexicon, config: config)
            .probability(of: lemma)!
    }

    @Test func knownAnswersRaiseAndUnknownAnswersLowerP() {
        let target = word(4321)
        let base = p(target, [])
        let oneYes = p(target, [obs(target, .test, "yes", day: 1)])
        let twoYes = p(target, [obs(target, .test, "yes", day: 1), obs(target, .verify, "correct", day: 1, minute: 1)])
        let oneNo = p(target, [obs(target, .test, "no", day: 1)])
        #expect(oneNo < base)
        #expect(base < oneYes)
        #expect(oneYes < twoYes)
    }

    @Test func reviewForgotCountsAsUnknownOtherRatingsAsKnown() {
        let target = word(4321)
        let base = p(target, [])
        #expect(p(target, [obs(target, .review, "again", day: 1)]) < base)
        for rating in ["hard", "good", "easy"] {
            // Seed the card with a first review so `easy` is not a first rating here.
            let first = obs(target, .review, "good", day: 1)
            let withRating = p(target, [first, obs(target, .review, rating, day: 2)])
            #expect(withRating > p(target, [first]), "rating \(rating) should count as known")
        }
    }

    @Test func firstRatingTooEasyIsStrongerThanAnOrdinaryKnownAnswer() {
        let target = word(6000)
        let easyFirst = p(target, [obs(target, .review, "easy", day: 1)])
        let goodFirst = p(target, [obs(target, .review, "good", day: 1)])
        #expect(easyFirst > goodFirst + 0.2)
        // Near the Learner's boundary (background knows up to rank ~3000) one "too easy" suffices for Mastered.
        let boundary = word(3000)
        #expect(p(boundary, [obs(boundary, .review, "easy", day: 1)]) >= 0.9)
    }

    @Test func wishesAndSettingsAreNotVocabularyEvidence() {
        let target = word(4321)
        let base = p(target, [])
        let noise = [
            obs(target, .wish, "add", day: 1),
            obs(target, .setting, "daily_new=10", day: 1),
        ]
        #expect(abs(p(target, noise) - base) < 1e-12)
    }

    @Test func falseAlarmsOnPseudowordsDiscountYesAnswers() {
        let target = word(4321)
        let yes = obs(target, .test, "yes", day: 1)
        func pseudo(_ k: Int, _ result: String) -> Observation {
            Observation(ts: ts(day: 1, minute: k), lemma: "blorf\(k)", source: .test, result: result, pseudo: true)
        }
        let honest = (0..<40).map { pseudo($0, "no") }
        let guesser = (0..<40).map { pseudo($0, $0 % 2 == 0 ? "yes" : "no") }
        let pHonest = p(target, [yes] + honest)
        let pGuesser = p(target, [yes] + guesser)
        #expect(pGuesser < pHonest)

        var config = ProfileConfig()
        config.asOf = ts(day: 5)
        let profileGuesser = ProfileEngine.compute(observations: background() + guesser, lexicon: lexicon, config: config)
        let profileHonest = ProfileEngine.compute(observations: background() + honest, lexicon: lexicon, config: config)
        #expect(profileGuesser.falseAlarmRate > 0.2)
        #expect(profileHonest.falseAlarmRate < 0.02)
        #expect(profileGuesser.vocabulary.lemmas.estimate < profileHonest.vocabulary.lemmas.estimate)
    }

    @Test func pFallsWithFrequencyRankForUnobservedWords() {
        let profile = ProfileEngine.compute(observations: background(), lexicon: lexicon)
        let ps = [10, 1000, 3000, 6000, 9999].map { profile.probability(of: word($0))! }
        #expect(ps == ps.sorted(by: >))
        #expect(ps.first! > 0.9)
        #expect(ps.last! < 0.1)
    }
}
