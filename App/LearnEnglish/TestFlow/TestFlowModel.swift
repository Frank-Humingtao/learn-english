import Foundation
import Lexicon
import Observation
import ProfileEngine
import TestEngine

/// Drives one Vocabulary Test: builds a `TestSession` from the current profile, stores every
/// answer as an Observation the moment it is given, and computes the result locally at the end.
@Observable @MainActor
final class TestFlowModel {
    enum Phase {
        case preparing
        case question(TestItem)
        case computingResult
        case result(TestResult)
        case failed(String)
    }

    private(set) var phase: Phase = .preparing
    private(set) var session: TestSession?
    /// Observations recorded in this flow.
    private(set) var recorded = 0

    private weak var app: AppModel?
    private let lexicon: Lexicon
    private let profile: LearnerProfile
    private let history: [LearnerObservation]
    private let config: TestConfig
    private var shownAt = Date()

    init(app: AppModel, lexicon: Lexicon, profile: LearnerProfile, config: TestConfig = .short) {
        self.app = app
        self.lexicon = lexicon
        self.profile = profile
        self.history = app.observations
        self.config = config
    }

    var title: String { "今日短测" }

    var progress: Double {
        guard let p = session?.progress, p.total > 0 else { return 0 }
        return Double(p.answered) / Double(p.total)
    }

    /// Rough minutes left at ~2.5 s per item.
    var minutesLeft: Int {
        guard let p = session?.progress else { return 0 }
        return max(1, Int((Double(p.total - p.answered) * 2.5 / 60).rounded(.up)))
    }

    func start() async {
        guard session == nil else { return }
        let (lexicon, profile, history, config) = (lexicon, profile, history, config)
        let id = Clock.sessionID(Date())
        let seed = UInt64.random(in: 0...UInt64.max)
        let s = await Task.detached(priority: .userInitiated) {
            TestSession(lexicon: lexicon, profile: profile, history: history, config: config, sessionID: id, seed: seed)
        }.value
        session = s
        advance()
    }

    func answer(_ answer: TestAnswer) {
        guard var s = session, case .question = phase else { return }
        let now = Date()
        let rt = Int(now.timeIntervalSince(shownAt) * 1000)
        let o = s.answer(answer, rtMs: rt, at: Clock.iso(now))
        session = s
        do {
            try app?.record(o)
            recorded += 1
        } catch {
            phase = .failed("保存失败：\(error)")
            return
        }
        advance()
    }

    private func advance() {
        guard let s = session else { return }
        if let item = s.current {
            phase = .question(item)
            shownAt = Date()
        } else {
            Task { await finish() }
        }
    }

    private func finish() async {
        guard let s = session else { return }
        phase = .computingResult
        let (history, lexicon) = (history, lexicon)
        let result = await Task.detached(priority: .userInitiated) {
            TestResult(history: history, session: s.observations, lexicon: lexicon)
        }.value
        app?.update(profile: result.profile)
        phase = .result(result)
        app?.sessionEnded()
    }

    /// ✕ or 完成. Answers are already stored; the profile is refreshed if the test was cut short.
    func close() {
        guard let app else { return }
        if case .result = phase {} else if recorded > 0 {
            Task { await app.recomputeProfile() }
        }
        app.dismissFlow()
    }

    #if DEBUG
    /// `LE_AUTOPLAY=1` (simulator verification only): answers like a learner who knows the
    /// 6,000 most frequent lemmas and says yes to every ninth pseudoword, one item per 0.15 s.
    func autoplayIfRequested() async {
        guard ProcessInfo.processInfo.environment["LE_AUTOPLAY"] != nil else { return }
        let stopAt = Int(ProcessInfo.processInfo.environment["LE_AUTOPLAY_STOP_AT"] ?? "") ?? .max
        var pseudo = 0
        while case .question(let item) = phase, recorded < stopAt {
            try? await Task.sleep(for: .milliseconds(150))
            let known = { (w: String) in (self.lexicon.entry(lemma: w)?.rank ?? .max) <= 6000 }
            switch item {
            case .yesNo(let q):
                if q.kind == .pseudoword {
                    pseudo += 1
                    answer(.yesNo(pseudo % 9 == 0))
                } else {
                    answer(.yesNo(known(q.word)))
                }
            case .meaningCheck(let q):
                answer(.meaning(known(q.lemma) ? q.correctIndex : nil))
            }
        }
    }
    #endif
}
