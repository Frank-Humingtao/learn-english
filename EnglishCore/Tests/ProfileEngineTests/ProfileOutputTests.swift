import CoreModels
import Lexicon
import ProfileEngine
import Testing

/// Vocabulary size, word family conversion, Word Bands and level mastery.
@Suite struct ProfileOutputTests {
    func background(knownUpTo: Int, day: Int = 0) -> [Observation] {
        var out: [Observation] = []
        for i in stride(from: 50, through: 9950, by: 100) {
            out.append(obs(word(i), .test, i <= knownUpTo ? "yes" : "no", day: day, minute: i / 100))
        }
        return out
    }

    @Test func vocabularySizeIsTheSumOfPWithA95PercentInterval() {
        let lexicon = syntheticLexicon(count: 10000)
        let profile = ProfileEngine.compute(observations: background(knownUpTo: 3000), lexicon: lexicon)
        let v = profile.vocabulary.lemmas
        let sum = profile.probabilities.reduce(0, +)
        #expect(abs(v.estimate - sum) < 1e-6)
        #expect(v.low < v.estimate && v.estimate < v.high)
        // Learner says yes to everything up to 3000 and no beyond: estimate lands near 3000.
        #expect(v.estimate > 2500 && v.estimate < 3800)
    }

    @Test func moreEvidenceNarrowsTheInterval() {
        let lexicon = syntheticLexicon(count: 10000)
        let one = ProfileEngine.compute(observations: background(knownUpTo: 3000), lexicon: lexicon)
        let three = ProfileEngine.compute(
            observations: background(knownUpTo: 3000) + background(knownUpTo: 3000, day: 1)
                + background(knownUpTo: 3000, day: 2),
            lexicon: lexicon)
        let none = ProfileEngine.compute(observations: [], lexicon: lexicon)
        func width(_ p: LearnerProfile) -> Double { p.vocabulary.lemmas.high - p.vocabulary.lemmas.low }
        #expect(width(three) < width(one))
        #expect(width(one) < width(none))
    }

    @Test func familiesCountEachWordFamilyOnce() {
        // Families w00001...w00100 each get two derived members ranked after all headwords.
        var derived: [(member: String, family: String)] = []
        for i in 1...100 {
            derived.append(("a" + word(i), word(i)))
            derived.append(("b" + word(i), word(i)))
        }
        let lexicon = syntheticLexicon(count: 10000, derived: derived)
        let profile = ProfileEngine.compute(observations: background(knownUpTo: 3000), lexicon: lexicon)
        // 10200 lemmas but 10000 families.
        #expect(profile.vocabulary.familyCount == 10000)
        // Derived members of top-100 families are known about as well as headwords at their rank,
        // yet add nothing to the family count: the family total stays at or below the lemma total.
        #expect(profile.vocabulary.families.estimate < profile.vocabulary.lemmas.estimate)

        // Knowing a derived member makes its (otherwise unknown) family known.
        let distantFamily = word(9500)
        let lexicon2 = syntheticLexicon(count: 10000, derived: [("x" + distantFamily, distantFamily)])
        let base = ProfileEngine.compute(observations: background(knownUpTo: 3000), lexicon: lexicon2)
        let withMember = ProfileEngine.compute(
            observations: background(knownUpTo: 3000) + [
                obs("x" + distantFamily, .test, "yes", day: 0, minute: 200),
                obs("x" + distantFamily, .verify, "correct", day: 0, minute: 201),
                obs("x" + distantFamily, .review, "easy", day: 0, minute: 202),
            ],
            lexicon: lexicon2)
        #expect(base.familyProbability(of: distantFamily)! < 0.1)
        #expect(withMember.familyProbability(of: distantFamily)! > 0.8)
        #expect(withMember.familyProbability(of: distantFamily)! == withMember.probability(of: "x" + distantFamily)!)
        #expect(withMember.vocabulary.families.estimate - base.vocabulary.families.estimate > 0.5)
    }

    @Test func wordBandsFollowThresholds() {
        let lexicon = syntheticLexicon(count: 10000)
        let farCard = word(9900)
        let leech = word(9800)
        var observations = background(knownUpTo: 3000)
        observations.append(obs(farCard, .review, "again", day: 1))
        for k in 0..<8 { observations.append(obs(leech, .review, "again", day: 1, minute: k)) }
        let profile = ProfileEngine.compute(observations: observations, lexicon: lexicon)
        let window = Int(profile.vocabulary.lemmas.estimate) + 2000

        for e in lexicon.entries {
            let p = profile.probability(of: e.lemma)!
            let band = profile.band(of: e.lemma)!
            if p >= 0.9 {
                #expect(band == .mastered, "\(e.lemma) p=\(p)")
            } else if e.lemma == farCard {
                #expect(band == .target, "active card is Target")
            } else if e.rank <= window - 1 {
                #expect(band == .target, "\(e.lemma) p=\(p)")
            } else if e.rank > window + 1 {
                #expect(band == .distant, "\(e.lemma) p=\(p)")
            }
        }
        #expect(profile.band(of: leech) == .distant, "a Leech is no longer an active card")
        let counts = profile.bandCounts
        #expect(counts.mastered + counts.target + counts.distant == 10000)
        #expect(counts.mastered > 1000 && counts.mastered < 3000, "\(counts) theta=\(profile.theta) slope=\(profile.slope) v=\(profile.vocabulary.lemmas)")
    }

    @Test func thresholdsAreTunable() {
        let lexicon = syntheticLexicon(count: 10000)
        var strict = ProfileConfig()
        strict.masteredThreshold = 0.97
        strict.targetWindow = 500
        let normal = ProfileEngine.compute(observations: background(knownUpTo: 3000), lexicon: lexicon)
        let tuned = ProfileEngine.compute(observations: background(knownUpTo: 3000), lexicon: lexicon, config: strict)
        #expect(tuned.bandCounts.mastered < normal.bandCounts.mastered)
        #expect(tuned.bandCounts.distant > normal.bandCounts.distant)
    }

    @Test func levelMasteryFallsAcrossFrequencyLevels() {
        let lexicon = syntheticLexicon(count: 10000)
        let profile = ProfileEngine.compute(observations: background(knownUpTo: 3000), lexicon: lexicon)
        let levels = profile.levelMastery
        #expect(levels.map(\.level) == Array(1...10))
        #expect(levels.allSatisfy { $0.families == 1000 })
        #expect(levels[0].mastery > 0.9)
        #expect(levels[9].mastery < 0.2)
        #expect(levels.map(\.mastery) == levels.map(\.mastery).sorted(by: >))
    }
}
