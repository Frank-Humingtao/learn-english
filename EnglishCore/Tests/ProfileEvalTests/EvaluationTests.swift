import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import ProfileEval
import Testing

// MARK: helpers

/// `count` lemmas `w00001`..., one family each, rank = position.
func syntheticLexicon(count: Int) -> Lexicon {
    Lexicon(version: "test-1", entries: (1...count).map {
        LexiconEntry(lemma: word($0), rank: $0, family: word($0), familyRank: $0, level: ($0 - 1) / 1000 + 1)
    })
}

func word(_ i: Int) -> String {
    let s = String(i)
    return "w" + String(repeating: "0", count: max(0, 5 - s.count)) + s
}

/// Observation at day `day` (Nov 2026), `minute` after noon UTC.
func obs(_ lemma: String, _ source: ObservationSource, _ result: String, day: Int, minute: Int,
         session: String? = nil, pseudo: Bool? = nil) -> Observation {
    let t = 1_793_534_400.0 + Double(day) * 86400 + Double(minute) * 60 // 2026-11-01T12:00:00Z
    return Observation(ts: Timestamp.iso(t), lemma: lemma, source: source, result: result,
                       session: session ?? "s\(day)", pseudo: pseudo)
}

/// A model that predicts a constant and records what it was trained on.
final class StubModel: VocabularyModel {
    let name = "stub"
    let p: Double
    var trainedOn: [[Observation]] = []
    init(p: Double) { self.p = p }

    func fit(observations: [Observation], lexicon: Lexicon) -> ModelFit {
        trainedOn.append(observations)
        let p = self.p
        let n = Double(lexicon.entries.count)
        let total = Interval(estimate: p * n, low: p * n * 0.9, high: p * n * 1.1)
        return ModelFit(knowledge: Array(repeating: p, count: lexicon.entries.count), lemmas: total,
                        families: total) { _, _ in p }
    }
}

// MARK: metrics

@Suite struct MetricsTests {
    @Test func logLossAndBrierOfKnownValues() {
        #expect(abs(Metrics.logLoss([0.5, 0.5], [1, 0]) - log(2)) < 1e-12)
        #expect(abs(Metrics.logLoss([0.8], [1]) + log(0.8)) < 1e-12)
        #expect(abs(Metrics.brier([0.8, 0.3], [1, 0]) - (0.04 + 0.09) / 2) < 1e-12)
    }

    @Test func aucCountsPairsAndHalvesTies() {
        #expect(Metrics.auc([0.1, 0.2, 0.8, 0.9], [0, 0, 1, 1]) == 1)
        #expect(Metrics.auc([0.9, 0.8, 0.2, 0.1], [0, 0, 1, 1]) == 0)
        #expect(Metrics.auc([0.5, 0.5, 0.5], [0, 1, 1]) == 0.5)
        // Positives 0.4, 0.8 vs negatives 0.4, 0.2: pairs 0.5 + 1 + 1 + 1 = 3.5 of 4.
        #expect(Metrics.auc([0.4, 0.8, 0.4, 0.2], [1, 1, 0, 0]) == 0.875)
        #expect(Metrics.auc([0.3, 0.6], [1, 1]) == nil)
    }

    @Test func eceWeighsBinGapsByBinSize() {
        // Bin [0.1, 0.2): mean p 0.15, rate 0 → gap 0.15 × 2/4. Bin [0.9, 1]: p 0.95, rate 0.5 → 0.45 × 2/4.
        let e = Metrics.ece([0.1, 0.2 - 1e-9, 0.95, 0.95], [0, 0, 1, 0])
        #expect(abs(e - (0.15 * 2 + 0.45 * 2) / 4) < 1e-6)
        #expect(Metrics.ece([0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3], [1, 1, 1, 0, 0, 0, 0, 0, 0, 0]) < 1e-12)
    }
}

// MARK: protocol

@Suite struct ProtocolTests {
    let lexicon = syntheticLexicon(count: 100)

    /// Three sessions; session 1 is only pseudowords and a review (nothing scorable).
    var observations: [Observation] {
        [
            obs("zzz", .test, "no", day: 0, minute: 0, pseudo: true),
            obs(word(1), .init(rawValue: "review"), "good", day: 0, minute: 1),
            obs(word(1), .test, "yes", day: 1, minute: 0),
            obs(word(50), .test, "no", day: 1, minute: 1),
            obs(word(2), .test, "yes", day: 1, minute: 2),
            obs(word(2), .verify, "correct", day: 1, minute: 3),
            obs(word(3), .test, "yes", day: 2, minute: 0),
            obs(word(3), .verify, "unknown", day: 2, minute: 1),
            obs(word(50), .test, "yes", day: 2, minute: 2),
            obs("notaword", .test, "yes", day: 2, minute: 3),
        ]
    }

    @Test func scorableItemsAreRealLexiconWordsWithKnownOutcomes() {
        let items = ScoredItem.extract(observations, lexicon: lexicon)
        #expect(items.map(\.observation) == [2, 3, 4, 5, 6, 7, 8])
        #expect(items.map(\.y) == [1, 0, 1, 1, 1, 0, 1])
        #expect(items.filter { $0.kind == .verify }.count == 2)
    }

    @Test func holdoutPredictsEachSessionOnlyFromEarlierObservations() {
        var o = EvalOptions()
        o.simulation = nil
        o.folds = 0
        let stub = StubModel(p: 0.7)
        let r = Evaluation.run(observations: observations, lexicon: lexicon, models: [stub], options: o)
        let h = try! #require(r.models[0].holdout)
        // s1 has no scorable history (s0 has none), so only s2 is predicted.
        #expect(h.scope == ["s2"])
        #expect(h.all.n == 3)
        #expect(h.yesNo?.n == 2 && h.verify?.n == 1)
        #expect(abs(h.all.brier - (0.09 + 0.49 + 0.09) / 3) < 1e-6)
        // The holdout fit for s2 saw exactly the six Observations of s0 and s1.
        #expect(stub.trainedOn.contains { $0.count == 6 && $0.allSatisfy { $0.session != "s2" } })
    }

    @Test func crossValidationPredictsEveryAnswerOnceWithoutSeeingItsWord() {
        var o = EvalOptions()
        o.simulation = nil
        o.folds = 3
        o.minItems = 1000
        let stub = StubModel(p: 0.6)
        let r = Evaluation.run(observations: observations, lexicon: lexicon, models: [stub], options: o)
        #expect(r.models[0].crossValidation?.all.n == 7)
        // Every CV training set misses at least one real word, and pseudowords stay in.
        let cvFits = stub.trainedOn.filter { $0.count < observations.count && $0.contains { $0.pseudo == true } }
        #expect(!cvFits.isEmpty)
        for train in cvFits {
            let seen = Set(train.map(\.lemma))
            #expect(seen.count < Set(observations.map(\.lemma)).count)
        }
    }

    @Test func splitHalfKeepsMeaningChecksWithTheirWordAndAlternatesWords() {
        var obsList: [Observation] = []
        for k in 1...40 {
            obsList.append(obs(word(k), .test, k % 3 == 0 ? "no" : "yes", day: 0, minute: k * 2))
            if k % 4 == 1 { obsList.append(obs(word(k), .verify, "correct", day: 0, minute: k * 2 + 1)) }
        }
        var o = EvalOptions()
        o.simulation = nil
        o.folds = 0
        o.minItems = 10
        let stub = StubModel(p: 0.5)
        let r = Evaluation.run(observations: obsList, lexicon: lexicon, models: [stub], options: o)
        let h = try! #require(r.models[0].splitHalf.first)
        // Words 1, 3, 5, … (with the checks after words 1, 5, 9, …) vs words 2, 4, 6, ….
        #expect(h.itemsA == 30 && h.itemsB == 20)
        #expect(h.consistent)
        let halves = stub.trainedOn.filter { $0.count < obsList.count }
        #expect(halves.count == 2)
        for half in halves {
            let tested = Set(half.filter { $0.source == .test }.map(\.lemma))
            #expect(half.filter { $0.source == .verify }.allSatisfy { tested.contains($0.lemma) })
        }
    }

    @Test func wordRetestPairsSameWordAcrossNearbySessions() {
        let list = [
            obs(word(1), .test, "yes", day: 0, minute: 0),
            obs(word(2), .test, "yes", day: 0, minute: 1),
            obs(word(1), .test, "yes", day: 3, minute: 0),
            obs(word(2), .test, "no", day: 3, minute: 1),
            obs(word(2), .test, "no", day: 20, minute: 0), // too far from day 3
        ]
        var o = EvalOptions()
        o.simulation = nil
        o.folds = 0
        let r = Evaluation.run(observations: list, lexicon: lexicon, models: [], options: o)
        #expect(r.wordRetest.pairs == 2)
        #expect(r.wordRetest.agreement == 0.5)
    }
}

// MARK: models and simulation

@Suite struct ModelAndSimulationTests {
    static let lexicon = syntheticLexicon(count: 6000)

    @Test func frequencyBaselineRecoversTheGeneratingCurve() {
        // Deterministic data from P = σ(1.5 − 1.2·ln(rank/1000)): 20 answers per probed rank,
        // with the expected share of "yes".
        var list: [Observation] = []
        var minute = 0
        for r in stride(from: 10, through: 6000, by: 60) {
            let p = 1 / (1 + exp(-(1.5 - 1.2 * log(Double(r) / 1000))))
            let yes = Int((p * 20).rounded())
            for k in 0..<20 {
                minute += 1
                list.append(obs(word(r), .test, k < yes ? "yes" : "no", day: minute / 1400, minute: minute % 1400))
            }
        }
        let fit = FrequencyBaselineModel().fit(observations: list, lexicon: Self.lexicon)
        let truth = (1...6000).reduce(0.0) { $0 + 1 / (1 + exp(-(1.5 - 1.2 * log(Double($1) / 1000)))) }
        #expect(abs(fit.lemmas.estimate - truth) / truth < 0.02, "\(fit.lemmas) vs \(truth)")
        #expect(fit.lemmas.contains(truth))
        #expect(fit.knowledge[0] > fit.knowledge[999] && fit.knowledge[999] > fit.knowledge[5999])
        #expect(fit.respond(999, .yesNo) == fit.knowledge[999])
    }

    @Test func simulatedLearnersAreDeterministicAndAnswerByStyle() {
        var o = SimulationOptions()
        o.baselineItems = 300
        o.shortItems = 100
        let a = SimulatedLearner.generate(lexicon: Self.lexicon, theta: 1, style: .honest, seed: 7, label: "a", options: o)
        let b = SimulatedLearner.generate(lexicon: Self.lexicon, theta: 1, style: .honest, seed: 7, label: "a", options: o)
        #expect(a.knows == b.knows && a.observations == b.observations)
        let real = a.observations.filter { $0.pseudo != true && $0.source == .test }
        #expect(real.count == 400)
        #expect(Set(real.map(\.lemma)).count == 400) // no word repeated across sessions
        let pseudo = a.observations.filter { $0.pseudo == true }.count
        #expect(abs(Double(pseudo) / Double(pseudo + real.count) - 0.15) < 0.01)
        #expect(Set(a.observations.compactMap(\.session)).count == 2)

        // Over-claiming says "yes" to unknown words far more often.
        let c = SimulatedLearner.generate(lexicon: Self.lexicon, theta: 1, style: .overclaiming, seed: 7, label: "c",
                                          options: o)
        func yesToUnknown(_ l: SimulatedLearner) -> Double {
            let idx = Dictionary(uniqueKeysWithValues: Self.lexicon.entries.enumerated().map { ($1.lemma, $0) })
            let unknown = l.observations.filter { $0.source == .test && $0.pseudo != true && !l.knows[idx[$0.lemma]!] }
            return Double(unknown.filter { $0.result == "yes" }.count) / Double(unknown.count)
        }
        #expect(yesToUnknown(a) < 0.08 && yesToUnknown(c) > 0.15)
    }

    @Test func evaluationIsRepeatableAndExposesOverclaiming() throws {
        var o = EvalOptions()
        o.folds = 2
        var sim = SimulationOptions()
        sim.thetas = [1.5]
        sim.learnersPerSetting = 2
        sim.baselineItems = 300
        sim.shortItems = 0
        o.simulation = sim
        // "Real" data: one simulated honest Learner's two sessions.
        var s2 = SimulationOptions()
        s2.baselineItems = 300
        s2.shortItems = 150
        let learner = SimulatedLearner.generate(lexicon: Self.lexicon, theta: 1.5, style: .honest, seed: 99,
                                                label: "real", options: s2)
        let models: [any VocabularyModel] = [LegacyProfileModel(name: "current"), FrequencyBaselineModel()]
        let r1 = Evaluation.run(observations: learner.observations, lexicon: Self.lexicon, models: models, options: o)
        let r2 = Evaluation.run(observations: learner.observations, lexicon: Self.lexicon, models: models, options: o)
        #expect(try r1.json() == r2.json())
        #expect(r1.table() == r2.table())

        #expect(r1.models.map(\.model) == ["current", "frequency"])
        for m in r1.models {
            let h = try #require(m.holdout)
            #expect(h.scope == ["sim-real-2"])
            #expect(h.all.auc.map { $0 > 0.7 } == true, "\(m.model) AUC \(String(describing: h.all.auc))")
            #expect(m.crossValidation?.all.n == r1.scorableItems)
            #expect(m.splitHalf.count == 2)
            #expect(m.retest.count == 1)
            let simReport = try #require(m.simulation)
            #expect(simReport.learners.count == 4)
            #expect(simReport.learners.allSatisfy { $0.knowledge.n == 6000 })
        }
        // The frequency baseline has no response layer, so over-claimed "yes" answers inflate its total.
        let freq = try #require(r1.models[1].simulation)
        #expect(freq.overclaiming.meanRelativeBiasFamilies > freq.honest.meanRelativeBiasFamilies + 0.1)

        let table = r1.table()
        #expect(table.contains("| 指标 | 目标 | current | frequency |"))
        #expect(table.contains("留出(按场次) AUC"))
    }

    /// Ticket 02: the two-layer model's intervals cover honest Learners and its word-level P is
    /// calibrated. Over-claimers are still hard (see ticket 02): it covers them more often than the
    /// reference models, which never do, but tends to over-correct.
    @Test func twoLayerModelCoversHonestLearnersAndIsCalibrated() throws {
        let lexicon = syntheticLexicon(count: 20000)
        var o = EvalOptions()
        o.folds = 0
        var sim = SimulationOptions()
        sim.thetas = [2.0]
        sim.learnersPerSetting = 3
        o.simulation = sim
        let models: [any VocabularyModel] = [LegacyProfileModel(), FrequencyBaselineModel(), TwoLayerModel()]
        let r = Evaluation.run(observations: [], lexicon: lexicon, models: models, options: o)
        let legacy = try #require(r.models[0].simulation), freq = try #require(r.models[1].simulation)
        let two = try #require(r.models[2].simulation)
        #expect(two.honest.lemmaCoverage == 1, "\(two.honest)")
        #expect(abs(two.honest.meanRelativeBiasFamilies) < 0.15, "\(two.honest)")
        for ref in [legacy, freq] {
            #expect(two.honest.meanKnowledgeECE < ref.honest.meanKnowledgeECE)
            #expect(two.overclaiming.familyCoverage > ref.overclaiming.familyCoverage)
        }
    }
}
