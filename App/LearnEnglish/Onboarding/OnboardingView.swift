import SwiftUI
import TestEngine

/// First launch: paste the token (skippable), then start the Baseline Test.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.step {
            case .token: token.transition(.push(from: .trailing))
            case .baseline: baseline.transition(.push(from: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.step)
    }

    private var token: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 8)
            TokenField(text: $model.tokenInput)
            if let error = model.tokenError {
                Text(error).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.bad)
            }
            Spacer()
            Button("保存") { model.saveToken() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.tokenInput.isEmpty)
                .accessibilityIdentifier("patSave")
            Button("跳过") { model.skipToken() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 8)
                .accessibilityIdentifier("patSkip")
        }
        .padding(16)
    }

    private var baseline: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(TestConfig.baseline.yesNoCount.grouped)
                .font(Theme.number(76))
            Text("题").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
            Spacer()
            Button {
                model.startBaseline()
            } label: {
                if model.canStartBaseline { Text("开始基线") } else { ProgressView().tint(.white) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canStartBaseline)
            .accessibilityIdentifier("baselineStart")
            Button("稍后") { model.later() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 8)
                .accessibilityIdentifier("baselineLater")
        }
        .padding(16)
    }
}
