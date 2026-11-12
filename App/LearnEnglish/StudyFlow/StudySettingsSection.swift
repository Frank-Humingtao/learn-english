import SwiftUI

/// 设置 › 学习: the daily new-card limit. Each change is one `setting` Observation.
struct StudySettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?

    static let choices = [3, 5, 8, 10, 15, 20, 25, 30, 40, 50]

    var body: some View {
        Section {
            Picker("每日新词上限", selection: Binding(
                get: { model.dailyNewLimit },
                set: { n in
                    do { try model.setDailyNewLimit(n) } catch { self.error = "保存失败：\(error)" }
                }
            )) {
                ForEach(Self.choices(including: model.dailyNewLimit), id: \.self) { Text("\($0) 个").tag($0) }
            }
            .accessibilityIdentifier("dailyNewLimit")
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("学习")
        } footer: {
            Text("每天的新词数取学习计划建议数和这个上限中较小的一个。")
        }
    }

    static func choices(including n: Int) -> [Int] {
        choices.contains(n) ? choices : (choices + [n]).sorted()
    }
}
