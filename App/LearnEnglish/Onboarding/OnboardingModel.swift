import Foundation
import Observation

/// First launch: welcome → paste the GitHub PAT (skippable) → Baseline Test intro.
/// Leaving the last step (start or later) marks onboarding done, so it never shows again.
@Observable @MainActor
final class OnboardingModel {
    enum Step: Int { case welcome, token, baseline }

    private(set) var step: Step = .welcome
    var tokenInput = ""
    private(set) var tokenError: String?
    /// Whether a token was saved in this onboarding (no token value is kept here).
    private(set) var tokenSaved = false

    private weak var app: AppModel?

    init(app: AppModel) {
        self.app = app
        tokenSaved = app.tokenStore.hasToken
    }

    func next() {
        if step == .welcome { step = .token }
    }

    /// Validates the pasted text's shape and stores it in the Keychain. The input is cleared
    /// right away so the token does not linger in memory longer than needed.
    func saveToken() {
        guard let app else { return }
        guard let token = PATFormat.normalized(tokenInput) else {
            tokenError = "这看起来不像 GitHub 令牌（应以 github_pat_ 开头）。"
            return
        }
        do {
            try app.tokenStore.save(token)
            tokenInput = ""
            tokenError = nil
            tokenSaved = true
            step = .baseline
        } catch {
            tokenError = "保存到钥匙串失败：\(error)"
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
