import SwiftUI

/// 测试 tab: start a short Vocabulary Test (again, even if already tested today) and see the last estimate.
struct TestTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let profile = model.profile {
                    List {
                        BaselineSection()
                        Section("今日短测") {
                            Text(model.testedToday ? "✓ 今天已测" : "3–5 分钟 · 约 80 题")
                            Button(model.testedToday ? "再测一次" : "开始短测") { model.startTest() }
                                .font(.headline)
                                .accessibilityIdentifier("startTest")
                        }
                        if profile.counts.evidence > 0 {
                            Section("上次结果") {
                                let v = profile.vocabulary.families
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Int(v.estimate.rounded()), format: .number)
                                        .font(.system(size: 40, weight: .bold))
                                    Text("词族 · 95% 区间 \(Int(v.low.rounded())) – \(Int(v.high.rounded()))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    if let day = model.lastTestDay {
                                        Text("最近测试 \(day)").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    LoadingState()
                }
            }
            .navigationTitle("测试")
            .syncStatusChrome()
        }
    }
}
