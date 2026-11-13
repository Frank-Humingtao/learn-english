import CoreModels
import Foundation
import Lexicon

public struct EvalOptions: Sendable, Equatable {
    /// Folds of the word-level cross-validation (0 turns it off).
    public var folds = 10
    /// Split-half and session retest need at least this many scorable items per half / session.
    public var minItems = 20
    /// Sessions further apart than this are not compared for retest consistency.
    public var retestMaxDays = 7.0
    /// nil: no simulated Learners.
    public var simulation: SimulationOptions? = SimulationOptions()

    public init() {}
}

// MARK: report

/// Prediction scores overall and by item kind.
public struct PredictionReport: Codable, Sendable, Equatable {
    public var all: Scores
    public var yesNo: Scores?
    public var verify: Scores?
    /// What was predicted: session ids (sequential holdout) or folds.
    public var scope: [String]
}

public struct SplitHalfResult: Codable, Sendable, Equatable {
    public var session: String
    public var itemsA: Int
    public var itemsB: Int
    public var familiesA: Interval
    public var familiesB: Interval
    public var lemmasA: Interval
    public var lemmasB: Interval
    /// |A − B| (families) ≤ 1.96·√(seA² + seB²).
    public var consistent: Bool
}

public struct SessionRetestResult: Codable, Sendable, Equatable {
    public var sessionA: String
    public var sessionB: String
    public var days: Double
    public var familiesA: Interval
    public var familiesB: Interval
    public var consistent: Bool
}

public struct SimulatedResult: Codable, Sendable, Equatable {
    public var learner: String
    public var style: AnswerStyle
    public var trueLemmas: Int
    public var trueFamilies: Int
    public var lemmas: Interval
    public var families: Interval
    public var lemmasCovered: Bool
    public var familiesCovered: Bool
    /// Published P(known) against the true knowledge state of every lexicon word.
    public var knowledge: Scores
}

public struct SimulationSummary: Codable, Sendable, Equatable {
    public var learners: Int
    /// Share of Learners whose true total lies inside the 95% interval.
    public var lemmaCoverage: Double
    public var familyCoverage: Double
    /// Mean |estimate − truth| / truth.
    public var meanAbsRelativeErrorLemmas: Double
    public var meanAbsRelativeErrorFamilies: Double
    /// Mean signed (estimate − truth) / truth: > 0 means overestimation.
    public var meanRelativeBiasFamilies: Double
    public var meanRelativeHalfWidthFamilies: Double
    public var meanKnowledgeLogLoss: Double
    public var meanKnowledgeECE: Double
}

public struct SimulationReport: Codable, Sendable, Equatable {
    public var all: SimulationSummary
    public var honest: SimulationSummary
    public var overclaiming: SimulationSummary
    public var learners: [SimulatedResult]
}

public struct ModelReport: Codable, Sendable, Equatable {
    public var model: String
    /// Each session predicted from the Observations before it.
    public var holdout: PredictionReport?
    /// Words split into folds; each fold's answers predicted from all other Observations.
    public var crossValidation: PredictionReport?
    /// Fitted on all Observations.
    public var lemmas: Interval?
    public var families: Interval?
    public var splitHalf: [SplitHalfResult]
    public var retest: [SessionRetestResult]
    public var simulation: SimulationReport?
}

public struct SessionSummary: Codable, Sendable, Equatable {
    public var id: String
    public var start: String
    public var yesNo: Int
    public var verify: Int
    public var pseudowords: Int
    /// Pseudowords answered "yes" / pseudowords.
    public var falseAlarmRate: Double?
}

public struct WordRetest: Codable, Sendable, Equatable {
    /// Pairs of Yes/No answers to the same word in two sessions at most `retestMaxDays` apart.
    public var pairs: Int
    public var agreement: Double?
}

public struct EvalReport: Codable, Sendable, Equatable {
    public var lexicon: String
    public var observations: Int
    public var scorableItems: Int
    public var sessions: [SessionSummary]
    public var wordRetest: WordRetest
    public var models: [ModelReport]
}

// MARK: runner

public enum Evaluation {
    public static func run(observations: [Observation], lexicon: Lexicon, models: [any VocabularyModel],
                           options: EvalOptions = EvalOptions()) -> EvalReport {
        let sessions = Session.group(observations, lexicon: lexicon)
        let items = ScoredItem.extract(observations, lexicon: lexicon)
        let simulated = options.simulation.map { SimulatedLearner.population(lexicon: lexicon, options: $0) } ?? []

        let reports = models.map { model in
            let full = items.isEmpty ? nil : model.fit(observations: observations, lexicon: lexicon)
            return ModelReport(
                model: model.name,
                holdout: holdout(model, observations, lexicon, sessions),
                crossValidation: options.folds > 1 ? crossValidation(model, observations, lexicon, folds: options.folds) : nil,
                lemmas: full?.lemmas, families: full?.families,
                splitHalf: splitHalf(model, observations, lexicon, sessions, minItems: options.minItems),
                retest: sessionRetest(model, observations, lexicon, sessions, options: options),
                simulation: simulated.isEmpty ? nil : simulation(model, simulated, lexicon))
        }
        return EvalReport(
            lexicon: lexicon.version, observations: observations.count, scorableItems: items.count,
            sessions: sessions.map { s in
                let pseudo = s.observations.filter { observations[$0].pseudo == true }
                let fa = pseudo.filter { observations[$0].result == ObservationResult.yes }.count
                return SessionSummary(id: s.id, start: Timestamp.iso(s.start),
                                      yesNo: s.items.filter { $0.kind == .yesNo }.count,
                                      verify: s.items.filter { $0.kind == .verify }.count,
                                      pseudowords: pseudo.count,
                                      falseAlarmRate: pseudo.isEmpty ? nil : rounded(Double(fa) / Double(pseudo.count)))
            },
            wordRetest: wordRetest(observations, sessions, maxDays: options.retestMaxDays),
            models: reports)
    }

    /// Predictions and outcomes → scores overall and by kind.
    static func report(_ scored: [(item: ScoredItem, p: Double)], scope: [String]) -> PredictionReport? {
        guard let all = Scores(predictions: scored.map(\.p), outcomes: scored.map(\.item.y)) else { return nil }
        func kind(_ k: ItemKind) -> Scores? {
            let s = scored.filter { $0.item.kind == k }
            return Scores(predictions: s.map(\.p), outcomes: s.map(\.item.y))
        }
        return PredictionReport(all: all, yesNo: kind(.yesNo), verify: kind(.verify), scope: scope)
    }

    /// Sequential holdout: each session with scorable items, predicted by a fit on every Observation
    /// strictly before the session's start. Sessions without any earlier scorable evidence are skipped.
    static func holdout(_ model: any VocabularyModel, _ observations: [Observation], _ lexicon: Lexicon,
                        _ sessions: [Session]) -> PredictionReport? {
        var scored: [(item: ScoredItem, p: Double)] = []
        var scope: [String] = []
        for s in sessions where !s.items.isEmpty {
            let history = observations.filter { o in Timestamp.epochSeconds(o.ts).map { $0 < s.start } ?? false }
            guard !ScoredItem.extract(history, lexicon: lexicon).isEmpty else { continue }
            let fit = model.fit(observations: history, lexicon: lexicon)
            scored += s.items.map { ($0, fit.respond($0.entry, $0.kind)) }
            scope.append(s.id)
        }
        return report(scored, scope: scope)
    }

    /// Word-level K-fold: words (lemmas) are hashed into folds; every answer about a fold's words is
    /// predicted by a fit on all other Observations (pseudowords always stay in training).
    static func crossValidation(_ model: any VocabularyModel, _ observations: [Observation], _ lexicon: Lexicon,
                                folds: Int) -> PredictionReport? {
        func fold(_ o: Observation) -> Int? {
            guard o.pseudo != true, let lemma = lexicon.lemma(for: o.lemma) else { return nil }
            return Int(stableHash(lemma) % UInt64(folds))
        }
        let items = ScoredItem.extract(observations, lexicon: lexicon)
        var scored: [(item: ScoredItem, p: Double)] = []
        var scope: [String] = []
        for k in 0..<folds {
            let test = items.filter { fold(observations[$0.observation]) == k }
            guard !test.isEmpty else { continue }
            let train = observations.filter { fold($0) != k }
            let fit = model.fit(observations: train, lexicon: lexicon)
            scored += test.map { ($0, fit.respond($0.entry, $0.kind)) }
            scope.append("fold \(k + 1)/\(folds)")
        }
        return report(scored, scope: scope)
    }

    /// Each session split into two halves by alternating words in order of first appearance (a
    /// meaning check stays with its Yes/No answer; pseudowords alternate too); each half fitted alone.
    static func splitHalf(_ model: any VocabularyModel, _ observations: [Observation], _ lexicon: Lexicon,
                          _ sessions: [Session], minItems: Int) -> [SplitHalfResult] {
        sessions.compactMap { s in
            var half: [String: Int] = [:]
            var a: [Observation] = [], b: [Observation] = []
            for i in s.observations {
                let o = observations[i]
                let key = o.pseudo == true ? "pseudo:" + o.lemma : (lexicon.lemma(for: o.lemma) ?? o.lemma)
                if half[key] == nil { half[key] = half.count % 2 }
                if half[key] == 0 { a.append(o) } else { b.append(o) }
            }
            let na = ScoredItem.extract(a, lexicon: lexicon).count, nb = ScoredItem.extract(b, lexicon: lexicon).count
            guard na >= minItems, nb >= minItems else { return nil }
            let fa = model.fit(observations: a, lexicon: lexicon), fb = model.fit(observations: b, lexicon: lexicon)
            return SplitHalfResult(session: s.id, itemsA: na, itemsB: nb, familiesA: fa.families, familiesB: fb.families,
                                   lemmasA: fa.lemmas, lemmasB: fb.lemmas,
                                   consistent: agree(fa.families, fb.families))
        }
    }

    /// Consecutive sessions at most `retestMaxDays` apart, each fitted on its own Observations.
    static func sessionRetest(_ model: any VocabularyModel, _ observations: [Observation], _ lexicon: Lexicon,
                              _ sessions: [Session], options: EvalOptions) -> [SessionRetestResult] {
        let usable = sessions.filter { $0.items.count >= options.minItems }
        guard usable.count >= 2 else { return [] }
        var fits: [String: ModelFit] = [:]
        func fit(_ s: Session) -> ModelFit {
            if let f = fits[s.id] { return f }
            let f = model.fit(observations: s.observations.map { observations[$0] }, lexicon: lexicon)
            fits[s.id] = f
            return f
        }
        var out: [SessionRetestResult] = []
        for (x, y) in zip(usable, usable.dropFirst()) {
            let days = (y.start - x.start) / 86400
            guard days <= options.retestMaxDays else { continue }
            let fx = fit(x), fy = fit(y)
            out.append(SessionRetestResult(sessionA: x.id, sessionB: y.id, days: rounded(days),
                                           familiesA: fx.families, familiesB: fy.families,
                                           consistent: agree(fx.families, fy.families)))
        }
        return out
    }

    static func agree(_ a: Interval, _ b: Interval) -> Bool {
        abs(a.estimate - b.estimate) <= 1.96 * sqrt(a.standardError * a.standardError + b.standardError * b.standardError)
    }

    /// Same-word Yes/No agreement across sessions (model-free).
    static func wordRetest(_ observations: [Observation], _ sessions: [Session], maxDays: Double) -> WordRetest {
        var answers: [String: [(start: Double, session: String, y: Bool)]] = [:]
        for s in sessions {
            for i in s.observations {
                let o = observations[i]
                guard o.pseudo != true, o.source == .test || o.source == .spotcheck,
                      o.result == ObservationResult.yes || o.result == ObservationResult.no else { continue }
                answers[o.lemma.lowercased(), default: []].append((s.start, s.id, o.result == ObservationResult.yes))
            }
        }
        var pairs = 0, agreeing = 0
        for list in answers.values {
            for (x, y) in zip(list, list.dropFirst()) where x.session != y.session && (y.start - x.start) / 86400 <= maxDays {
                pairs += 1
                if x.y == y.y { agreeing += 1 }
            }
        }
        return WordRetest(pairs: pairs, agreement: pairs > 0 ? rounded(Double(agreeing) / Double(pairs)) : nil)
    }

    static func simulation(_ model: any VocabularyModel, _ learners: [SimulatedLearner],
                           _ lexicon: Lexicon) -> SimulationReport {
        let results = learners.map { l -> SimulatedResult in
            let fit = model.fit(observations: l.observations, lexicon: lexicon)
            let tl = l.trueLemmas, tf = l.trueFamilies(lexicon)
            return SimulatedResult(learner: l.label, style: l.style, trueLemmas: tl, trueFamilies: tf,
                                   lemmas: fit.lemmas, families: fit.families,
                                   lemmasCovered: fit.lemmas.contains(Double(tl)),
                                   familiesCovered: fit.families.contains(Double(tf)),
                                   knowledge: Scores(predictions: fit.knowledge, outcomes: l.knows.map { $0 ? 1 : 0 })!)
        }
        func summary(_ rs: [SimulatedResult]) -> SimulationSummary {
            let n = Double(max(1, rs.count))
            func mean(_ f: (SimulatedResult) -> Double) -> Double { rounded(rs.map(f).reduce(0, +) / n) }
            return SimulationSummary(
                learners: rs.count,
                lemmaCoverage: mean { $0.lemmasCovered ? 1 : 0 },
                familyCoverage: mean { $0.familiesCovered ? 1 : 0 },
                meanAbsRelativeErrorLemmas: mean { abs($0.lemmas.estimate - Double($0.trueLemmas)) / Double(max(1, $0.trueLemmas)) },
                meanAbsRelativeErrorFamilies: mean { abs($0.families.estimate - Double($0.trueFamilies)) / Double(max(1, $0.trueFamilies)) },
                meanRelativeBiasFamilies: mean { ($0.families.estimate - Double($0.trueFamilies)) / Double(max(1, $0.trueFamilies)) },
                meanRelativeHalfWidthFamilies: mean { $0.families.relativeHalfWidth },
                meanKnowledgeLogLoss: mean { $0.knowledge.logLoss },
                meanKnowledgeECE: mean { $0.knowledge.ece })
        }
        return SimulationReport(all: summary(results), honest: summary(results.filter { $0.style == .honest }),
                                overclaiming: summary(results.filter { $0.style == .overclaiming }),
                                learners: results)
    }
}
