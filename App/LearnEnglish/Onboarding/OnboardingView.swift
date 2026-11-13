import SwiftUI

/// First-launch screens (prototype scheme A, `onboarding()`).
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    @FocusState private var tokenFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .welcome: welcome
                case .token: token
                case .baseline: baseline
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemGroupedBackground))
            .animation(.default, value: model.step)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("你好").font(.largeTitle.bold()).padding(.top, 24)
            Text("这个 App 会定期测出你的词汇量。")
            Text("所有记录都存到你自己的私有 GitHub 仓库 english-data。")
                .foregroundStyle(.secondary)
            Spacer()
            primaryButton("开始设置", id: "onboardingStart") { model.next() }
        }
    }

    private var token: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("第 1 步：连接 GitHub").font(.title2.bold()).padding(.top, 24)
            Text("粘贴令牌（fine-grained PAT）").font(.headline)
            SecureField("github_pat_…", text: $model.tokenInput)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($tokenFocused)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { tokenFocused = true }
                .accessibilityIdentifier("patField")
            if let error = model.tokenError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Text("只需授权 english-data 仓库的 Contents 读写。令牌只存在本机钥匙串里。也可以先跳过，稍后在设置里补上。")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            primaryButton("保存", id: "patSave") { model.saveToken() }
                .disabled(model.tokenInput.isEmpty)
            Button("先跳过，稍后再设") { model.skipToken() }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityIdentifier("patSkip")
        }
    }

    private var baseline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("第 2 步：基线测试").font(.title2.bold()).padding(.top, 24)
            if model.tokenSaved {
                Label("令牌已保存到钥匙串", systemImage: "checkmark.seal").font(.footnote).foregroundStyle(.green)
            }
            Text("约 30 分钟").font(.system(size: 40, weight: .bold))
            Text("一次性的完整测试，用来定出你的起点。中途可以退出，下次从断点继续。之后每天只需 3–5 分钟的短测。")
                .foregroundStyle(.secondary)
            Spacer()
            primaryButton(model.canStartBaseline ? "开始基线测试" : "正在加载词库…", id: "baselineStart") {
                model.startBaseline()
            }
            .disabled(!model.canStartBaseline)
            Button("稍后再做") { model.later() }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityIdentifier("baselineLater")
        }
    }

    private func primaryButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier(id)
    }
}
