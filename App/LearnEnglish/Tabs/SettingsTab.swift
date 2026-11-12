import SwiftUI

/// 设置 tab. Token, sync and study settings arrive with tickets 04, 05 and 07.
struct SettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                StudySettingsSection()
                SyncSettingsSection()
                Section("本机数据") {
                    LabeledContent("本机记录", value: "\(model.observations.count) 条")
                    LabeledContent("词库版本", value: model.lexicon?.version ?? "加载中")
                }
                RedoBaselineSection()
            }
            .navigationTitle("设置")
            .syncStatusChrome()
        }
    }
}
