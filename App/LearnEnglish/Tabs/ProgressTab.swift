import SwiftUI

/// 进度 tab: vocabulary estimate and Word Band counts from the local profile. Ticket 09 fills it out.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let p = model.profile {
                    List {
                        Section("估计词汇量（word family）") {
                            let v = p.vocabulary.families
                            Text(Int(v.estimate.rounded()), format: .number).font(.system(size: 40, weight: .bold))
                            Text("95% 区间 \(Int(v.low.rounded())) – \(Int(v.high.rounded()))")
                                .foregroundStyle(.secondary)
                        }
                        Section("三类词") {
                            LabeledContent("已掌握 Mastered", value: "\(p.bandCounts.mastered)")
                            LabeledContent("正好该学 Target", value: "\(p.bandCounts.target)")
                            LabeledContent("暂时太远 Distant", value: "\(p.bandCounts.distant)")
                        }
                    }
                } else {
                    LoadingState()
                }
            }
            .navigationTitle("进度")
        }
    }
}
