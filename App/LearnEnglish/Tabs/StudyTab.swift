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
                    Text(plan.summary)
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
