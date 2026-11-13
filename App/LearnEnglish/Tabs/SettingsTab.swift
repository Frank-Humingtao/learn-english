import SwiftUI

/// 设置 tab: the GitHub token and 重做基线测试. Sync status shows only as the error banner.
struct SettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var editingToken = false
    @State private var confirmingRedo = false
    @State private var ownerDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            SyncErrorBanner()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("设置").font(.system(size: 28, weight: .heavy)).padding(.top, 12)
                    Button { editingToken = true } label: {
                        row("令牌", value: model.maskedToken ?? "未设置")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tokenRow")
                    if model.publicOwner == nil {
                        HStack {
                            Text("GitHub")
                            TextField("用户名", text: $ownerDraft)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .onSubmit { model.setPublicOwner(ownerDraft) }
                        }
                        .font(.system(size: 16))
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button { confirmingRedo = true } label: {
                        Text("重做基线测试")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.bad)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isLoaded)
                    .accessibilityIdentifier("redoBaseline")
                    .alert("重做基线测试？", isPresented: $confirmingRedo) {
                        Button("开始") { model.startBaseline(redo: true) }
                            .accessibilityIdentifier("confirmRedo")
                        Button("取消", role: .cancel) {}
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $editingToken) { TokenSheet() }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Theme.muted).monospaced()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.line)
        }
        .font(.system(size: 16))
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Paste a new token; GitHub validates it before it replaces the old one.
private struct TokenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("令牌").font(.system(size: 22, weight: .heavy)).padding(.top, 24)
            TokenField(text: $token)
            if let error {
                Text(error).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.bad)
            }
            Spacer()
            Button {
                saving = true
                error = nil
                Task {
                    do {
                        try await model.sync.replaceToken(token)
                        token = ""
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                    saving = false
                }
            } label: {
                if saving { ProgressView().tint(.white) } else { Text("保存") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(token.isEmpty || saving)
        }
        .padding(16)
        .background(Theme.background)
        .presentationDetents([.medium])
    }
}

/// Secure paste field for the GitHub PAT (shared by onboarding and 设置).
struct TokenField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        SecureField("github_pat_…", text: $text)
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focused)
            .font(.system(size: 17))
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityIdentifier("patField")
    }
}

extension AppModel {
    /// `github_pat_••••3fQk`, or nil when no token is stored.
    var maskedToken: String? {
        guard sync.hasToken, let token = tokenStore.readToken() else { return nil }
        let prefix = token.hasPrefix("github_pat_") ? "github_pat_" : token.hasPrefix("ghp_") ? "ghp_" : ""
        return prefix + "••••" + token.suffix(4)
    }
}
