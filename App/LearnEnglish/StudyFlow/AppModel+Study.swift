import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import StudyComposer

/// Card study (ticket 07): session composition, 加词, daily limit, Leeches.
///
/// Everything here is derived from `observations`; the only writes go through `record(_:)`.
extension AppModel {
    /// FSRS-6, retention 0.9; personal weights from `fsrs/params.json` once synced (ticket 10),
    /// FSRS-6 defaults until then.
    var studyComposer: StudyComposer {
        StudyComposer(scheduler: CardScheduler(config: sync.fsrsParams.config))
    }

    /// The hand-written sample plan bundled with the app (same schema as `plan/YYYY-MM-DD.json`).
    /// DEBUG only, and only with `LE_SAMPLE_PLAN=1` until a real plan has been pulled.
    static let samplePlan: StudyPlan? = Bundle.main.url(forResource: "sample-plan", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(StudyPlan.self, from: $0) }

    /// Source of new cards: the newest `plan/YYYY-MM-DD.json` pulled from english-data.
    var studyPlan: StudyPlan? {
        #if DEBUG
        if plans.plan == nil, ProcessInfo.processInfo.environment["LE_SAMPLE_PLAN"] != nil { return Self.samplePlan }
        #endif
        return plans.plan
    }

    /// 每日新词上限 (latest `setting` Observation, or the default).
    var dailyNewLimit: Int { StudySettings.dailyNewLimit(from: observations) }

    /// What a study session started now would contain (nil until the lexicon and profile load).
    func composeStudy(now: Date = Date()) -> StudySession? {
        guard let lexicon, let profile else { return nil }
        return studyComposer.compose(
            observations: observations, plan: studyPlan, dailyNewLimit: dailyNewLimit,
            isMastered: { profile.band(of: $0) == .mastered },
            isKnownLemma: { lexicon.entry(lemma: $0) != nil },
            now: now, calendar: .current, sessionID: Clock.sessionID(now), lexiconVersion: lexicon.version)
    }

    func startStudy() {
        guard let lexicon, let session = composeStudy() else { return }
        presentedFlow = .study(StudyFlowModel(app: self, lexicon: lexicon, session: session))
    }

    /// Paused Leeches, for the 进度 tab (ticket 09).
    var leeches: [Leech] {
        studyComposer.ledger(observations: observations, now: Date()).leeches
    }

    /// 重新学: the Leech restarts as a new card at the front of today's new cards (counts toward the limit).
    func relearn(_ lemma: String) throws {
        try record(StudyObservations.relearn(lemma, at: Date()))
    }

    enum AddWordError: LocalizedError {
        case notInLexicon(String)
        var errorDescription: String? {
            switch self {
            case .notInLexicon(let w): "词库里没有「\(w)」"
            }
        }
    }

    /// 加词: records a `wish` Observation for the word's lemma and returns the lemma.
    @discardableResult
    func addWish(_ word: String) throws -> String {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lemma = lexicon?.lemma(for: w) else { throw AddWordError.notInLexicon(w) }
        try record(StudyObservations.wish(lemma, at: Date(), lexiconVersion: lexicon?.version))
        return lemma
    }

    /// Words added with 加词, newest first, without repeats.
    var wishes: [String] {
        var seen = Set<String>()
        return observations.reversed().filter { $0.source == .wish && seen.insert($0.lemma).inserted }.map(\.lemma)
    }

    func setDailyNewLimit(_ limit: Int) throws {
        guard limit != dailyNewLimit else { return }
        try record(StudyObservations.dailyNewLimit(limit, at: Date()))
    }

    #if DEBUG
    /// Simulator hook (`LE_SEED_REVIEWS=1`): the first 3 sample-plan words learned 5 days ago, so
    /// a session has due reviews before the new cards. Writes real Observations; DEBUG only.
    func seedReviewsIfRequested() {
        guard ProcessInfo.processInfo.environment["LE_SEED_REVIEWS"] != nil,
              !observations.contains(where: { $0.source == .review }),
              let words = studyPlan?.newWords.prefix(3).map(\.lemma) else { return }
        let start = Date().addingTimeInterval(-5 * 86400)
        for (i, w) in words.enumerated() {
            for (k, grade) in [Grade.good, .good].enumerated() {
                let t = start.addingTimeInterval(Double(i * 60 + k * 15 * 60))
                try? record(Observation(ts: Clock.iso(t), lemma: w, source: .review, result: grade.result,
                                        session: "seed", lexicon: lexicon?.version))
            }
        }
    }
    #endif
}
