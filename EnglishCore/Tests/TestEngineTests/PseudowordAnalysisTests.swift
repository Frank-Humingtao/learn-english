import CoreModels
import Lexicon
import TestEngine
import Testing

@Suite struct PseudowordAnalysisTests {
    let lexicon = syntheticLexicon(count: 6000)

    /// `n` pseudowords of the given neighbourhood class, `yes` of them answered "yes".
    func answers(_ words: [String], yes: Int, session: String) -> [Observation] {
        words.enumerated().map { k, w in
            Observation(ts: stamp(day: 1, second: k), lemma: w, source: .test, result: k < yes ? "yes" : "no",
                        session: session, pseudo: true)
        }
    }

    @Test func aShapeClassAcceptedFarMoreOftenThanTheRestIsRetired() {
        let gen = Pseudowords(lexicon: lexicon)
        // Close neighbours of real words (one letter changed) vs. strings far from any word.
        let near = lexicon.entries.prefix(400).map { e -> String in
            var c = Array(e.lemma)
            c[c.count - 1] = c[c.count - 1] == "z" ? "x" : "z"
            return String(c)
        }.filter { lexicon.lemma(for: $0) == nil && gen.neighbors($0) >= 2 }.prefix(40)
        let far = (0..<200).map { "qvx" + String(UnicodeScalar(97 + $0 % 26)!) + String(UnicodeScalar(97 + $0 / 26)!) }
            .filter { gen.neighbors($0) == 0 }.prefix(80)
        #expect(near.count >= 25 && far.count >= 40)
        let history = answers(Array(near), yes: near.count / 2, session: "a") + answers(Array(far), yes: 2, session: "b")
        let analysis = PseudowordAnalysis(history: history, lexicon: lexicon)
        let nearShape = gen.shape(near.first!)
        #expect(analysis.retired.contains(nearShape), "\(analysis.rows)")
        #expect(!analysis.retired.contains(gen.shape(far.first!)))
    }

    @Test func nothingIsRetiredWithoutEnoughEvidence() {
        let gen = Pseudowords(lexicon: lexicon)
        let words = gen.generate(count: 15, templates: lexicon.entries.prefix(50).map(\.lemma), seed: 3)
        let analysis = PseudowordAnalysis(history: answers(words, yes: 8, session: "a"), lexicon: lexicon)
        #expect(analysis.retired.isEmpty)
    }
}
