import CoreModels
import Lexicon
import ProfileEngine

/// Chooses the Yes/No items of one test.
enum ItemSelector {
    static func yesNoItems(lexicon: Lexicon, profile: LearnerProfile, history: [Observation], config: TestConfig,
                           rng: inout SplitMix64) -> [YesNoItem] {
        var tested = Set<Int>()
        var usedPseudowords = Set<String>()
        for o in history {
            if o.pseudo == true {
                usedPseudowords.insert(o.lemma.lowercased())
            } else if [.test, .spotcheck, .verify].contains(o.source),
                      let l = lexicon.lemma(for: o.lemma), let i = lexicon.index(of: l) {
                tested.insert(i)
            }
        }

        let total = max(0, config.yesNoCount)
        let pseudoCount = Int((Double(total) * config.pseudowordFraction).rounded())
        let spotTarget = Int((Double(total) * config.spotcheckFraction).rounded())
        let entries = lexicon.entries
        let p = profile.probabilities

        // Spot checks: random Mastered words.
        var mastered = entries.indices.filter { profile.bands[$0] == .mastered && MeaningChecks.gloss(entries[$0]) != nil }
        mastered.shuffle(using: &rng)
        let spot = Array(mastered.prefix(spotTarget))
        let realCount = total - pseudoCount - spot.count

        // Real words: untested, closest to P = 0.5, randomized among the best (Randomesque).
        let excluded = tested.union(spot)
        let candidates = entries.indices
            .filter { !excluded.contains($0) && MeaningChecks.gloss(entries[$0]) != nil }
            .sorted { abs(p[$0] - 0.5) != abs(p[$1] - 0.5) ? abs(p[$0] - 0.5) < abs(p[$1] - 0.5) : $0 < $1 }
        var pool = Array(candidates.prefix(realCount * max(1, config.poolFactor)))
        pool.shuffle(using: &rng)
        let real = Array(pool.prefix(realCount))

        let pseudo = Pseudowords(lexicon: lexicon).generate(
            count: pseudoCount, templates: real.map { entries[$0].lemma }, excluding: usedPseudowords, rng: &rng)

        var items = real.map { YesNoItem(word: entries[$0].lemma, kind: .real) }
            + spot.map { YesNoItem(word: entries[$0].lemma, kind: .spotcheck) }
            + pseudo.map { YesNoItem(word: $0, kind: .pseudoword) }
        items.shuffle(using: &rng)
        return items
    }
}
