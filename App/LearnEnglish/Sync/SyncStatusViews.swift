import SwiftUI
import SyncCore

/// Sync status appears only when something is wrong: a one-line red banner at the top of a tab.
/// Tapping it opens 设置. Pending or offline uploads are normal and show nothing.
struct SyncErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.sync.errorMessage {
            Button { model.selectedTab = .settings } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("同步失败 · \(message)").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.bad)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.badSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .accessibilityIdentifier("tokenErrorBar")
        }
    }
}

extension SyncModel {
    /// Short reason when sync is failing; nil while it works (or merely waits for the network).
    var errorMessage: String? {
        switch status {
        case .tokenError(let problem): problem.reason
        case .pending where state.lastError != nil: "稍后重试"
        case .synced, .pending, .offline: nil
        }
    }
}

extension TokenProblem {
    var reason: String {
        switch self {
        case .missing: "未设置令牌"
        case .rejected: "令牌无效"
        case .expired: "令牌已过期"
        case .noAccess: "令牌无权访问 english-data"
        }
    }
}
