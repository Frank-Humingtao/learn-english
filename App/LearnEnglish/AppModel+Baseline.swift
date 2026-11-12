import Foundation
import TestEngine

/// First launch (onboarding) and the Baseline Test: start, resume, redo.
extension AppModel {
    private static let onboardingKey = "onboarding.completed"

    /// Welcome → PAT → Baseline intro has been gone through once on this install.
    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Self.onboardingKey) }
        set { defaults.set(newValue, forKey: Self.onboardingKey) }
    }

    /// Presents onboarding on a fresh install; afterwards never again.
    ///
    /// Keychain items outlive an uninstall, so on the first launch of a fresh install any token
    /// left behind by an earlier install is removed (UserDefaults are wiped with the app).
    func presentOnboardingIfNeeded() {
        let installKey = "install.initialized"
        if !defaults.bool(forKey: installKey) {
            try? tokenStore.delete()
            defaults.set(true, forKey: installKey)
        }
        guard !onboardingCompleted, presentedFlow == nil else { return }
        presentedFlow = .onboarding(OnboardingModel(app: self))
    }

    /// A Baseline Test was started and not finished: the next one resumes it.
    var baselinePending: Bool { baseline.map { !$0.isCompleted } ?? false }

    /// Answers stored so far for the pending Baseline Test.
    var baselineAnswered: Int {
        guard let b = baseline else { return 0 }
        return observations.lazy.filter { $0.session == b.session }.count
    }

    /// Starts a new Baseline Test, or resumes the pending one. `redo` always starts a new one
    /// (the old, unfinished one is simply superseded; its answers stay as Observations).
    func startBaseline(redo: Bool = false) {
        guard let lexicon, let profile else { return }
        if !redo, let pending = baseline, !pending.isCompleted, let session = try? pending.testSession() {
            let stored = observations.filter { $0.session == pending.session }
            let history = observations.filter { $0.session != pending.session }
            presentedFlow = .test(TestFlowModel(app: self, lexicon: lexicon, profile: profile, config: .baseline,
                                                kind: .baseline, resume: (session, stored), history: history))
        } else {
            presentedFlow = .test(TestFlowModel(app: self, lexicon: lexicon, profile: profile, config: .baseline,
                                                kind: .baseline))
        }
    }

    /// Called by the test flow right after creating a Baseline session, before the first answer.
    func baselineCreated(_ session: TestSession) throws {
        let c = try TestCheckpoint(session: session, kind: .baseline, createdAt: Clock.iso(Date()))
        try database.save(c)
        baseline = c
    }

    /// Called by the test flow when the last Baseline item was answered.
    func baselineFinished(session: String) throws {
        let ts = Clock.iso(Date())
        try database.markCheckpointCompleted(session: session, at: ts)
        if baseline?.session == session { baseline?.completed_at = ts }
    }
}
