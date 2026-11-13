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

    /// Short test and Baseline Test share this flow; they differ in size (`TestConfig`) and in
    /// that the Baseline is checkpointed so it can be resumed.
    enum Kind { case short, baseline }

    let kind: Kind

    private(set) var phase: Phase = .preparing
    private(set) var session: TestSession?
    /// Observations recorded in this flow.
    private(set) var recorded = 0
    /// Judgment of the last answer (pseudowords and meaning checks; real words are neutral).
    private(set) var feedback: Feedback?
    /// Live vocabulary estimate (word families) after the answers so far.
    private(set) var liveEstimate: Int?

    private weak var app: AppModel?
    private let lexicon: Lexicon
    private let profile: LearnerProfile
    private let history: [LearnerObservation]
    private let config: TestConfig
    private var shownAt = Date()
    private var started = false
    /// A checkpointed session plus the Observations already stored for it.
    private let resume: (session: TestSession, stored: [LearnerObservation])?

    /// `history`: Observations before this test (defaults to all; a resumed test passes the ones
    /// not belonging to its own session).
    init(app: AppModel, lexicon: Lexicon, profile: LearnerProfile, config: TestConfig = .short, kind: Kind = .short,
         resume: (session: TestSession, stored: [LearnerObservation])? = nil, history: [LearnerObservation]? = nil) {
        self.app = app
        self.lexicon = lexicon
        self.profile = profile
        self.history = history ?? app.observations
        self.config = config
        self.kind = kind
        self.resume = resume
    }

    /// Baseline answers survive ✕; the view asks before leaving.
    var confirmsExit: Bool {
        guard kind == .baseline else { return false }
        if case .question = phase { return true }
        return false
    }

    var progress: Double {
        guard let p = session?.progress, p.total > 0 else { return 0 }
        return Double(p.answered) / Double(p.total)
    }

    /// Number of segments in the answer screen's progress bar.
    static let segments = 10

    /// Progress-bar segments completely filled so far.
    var segmentsFilled: Int { min(Self.segments, Int((progress * Double(Self.segments)).rounded(.down))) }

    func start() async {
        // `.task` can run again (e.g. when the cover is re-presented); start only once.
        guard session == nil, !started else { return }
        started = true
        if let checkpoint = resume?.session, let stored = resume?.stored {
            // Resume: replay what was already stored; these are not recorded again.
            let lexicon = lexicon
            let (s, applied) = await Task.detached(priority: .userInitiated) {
                var s = checkpoint
                s.attach(lexicon)
                let applied = s.replay(stored)
                return (s, applied)
            }.value
            recorded = applied
            session = s
            liveEstimate = s.estimate.map { Int($0.estimate.rounded()) }
            advance()
            return
        }
        let (lexicon, profile, history, config) = (lexicon, profile, history, config)
        let id = Clock.sessionID(Date())
        let seed = UInt64.random(in: 0...UInt64.max)
        let s = await Task.detached(priority: .userInitiated) {
            TestSession(lexicon: lexicon, profile: profile, history: history, config: config, sessionID: id, seed: seed)
        }.value
        if kind == .baseline {
            do {
                try app?.baselineCreated(s)
            } catch {
                phase = .failed("保存失败：\(error)")
                return
            }
        }
        session = s
        liveEstimate = s.estimate.map { Int($0.estimate.rounded()) }
        advance()
    }

    /// Records the answer to the current item and moves on; returns the judgment to show.
    @discardableResult
    func answer(_ answer: TestAnswer) -> Feedback {
        guard var s = session, case .question = phase else { return .neutral }
        let now = Date()
        let rt = Int(now.timeIntervalSince(shownAt) * 1000)
        let outcome = s.answer(answer, rtMs: rt, at: Clock.iso(now))
        session = s
        feedback = outcome.feedback
        liveEstimate = s.estimate.map { Int($0.estimate.rounded()) }
        do {
            try app?.record(outcome.observation)
            recorded += 1
        } catch {
            phase = .failed("保存失败：\(error)")
            return outcome.feedback
        }
        advance()
        return outcome.feedback
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
        if kind == .baseline { try? app?.baselineFinished(session: s.sessionID) }
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
        // `LE_AUTOPLAY_STOP_BEFORE=pseudoword|meaning`: stop (after the first 20) at such an item.
        let stopBefore = ProcessInfo.processInfo.environment["LE_AUTOPLAY_STOP_BEFORE"]
        var pseudo = 0
        while case .question(let item) = phase, recorded < stopAt {
            if recorded >= 20, let stopBefore {
                switch item {
                case .yesNo(let q) where q.kind == .pseudoword && stopBefore == "pseudoword": return
                case .meaningCheck where stopBefore == "meaning": return
                default: break
                }
            }
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
