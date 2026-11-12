import StudyComposer
import SwiftUI

/// 学习 tab: today's reviews and new cards from the Study Plan, start a session, 加词.
struct StudyTab: View {
    @Environment(AppModel.self) private var model
    @State private var addingWord = false
    @State private var newWord = ""
    @State private var addMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoaded {
                    content
                } else {
                    LoadingState()
                }
            }
            .navigationTitle("学习")
            .syncStatusChrome()
            .toolbar {
                Button { addingWord = true } label: { Label("加词", systemImage: "plus") }
                    .accessibilityIdentifier("addWord")
            }
            .alert("加词", isPresented: $addingWord) {
                TextField("英文单词", text: $newWord)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("加入") { addWord() }
                Button("取消", role: .cancel) { newWord = "" }
            } message: {
                Text("下一份学习计划会优先安排它。")
            }
        }
    }

    private var content: some View {
        let session = model.composeStudy()
        return List {
            Section("今天") {
                HStack {
                    stat("复习", session?.reviews.count ?? 0)
                    stat("新词", session?.newCards.count ?? 0)
                }
                if let plan = model.studyPlan, !plan.summary.isEmpty {
                    Text(plan.summary)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("planSummary")
                }
                if let warning = session.flatMap({ Self.planWarning($0.planStatus) }) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Self.warningYellow)
                        .accessibilityIdentifier("planWarning")
                }
                if let session, !session.isEmpty {
                    Button("开始学习") { model.startStudy() }
                        .font(.headline)
                        .accessibilityIdentifier("startStudy")
                } else {
                    Text("今天的卡片都学完了").foregroundStyle(.secondary)
                }
            }
            if let plan = model.studyPlan {
                Section("学习计划") {
                    LabeledContent("生成于", value: String(plan.generatedAt.prefix(10)))
                    LabeledContent("计划每日", value: "\(plan.dailyNew) 个")
                    LabeledContent("我的上限", value: "\(model.dailyNewLimit) 个")
                }
            }
            if let addMessage {
                Section { Text(addMessage).font(.footnote) }
            }
            let wishes = model.wishes
            if !wishes.isEmpty {
                Section("想学的词") {
                    Text(wishes.prefix(20).joined(separator: " · ")).font(.footnote)
                }
            }
        }
    }

    /// Dark yellow: readable on white, still reads as 黄字.
    static let warningYellow = Color(red: 0.78, green: 0.56, blue: 0.0)

    /// The yellow line under today's counts; nil when the plan is fine.
    static func planWarning(_ status: PlanStatus) -> String? {
        switch status {
        case .current: nil
        case .missing: "还没有学习计划，去跑一次选词规划"
        case .usedUp: "学习计划已用完，去跑一次选词规划"
        case .stale(let days): "学习计划 \(days) 天未更新，去检查选词规划"
        case .runningLow(let n): "学习计划只剩 \(n) 个新词，不够 2 天，去检查选词规划"
        }
    }

    private func stat(_ title: String, _ n: Int) -> some View {
        VStack(alignment: .leading) {
            Text("\(n)").font(.system(size: 32, weight: .bold))
            Text(title).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addWord() {
        defer { newWord = "" }
        guard !newWord.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let lemma = try model.addWish(newWord)
            addMessage = "已加入「\(lemma)」"
        } catch {
            addMessage = error.localizedDescription
        }
    }
}
