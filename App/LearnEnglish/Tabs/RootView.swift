import SwiftUI

/// Bottom tab bar (scheme A): 学习 / 测试 / 进度 / 设置. Tests and reviews run as full-screen flows
/// over the tab bar via `AppModel.presentedFlow`. Each tab lives in its own file.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            StudyTab()
                .tabItem { Label("学习", systemImage: "book") }
                .tag(AppModel.Tab.study)
            TestTab()
                .tabItem { Label("测试", systemImage: "checklist") }
                .tag(AppModel.Tab.test)
            ProgressTab()
                .tabItem { Label("进度", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppModel.Tab.progress)
            SettingsTab()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(AppModel.Tab.settings)
        }
        .fullScreenCover(item: $model.presentedFlow) { flow in
            switch flow {
            case .test(let test): TestFlowView(model: test)
            case .study(let study): StudyFlowView(model: study)
            }
        }
    }
}

/// Shown by tabs while the lexicon and profile load.
struct LoadingState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.loadError {
            ContentUnavailableView("无法加载词库", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ProgressView("正在加载词库…")
        }
    }
}
