import SwiftUI

/// 测试 tab: start the Baseline Test if it was never taken, or resume an unfinished one.
/// Shows nothing once the latest Baseline Test is complete.
struct BaselineSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.baselinePending, let b = model.baseline {
            Section("基线测试") {
                Text("已答 \(model.baselineAnswered) / 约 \(b.total) 题，从断点继续")
                Button("继续基线测试") { model.startBaseline() }
                    .font(.headline)
                    .accessibilityIdentifier("resumeBaseline")
            }
        } else if model.baseline == nil {
            Section("基线测试") {
                Text("约 30 分钟，一次性定出你的起点。中途可以退出，下次从断点继续。")
                Button("开始基线测试") { model.startBaseline() }
                    .font(.headline)
                    .accessibilityIdentifier("startBaseline")
            }
        }
    }
}

/// 设置 tab: "重做 Baseline Test" (spec story 53). Starts a fresh full-length test; earlier
/// answers stay as Observations.
struct RedoBaselineSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        Section("测试") {
            Button("重做基线测试") { confirming = true }
                .disabled(!model.isLoaded)
                .accessibilityIdentifier("redoBaseline")
                .alert("重做基线测试？", isPresented: $confirming) {
                    Button("开始（约 30 分钟）") { model.startBaseline(redo: true) }
                        .accessibilityIdentifier("confirmRedo")
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(model.baselinePending
                         ? "未完成的那次会被放弃，已答的题仍然保留在记录里。"
                         : "适合隔了很久之后重新校准。以前的记录都会保留。")
                }
        }
    }
}
