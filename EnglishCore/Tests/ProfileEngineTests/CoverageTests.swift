import CoreModels
import Lexicon
import ProfileEngine
import Testing

@Suite struct CoverageTests {
    // Ranks: the..bank are frequent (known), quixotic/obfuscate are rare (unknown).
    let lexicon: Lexicon = {
        let words = ["the", "cat", "run", "to", "bank", "be", "river"]
        var entries = words.enumerated().map { i, w in
            LexiconEntry(lemma: w, rank: i + 1, family: w, familyRank: i + 1, level: 1)
        }
        for i in 8...9000 { // filler so the fit has a frequency scale
            entries.append(LexiconEntry(lemma: word(i), rank: i, family: word(i), familyRank: i, level: (i - 1) / 1000 + 1))
        }
        entries.append(LexiconEntry(lemma: "quixotic", rank: 9001, family: "quixotic", familyRank: 9001, level: 10))
        entries.append(LexiconEntry(lemma: "obfuscate", rank: 9002, family: "obfuscate", familyRank: 9002, level: 10))
        return Lexicon(version: "t", entries: entries,
                       forms: ["cats": "cat", "ran": "run", "running": "run", "is": "be", "was": "be",
                               "obfuscated": "obfuscate"],
                       supplementary: ["london", "bbc"])
    }()

    func profile() -> LearnerProfile {
        var observations: [Observation] = []
        for i in stride(from: 100, through: 9000, by: 100) {
            observations.append(obs(word(i), .test, i <= 2000 ? "yes" : "no", day: 0, minute: i / 100))
        }
        for w in ["the", "cat", "run", "to", "bank", "be", "river"] {
            observations.append(obs(w, .test, "yes", day: 0))
        }
        observations.append(obs("quixotic", .test, "no", day: 0))
        observations.append(obs("obfuscate", .test, "no", day: 0))
        return ProfileEngine.compute(observations: observations, lexicon: lexicon)
    }

    @Test func coverageOfKnownTextIsHigh() {
        let c = profile().coverage(of: "The cat ran to the bank of the river.")
        #expect(c.tokens == 8) // "of" is not in this lexicon
        #expect(c.outOfLexicon == 1)
        #expect(c.known > 0.95)
        #expect(c.mastered == 1.0)
    }

    @Test func coverageCountsUnknownTokens() {
        // 8 tokens, 2 of them unknown rare words.
        let c = profile().coverage(of: "The cat was quixotic; the bank obfuscated it")
        #expect(c.tokens == 7) // "it" is not in this lexicon
        #expect(c.outOfLexicon == 1)
        #expect(abs(c.mastered - 5.0 / 7.0) < 1e-9)
        #expect(c.known > 0.6 && c.known < 0.8)
    }

    @Test func inflectedFormsAreLemmatized() {
        let p = profile()
        #expect(p.coverage(of: "Cats running").known == p.coverage(of: "cat run").known)
    }

    @Test func properNamesAndNumbersCountAsKnownOrAreSkipped() {
        let c = profile().coverage(of: "The BBC in London, 1999: quixotic!")
        // the, bbc, london, quixotic -> 3 of 4 known; "in" is out of lexicon, 1999 skipped.
        #expect(c.tokens == 4)
        #expect(abs(c.mastered - 0.75) < 1e-9)
    }
}
