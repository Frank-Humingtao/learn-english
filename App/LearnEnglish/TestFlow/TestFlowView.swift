import SwiftUI
import TestEngine

/// Full-screen test flow: ✕ top-left exits at any time; answers are saved as they are given.
struct TestFlowView: View {
    let model: TestFlowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.phase {
            case .preparing:
                Spacer()
                ProgressView("正在出题…")
                Spacer()
            case .question(.yesNo(let q)):
                YesNoQuestion(item: q) { model.answer(.yesNo($0)) }
                    .id(model.recorded)
            case .question(.meaningCheck(let q)):
                MeaningQuestion(item: q) { model.answer(.meaning($0)) }
                    .id(model.recorded)
            case .computingResult:
                Spacer()
                ProgressView("正在计算结果…")
                Spacer()
            case .result(let result):
                TestResultView(result: result, recorded: model.recorded) { model.close() }
            case .failed(let message):
                Spacer()
                ContentUnavailableView("出错了", systemImage: "exclamationmark.triangle", description: Text(message))
                Spacer()
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await model.start()
            #if DEBUG
            await model.autoplayIfRequested()
            #endif
        }
    }

    @ViewBuilder private var header: some View {
        if case .result = model.phase {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                HStack {
                    Button { model.close() } label: {
                        Image(systemName: "xmark").font(.title3.weight(.semibold))
                    }
                    .accessibilityLabel("退出测试")
                    .accessibilityIdentifier("closeTest")
                    Spacer()
                    Text(model.title).font(.headline)
                    Spacer()
                    Text("剩约 \(model.minutesLeft) 分").font(.footnote).foregroundStyle(.secondary)
                }
                ProgressView(value: model.progress)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

private struct YesNoQuestion: View {
    let item: YesNoItem
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack {
            Text("你认识这个词吗？（有些是编出来的假词）")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 24)
            Spacer()
            Text(item.word)
                .font(.system(size: 44, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal)
                .accessibilityIdentifier("testWord")
            Spacer()
            HStack(spacing: 12) {
                Button { onAnswer(false) } label: {
                    Text("不认识").frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("answerNo")
                Button { onAnswer(true) } label: {
                    Text("认识").frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("answerYes")
            }
            .font(.title3.weight(.semibold))
            .padding()
        }
    }
}

private struct MeaningQuestion: View {
    let item: MeaningCheckItem
    let onAnswer: (Int?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("选出它的中文意思").font(.footnote).foregroundStyle(.secondary).padding(.top, 24)
                Text(item.lemma).font(.system(size: 36, weight: .bold)).padding(.bottom, 16)
                ForEach(Array(item.options.enumerated()), id: \.offset) { i, option in
                    optionButton(option) { onAnswer(i) }
                }
                optionButton("不认识") { onAnswer(nil) }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private func optionButton(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
