import Lexicon
import StudyComposer
import SwiftUI

/// Full-screen study flow (scheme A): reviews → "复习完成" stop point → new cards → completion page.
/// ✕ top-left stops at any time; each rating is saved as it is given.
struct StudyFlowView: View {
    let model: StudyFlowModel

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .review(let lemma), .newCard(let lemma):
                header
                CardView(model: model, lemma: lemma)
                    .id(model.recorded)
            case .separator(let n):
                header
                SeparatorView(newCount: n, reviewed: model.session.summary.reviewed,
                              onStart: model.startNewCards, onStop: model.finish)
            case .done:
                StudyDoneView(summary: model.session.summary, onClose: model.close)
            }
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.bottom)
            }
        }
        .background(Color(.systemGroupedBackground))
        #if DEBUG
        .task { await model.autoplayIfRequested() }
        #endif
    }

    private var header: some View {
        HStack {
            Button { model.finish() } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold))
            }
            .accessibilityLabel("结束学习")
            .accessibilityIdentifier("closeStudy")
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Text(model.session.current == nil ? "" : "剩 \(model.session.remainingInPhase)")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
    }

    private var title: String {
        switch model.phase {
        case .review: "复习"
        case .newCard: "新词"
        default: "学习"
        }
    }
}

/// One card: word, phonetic and pronunciation on the front; tap to flip to definitions, example,
/// Chinese and the plan's note; then the four rating buttons with their next intervals.
private struct CardView: View {
    let model: StudyFlowModel
    let lemma: String

    var body: some View {
        let entry = model.entry(lemma)
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Text(lemma)
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .padding(.top, 40)
                        .accessibilityIdentifier("cardWord")
                    HStack(spacing: 8) {
                        if let p = entry?.phonetic, !p.isEmpty {
                            Text("/\(p)/").font(.title3).foregroundStyle(.secondary)
                        }
                        Button { model.speak(lemma) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .accessibilityLabel("发音")
                    }
                    if model.flipped {
                        back(entry)
                    } else {
                        Text("点击翻面").font(.footnote).foregroundStyle(.tertiary).padding(.top, 60)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.flip() }
            .accessibilityAction(named: "翻面") { model.flip() }
            if model.flipped { buttons }
        }
        .onAppear { model.speak(lemma) }
    }

    @ViewBuilder private func back(_ entry: LexiconEntry?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            if let d = entry?.definition, !d.isEmpty {
                Text(lines(d)).font(.body)
            }
            if let ex = entry?.example, !ex.isEmpty {
                Text(ex).font(.body.italic()).foregroundStyle(.secondary)
            }
            if let zh = entry?.translation, !zh.isEmpty {
                Text(lines(zh)).font(.body)
            }
            if let note = model.note(lemma) {
                Label(note, systemImage: "lightbulb")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// ECDICT fields keep line breaks as a literal `\n`.
    private func lines(_ s: String) -> String { s.replacingOccurrences(of: "\\n", with: "\n") }

    private var buttons: some View {
        let intervals = model.intervals()
        return HStack(spacing: 8) {
            ForEach(Grade.allCases, id: \.self) { g in
                Button { model.rate(g) } label: {
                    VStack(spacing: 4) {
                        Text(g.label).font(.headline)
                        Text(intervals[g].map(IntervalText.format) ?? "").font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(g.tint)
                .accessibilityIdentifier("rate-\(g.result)")
            }
        }
        .padding()
    }
}

private struct SeparatorView: View {
    let newCount: Int
    let reviewed: Int
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("复习完成").font(.title.bold())
            Text("已复习 \(reviewed) 张").foregroundStyle(.secondary)
            Button(action: onStart) {
                Text("开始 \(newCount) 个新词").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("startNewCards")
            Button("今天先到这里", action: onStop)
            Spacer()
        }
        .padding(32)
    }
}

private struct StudyDoneView: View {
    let summary: StudySession.Summary
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 56)).foregroundStyle(.yellow)
            Text("今天的学习完成了").font(.title.bold())
            VStack(spacing: 8) {
                LabeledContent("复习", value: "\(summary.reviewed) 张")
                LabeledContent("新学", value: "\(summary.learned) 个")
                if summary.tooEasy > 0 {
                    LabeledContent("太简单（已跳过）", value: "\(summary.tooEasy) 个")
                }
                LabeledContent("评分", value: "\(summary.ratings) 次")
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            Button(action: onClose) { Text("完成").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("closeStudyDone")
            Spacer()
        }
        .padding(32)
    }
}

extension Grade {
    var label: String {
        switch self {
        case .again: "忘了"
        case .hard: "模糊"
        case .good: "想起"
        case .easy: "太简单"
        }
    }

    var tint: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}

/// Short Chinese interval text under a rating button.
enum IntervalText {
    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "<1分钟" }
        if s < 3600 { return "\(Int((s / 60).rounded()))分钟" }
        if s < 86400 { return "\(Int((s / 3600).rounded()))小时" }
        let days = s / 86400
        if days < 30 { return "\(Int(days.rounded()))天" }
        if days < 365 { return String(format: "%.1f个月", days / 30) }
        return String(format: "%.1f年", days / 365)
    }
}
