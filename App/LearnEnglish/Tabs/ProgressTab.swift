import Charts
import CoreModels
import ProfileEngine
import SwiftUI

/// 进度 tab (ticket 09): vocabulary size and its curve, Word Bands, level mastery, streak,
/// and links to the public dashboard. All numbers are recomputed on device.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var curve: [VocabPoint] = []
    @State private var ownerDraft = ""

    var body: some View {
        NavigationStack {
            Group {
                if let p = model.profile {
                    content(p)
                } else {
                    LoadingState()
                }
            }
            .navigationTitle("进度")
            .syncStatusChrome()
            .task(id: curveKey) { await refreshCurve() }
        }
    }

    private func content(_ p: LearnerProfile) -> some View {
        let activity = model.testActivity
        return List {
            Section {
                let v = p.vocabulary.families
                Text(Int(v.estimate.rounded()), format: .number)
                    .font(.system(size: 40, weight: .bold)).accessibilityIdentifier("vocabEstimate")
                Text("95% 区间 \(Int(v.low.rounded())) – \(Int(v.high.rounded()))").foregroundStyle(.secondary)
                if curve.count >= 1 { VocabCurveChart(points: curve) }
            } header: {
                Text("估计词汇量（词族）")
            } footer: {
                Text(curve.isEmpty ? "做过测试后这里显示曲线。" : "每次测试结束时的估计，阴影为 95% 区间。")
            }

            Section("三类词") {
                BandChart(counts: p.bandCounts)
                LabeledContent("已掌握 Mastered", value: "\(p.bandCounts.mastered)")
                LabeledContent("正好该学 Target", value: "\(p.bandCounts.target)")
                LabeledContent("暂时太远 Distant", value: "\(p.bandCounts.distant)")
            }

            Section {
                LevelMasteryChart(levels: p.levelMastery)
            } header: {
                Text("各频段掌握率")
            } footer: {
                Text("每 1000 个词族为一段（BNC/COCA），数值为该段词族的平均掌握概率。")
            }

            Section("坚持") {
                LabeledContent("连续测试天数", value: "\(activity.streakDays) 天")
                LabeledContent("最近测试", value: activity.lastTestDay ?? "还没有")
            }

            linksSection
        }
    }

    // MARK: public links

    @ViewBuilder private var linksSection: some View {
        Section {
            if let dashboard = model.publicDashboardURL, let reports = model.progressReportURL {
                Button { openURL(dashboard) } label: {
                    Label("公开看板", systemImage: "globe")
                }
                .accessibilityIdentifier("openDashboard")
                Button { openURL(reports) } label: {
                    Label("最新 Progress Report", systemImage: "doc.text")
                }
                .accessibilityIdentifier("openReport")
            } else {
                TextField("GitHub 用户名", text: $ownerDraft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { model.setPublicOwner(ownerDraft) }
                Button("保存") { model.setPublicOwner(ownerDraft) }
                    .disabled(ownerDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("公开")
        } footer: {
            Text("本页数字由本机重算。公开看板在同步后由 GitHub Actions 更新，会稍有滞后。")
        }
    }

    // MARK: curve

    /// Changes when a test answer is added (or the lexicon loads), so the curve is refreshed then.
    private var curveKey: String {
        "\(model.lexicon?.version ?? "")#\(model.observations.lazy.filter { $0.source == .test }.count)"
    }

    private func refreshCurve() async {
        guard let lexicon = model.lexicon else { return }
        let observations = model.observations
        let cached = curve
        curve = await Task.detached(priority: .utility) {
            ProgressPage.curve(observations: observations, lexicon: lexicon, reusing: cached)
        }.value
    }
}

private struct VocabCurveChart: View {
    let points: [VocabPoint]

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                let date = Clock.date(fromISO: pt.ts) ?? .distantPast
                AreaMark(x: .value("日期", date), yStart: .value("下限", pt.families.low),
                         yEnd: .value("上限", pt.families.high))
                    .foregroundStyle(.blue.opacity(0.15))
                LineMark(x: .value("日期", date), y: .value("词族", pt.families.estimate))
                PointMark(x: .value("日期", date), y: .value("词族", pt.families.estimate))
            }
        }
        .chartYAxisLabel("词族")
        .frame(height: 180)
        .accessibilityIdentifier("vocabCurve")
    }
}

private struct BandChart: View {
    let counts: BandCounts

    var body: some View {
        let rows: [(String, Int, Color)] = [("已掌握", counts.mastered, .green), ("该学", counts.target, .orange),
                                            ("太远", counts.distant, .gray)]
        Chart(rows, id: \.0) { row in
            BarMark(x: .value("词数", row.1), y: .value("类别", row.0))
                .foregroundStyle(row.2)
                .annotation(position: .trailing) { Text("\(row.1)").font(.caption) }
        }
        .chartXAxis(.hidden)
        .frame(height: 110)
    }
}

private struct LevelMasteryChart: View {
    let levels: [LevelMastery]

    var body: some View {
        Chart(levels, id: \.level) { l in
            BarMark(x: .value("频段（千）", l.level), y: .value("掌握率", l.mastery))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(values: [0, 0.5, 1]) { v in
            AxisGridLine()
            AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%") }
        } }
        .frame(height: 160)
    }
}
