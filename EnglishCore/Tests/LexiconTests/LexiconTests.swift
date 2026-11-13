import Foundation
import Lexicon
import Testing

/// The committed fixture is a 1-in-50 family sample of a real build (true ranks kept).
let fixtureLexicon = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/lexicon")

@Suite struct LexiconTests {
    let lexicon = try! Lexicon.load(directory: fixtureLexicon)

    @Test func carriesTheBuildVersion() throws {
        let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureLexicon.appendingPathComponent("meta.json"))) as! [String: Any]
        #expect(lexicon.version == meta["version"] as! String)
        #expect(lexicon.version.hasPrefix("lex-"))
    }

    @Test func looksUpDefinitionPhoneticRankAndExample() throws {
        let tax = try #require(lexicon.lookup("tax"))
        #expect(tax.lemma == "tax")
        #expect(tax.level == 1)
        #expect(tax.rank == 459)
        #expect(tax.phonetic == "tæks")
        #expect(tax.translation.contains("税"))
        #expect(!tax.definition.isEmpty)

        let be = try #require(lexicon.lookup("be"))
        #expect(be.rank == 1)
        #expect(!be.example.isEmpty)
        #expect(be.audio.hasPrefix("https://"))
    }

    @Test func multiLineFieldsAreUnescaped() throws {
        let be = try #require(lexicon.lookup("be"))
        #expect(be.definition.contains("\n"))
        #expect(!be.definition.contains("\\n"))
    }

    @Test func inflectedFormsResolveToTheirLemma() throws {
        #expect(lexicon.lookup("Taxes")?.lemma == "tax")
        #expect(lexicon.lookup("accepted")?.lemma == "accept")
        #expect(lexicon.lemma(for: "qwzx") == nil)
    }

    @Test func supplementaryWordsAreLoaded() {
        #expect(lexicon.supplementary.contains("alice"))
    }

    @Test func entriesAreSortedByRankAndFamiliesAreGrouped() {
        let ranks = lexicon.entries.map(\.rank)
        #expect(ranks == ranks.sorted())
        #expect(lexicon.entries.count == 925)
        #expect(Set(lexicon.entries.map(\.family)).count == 500)
    }
}
