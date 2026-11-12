import SwiftUI
import TestEngine

/// Result screen. Every number is computed on this device by the Profile Engine.
struct TestResultView: View {
    let result: TestResult
    let recorded: Int
    var title = "今日短测完成"
    let onDone: () -> Void

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("估计词汇量").font(.footnote).foregroundStyle(.secondary)
                    Text(result.vocabulary.estimate, format: .number)
                        .font(.system(size: 44, weight: .bold))
                        .accessibilityIdentifier("resultVocabulary")
                    Text("词族 · 95% 区间 \(result.vocabulary.low) – \(result.vocabulary.high)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(changeText).font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                LabeledContent("新发现的 Target 词", value: "\(result.newTargetWords.count)")
                LabeledContent("抽查的已掌握词",
                               value: "\(result.spotcheck.correct) 对 / \(result.spotcheck.wrong) 错")
                LabeledContent("假词误认", value: "\(result.pseudowords.falseAlarms) / \(result.pseudowords.total)")
            }
            Section {
                Text("本机已记下 \(recorded) 条作答。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("完成", action: onDone)
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .accessibilityIdentifier("doneTest")
            }
        }
        .safeAreaInset(edge: .top) {
            Text(title).font(.headline).padding(.top, 8)
        }
    }

    private var changeText: String {
        guard let c = result.change else { return "第一次测试" }
        return c == 0 ? "与上次持平" : c > 0 ? "较上次 +\(c)" : "较上次 \(c)"
    }
}
