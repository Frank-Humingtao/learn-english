import SwiftUI
import SyncCore

extension View {
    /// Sync status on a tab page: "未同步 N 条" / offline note in the nav bar's top-right,
    /// and the persistent red token-error bar at the top. Apply inside the tab's NavigationStack.
    func syncStatusChrome() -> some View {
        modifier(SyncStatusChrome())
    }
}

private struct SyncStatusChrome: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if case .tokenError(let problem) = model.sync.status {
                    TokenErrorBar(problem: problem) { model.selectedTab = .settings }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SyncBadge()
                }
            }
    }
}

/// Nav-bar item: nothing when synced; tappable "未同步 N 条"; grey offline note.
struct SyncBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.sync.status {
        case .synced, .tokenError:
            EmptyView()
        case .pending(let n):
            Button {
                Task { await model.sync.syncNow() }
            } label: {
                if model.sync.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("未同步 \(n) 条").font(.footnote)
                }
            }
            .accessibilityIdentifier("syncPending")
        case .offline:
            Text("离线中，联网后自动同步")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("syncOffline")
        }
    }
}

struct TokenErrorBar: View {
    let problem: TokenProblem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.reason).font(.subheadline.weight(.semibold))
                    Text("无法同步，记录都还在本机。点此去设置。").font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red, ignoresSafeAreaEdges: [])
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tokenErrorBar")
    }
}

extension TokenProblem {
    var reason: String {
        switch self {
        case .missing: "还没有设置 GitHub 令牌"
        case .rejected: "GitHub 令牌无效或已被撤销"
        case .expired: "GitHub 令牌已过期"
        case .noAccess: "令牌无权访问 english-data 仓库"
        }
    }
}

/// 设置 › 同步: status, outbox size, last success, repo, sync now, replace PAT + expiry.
struct SyncSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var newToken = ""
    @State private var replacing = false
    @State private var tokenMessage: String?

    var body: some View {
        let sync = model.sync
        Section("同步") {
            LabeledContent("状态", value: statusText(sync.status))
            LabeledContent("未同步", value: "\(sync.pendingCount) 条")
            LabeledContent("上次成功") {
                if let d = sync.state.lastSuccess {
                    Text(d, format: .dateTime.month().day().hour().minute())
                } else {
                    Text("从未")
                }
            }
            LabeledContent("仓库", value: sync.repoDisplayName)
            if let error = sync.state.lastError, case .pending = sync.status {
                Text("上次失败：\(error)").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { await sync.syncNow() }
            } label: {
                HStack {
                    Text("立即同步")
                    if sync.isSyncing { Spacer(); ProgressView() }
                }
            }
            .disabled(sync.isSyncing || !sync.hasToken)
            .accessibilityIdentifier("syncNow")
        }
        Section {
            LabeledContent("令牌", value: sync.hasToken ? "已保存在钥匙串" : "未设置")
            if sync.hasToken {
                LabeledContent("有效期至") {
                    if let d = sync.state.tokenExpiresAt {
                        Text(d, format: .dateTime.year().month().day())
                    } else {
                        Text("未知或永不过期")
                    }
                }
            }
            SecureField("粘贴新的 fine-grained PAT", text: $newToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(sync.hasToken ? "替换令牌" : "保存令牌") {
                replacing = true
                tokenMessage = nil
                Task {
                    do {
                        try await sync.replaceToken(newToken)
                        newToken = ""
                        tokenMessage = "已保存，正在补交未同步的记录"
                    } catch {
                        tokenMessage = error.localizedDescription
                    }
                    replacing = false
                }
            }
            .disabled(newToken.isEmpty || replacing)
            if let tokenMessage {
                Text(tokenMessage).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("GitHub 令牌")
        } footer: {
            Text("只授权 english-data 仓库 Contents 读写。令牌只存在本机钥匙串。")
        }
    }

    private func statusText(_ status: SyncStatus) -> String {
        switch status {
        case .synced: "已同步"
        case .pending(let n): "未同步 \(n) 条"
        case .offline: "离线中，联网后自动同步"
        case .tokenError(let p): p.reason
        }
    }
}
