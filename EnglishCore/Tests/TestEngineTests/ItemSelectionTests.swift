import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import TestEngine
import Testing

@Suite struct ItemSelectionTests {
    let lexicon = syntheticLexicon(count: 6000)

    /// History of a learner who knows the first 1500 words: a spread of answers over the lexicon.
    func history() -> [Observation] {
        var out: [Observation] = []
        for k in 0..<120 {
            let rank = 1 + k * 50
            let lemma = lexicon.entries[rank - 1].lemma
            out.append(Observation(ts: stamp(day: 1, second: k), lemma: lemma, source: .test,
                                   result: rank <= 1500 ? "yes" : "no", session: "h1"))
        }
        return out
    }

    func session(history: [Observation], config: TestConfig = .short, seed: UInt64 = 7) -> TestSession {
        let profile = ProfileEngine.compute(observations: history, lexicon: lexicon)
        return TestSession(lexicon: lexicon, profile: profile, history: history, config: config,
                           sessionID: "s-test", seed: seed)
    }

    /// Runs the whole session with a learner who knows ranks ≤ 1500.
    func run(_ s: inout TestSession) {
        var learner = ThresholdLearner(knownUpTo: 1500)
        runSession(&s, learner: &learner, lexicon: lexicon, day: 3)
    }

    func yesNoItems(_ s: TestSession) -> [YesNoItem] {
        s.items.compactMap { if case .yesNo(let q) = $0 { return q } else { return nil } }
    }

    @Test func itemKindsFollowTheConfiguredFractions() {
        var s = session(history: history())
        run(&s)
        let items = yesNoItems(s)
        #expect(items.count == TestConfig.short.yesNoCount)
        func share(_ k: YesNoItem.Kind) -> Double { Double(items.filter { $0.kind == k }.count) / Double(items.count) }
        #expect(abs(share(.pseudoword) - 0.15) <= 0.01)
        let real = 0.85
        #expect(abs(share(.stratified) - 0.40 * real) <= 0.02)
        #expect(abs(share(.uncertain) - 0.40 * real) <= 0.02)
        #expect(abs(share(.boundary) - 0.15 * real) <= 0.02)
        #expect(abs(share(.retest) - 0.05 * real) <= 0.02)
    }

    @Test func fractionsAreConfigurable() {
        var config = TestConfig(yesNoCount: 200)
        config.pseudowordFraction = 0.10
        config.allocation = .init(stratified: 1, uncertain: 0, boundary: 0, retest: 0)
        var s = session(history: history(), config: config)
        run(&s)
        let items = yesNoItems(s)
        #expect(items.filter { $0.kind == .pseudoword }.count == 20)
        #expect(items.filter { $0.kind == .stratified }.count == 180)
    }

    @Test func withoutEarlierAnswersRetestSlotsGoToTheStratifiedSample() {
        var s = session(history: [])
        run(&s)
        let items = yesNoItems(s)
        #expect(items.count == TestConfig.short.yesNoCount)
        #expect(!items.contains { $0.kind == .retest })
    }

    @Test func stratifiedSampleReachesEveryFrequencyLevelIncludingTheTail() {
        var s = session(history: history())
        run(&s)
        let levels = yesNoItems(s).filter { $0.kind == .stratified }.map { lexicon.entry(lemma: $0.word)!.level }
        for level in 1...6 {
            #expect(levels.filter { $0 == level }.count >= 2, "level \(level): \(levels.filter { $0 == level }.count)")
        }
    }

    @Test func neymanAllocationFavoursLevelsWhereKnowledgeIsMostUncertain() {
        // The learner of `history` knows level 1 and part of level 2: level 2 is the most uncertain.
        var s = session(history: history(), config: TestConfig(yesNoCount: 450))
        run(&s)
        let levels = yesNoItems(s).filter { $0.kind == .stratified }.map { lexicon.entry(lemma: $0.word)!.level }
        let count = { (l: Int) in levels.filter { $0 == l }.count }
        let profile = ProfileEngine.compute(observations: history(), lexicon: lexicon)
        let mastery = Dictionary(uniqueKeysWithValues: profile.levelMastery.map { ($0.level, $0.mastery) })
        let spread = { (l: Int) in mastery[l]! * (1 - mastery[l]!) }
        let mostUncertain = (1...6).max { spread($0) < spread($1) }!
        let leastUncertain = (1...6).min { spread($0) < spread($1) }!
        #expect(count(mostUncertain) > count(leastUncertain), "\(levels)")
    }

    @Test func boundaryWordsSitNearTheLearnersBoundary() {
        let h = history()
        var s = session(history: h)
        run(&s)
        // Judged at the profile after the test: the live estimate has moved them toward 0.5.
        let profile = ProfileEngine.compute(observations: h + s.observations, lexicon: lexicon)
        let boundary = yesNoItems(s).filter { $0.kind == .boundary }.map(\.word)
        let stratified = yesNoItems(s).filter { $0.kind == .stratified }.map(\.word)
        let rank = { (w: String) in Double(lexicon.entry(lemma: w)!.rank) }
        // Boundary words cluster around the learner's edge (rank 1500), stratified ones spread out.
        let meanDistance = { (ws: [String]) in ws.map { abs(log(rank($0) / 1500)) }.reduce(0, +) / Double(ws.count) }
        #expect(meanDistance(boundary) < 0.6 * meanDistance(stratified), "\(boundary)")
        _ = profile
    }

    @Test func uncertainWordsAreFrequentWordsWithUncertainP() {
        var s = session(history: history())
        run(&s)
        let uncertain = yesNoItems(s).filter { $0.kind == .uncertain }.map { lexicon.entry(lemma: $0.word)!.rank }
        let stratified = yesNoItems(s).filter { $0.kind == .stratified }.map { lexicon.entry(lemma: $0.word)!.rank }
        func median(_ a: [Int]) -> Int { a.sorted()[a.count / 2] }
        // Token-frequency weighting pulls them toward frequent words, but not the ones the learner surely knows.
        #expect(median(uncertain) < median(stratified))
        #expect(median(uncertain) > 300, "\(uncertain.sorted())")
    }

    @Test func realWordsAreNeverPreviouslyTestedOrRepeatedExceptRetests() {
        let h = history()
        let tested = Set(h.map(\.lemma))
        var s = session(history: h)
        run(&s)
        let items = yesNoItems(s)
        let real = items.filter { $0.kind.isReal }.map(\.word)
        #expect(Set(real).count == real.count)
        for q in items where q.kind.isReal {
            #expect(tested.contains(q.word) == (q.kind == .retest), "\(q)")
        }
    }

    @Test func pseudowordsAreFreshNonwordsMatchedToTheSessionsWords() {
        var s = session(history: history())
        run(&s)
        let items = yesNoItems(s)
        let pseudo = items.filter { $0.kind == .pseudoword }.map(\.word)
        let realLengths = Set(items.filter { $0.kind.isReal }.map(\.word.count))
        #expect(Set(pseudo).count == pseudo.count)
        for p in pseudo {
            #expect(lexicon.lemma(for: p) == nil, "\(p) is a real word")
            #expect(p.allSatisfy { $0.isLetter && $0.isLowercase })
            #expect((p.count - 1...p.count + 1).contains { realLengths.contains($0) }, "\(p)")
        }
        // Length distribution close to the real words'.
        let mean = { (ws: [String]) in Double(ws.map(\.count).reduce(0, +)) / Double(ws.count) }
        #expect(abs(mean(pseudo) - mean(items.filter { $0.kind.isReal }.map(\.word))) < 1.0)
    }

    @Test func pseudowordsAreNeverReused() {
        var h = history()
        var first = session(history: h, seed: 1)
        run(&first)
        let firstPseudo = yesNoItems(first).filter { $0.kind == .pseudoword }
        for (i, p) in firstPseudo.enumerated() {
            h.append(Observation(ts: stamp(day: 2, second: i), lemma: p.word, source: .test, result: "no",
                                 session: "h2", pseudo: true))
        }
        var second = session(history: h, seed: 1)
        run(&second)
        let secondPseudo = yesNoItems(second).filter { $0.kind == .pseudoword }
        #expect(Set(firstPseudo.map(\.word)).isDisjoint(with: secondPseudo.map(\.word)))
    }

    @Test func pseudowordsThatLookDerivedFromARealWordAreRejected() {
        let gen = Pseudowords(lexicon: lexicon)
        let base = lexicon.entries[10].lemma
        #expect(gen.looksDerived(base + "ness"))
        #expect(gen.looksDerived(base + "s"))
        #expect(!gen.looksDerived("zzqvnt"))
    }

    @Test func sameSeedAndAnswersGiveTheSameTest() {
        let h = history()
        var a = session(history: h, seed: 3), b = session(history: h, seed: 3), c = session(history: h, seed: 4)
        run(&a)
        run(&b)
        run(&c)
        #expect(a.items == b.items)
        #expect(a.items != c.items)
    }
}
