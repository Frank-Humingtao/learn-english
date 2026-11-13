import Foundation
import Observation

/// First launch: paste the GitHub PAT (skippable) → start the Baseline Test.
/// Leaving the last step (start or later) marks onboarding done, so it never shows again.
@Observable @MainActor
final class OnboardingModel {
    enum Step: Int { case token, baseline }

    private(set) var step: Step = .token
    var tokenInput = ""
    private(set) var tokenError: String?
    /// Whether a token was saved in this onboarding (no token value is kept here).
    private(set) var tokenSaved = false

    private weak var app: AppModel?

    init(app: AppModel) {
        self.app = app
        tokenSaved = app.tokenStore.readToken() != nil
    }

    /// Validates the pasted text's shape and stores it in the Keychain. The input is cleared
    /// right away so the token does not linger in memory longer than needed.
    func saveToken() {
        guard let app else { return }
        guard let token = PATFormat.normalized(tokenInput) else {
            tokenError = "不是 github_pat_ 令牌"
            return
        }
        do {
            try app.tokenStore.saveToken(token)
            app.sync.tokenChanged()
            tokenInput = ""
            tokenError = nil
            tokenSaved = true
            step = .baseline
        } catch {
            tokenError = "保存失败"
        }
    }

    func skipToken() {
        tokenInput = ""
        tokenError = nil
        step = .baseline
    }

    var canStartBaseline: Bool { app?.isLoaded ?? false }

    func startBaseline() {
        guard let app, app.isLoaded else { return }
        app.onboardingCompleted = true
        app.selectedTab = .test
        app.startBaseline()
    }

    func later() {
        guard let app else { return }
        app.onboardingCompleted = true
        app.selectedTab = .test
        app.dismissFlow()
    }
}
