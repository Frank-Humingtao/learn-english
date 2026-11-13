import Charts
import CoreModels
import ProfileEngine
import SwiftUI

/// 进度 tab: vocabulary history with its interval band, ≤14k / >14k, the three Word Bands and
/// mastery per frequency level. Numbers and charts only; all recomputed on device.
struct ProgressTab: View {
    @Environment(AppModel.self) private var model
    @State private var curve: [VocabPoint] = []

    var body: some View {
        VStack(spacing: 0) {
            SyncErrorBanner()
            if let p = model.profile {
                ScrollView { content(p) }
            } else {
                LoadingState().frame(maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .task(id: curveKey) { await refreshCurve() }
    }

    private func content(_ p: LearnerProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("进度").font(.system(size: 28, weight: .heavy)).padding(.top, 12)

            Panel(title: "词汇量") {
                if !curve.isEmpty { VocabCurveChart(points: curve) }
                HStack(alignment: .top, spacing: 10) {
                    kpi(Int(p.vocabulary.core.families.estimate.rounded()).grouped, "≤14k", id: "vocabCore")
                    kpi(Int(p.vocabulary.tail.families.estimate.rounded()).grouped, ">14k", id: "vocabTail")
                    kpi("\(model.testActivity.streakDays)", "连续天数", id: "streak")
                }
            }

            Panel(title: "三类词") {
                BandBar(counts: p.bandCounts)
            }

            Panel(title: "各频段掌握率") {
                LevelMasteryChart(levels: p.levelMastery)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func kpi(_ value: String, _ label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.number(24)).accessibilityIdentifier(id)
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// At most four x labels, one per day.
    private var labelDates: [Date] {
        var seen = Set<String>()
        let days = points.compactMap { Clock.date(fromISO: $0.ts) }.filter { seen.insert(Clock.localDay($0)).inserted }
        let step = max(1, Int((Double(days.count) / 4).rounded(.up)))
        return days.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                let date = Clock.date(fromISO: pt.ts) ?? .distantPast
                AreaMark(x: .value("日期", date), yStart: .value("下限", pt.families.low),
                         yEnd: .value("上限", pt.families.high))
                    .foregroundStyle(Theme.accentSoft)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("日期", date), y: .value("词族", pt.families.estimate))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("日期", date), y: .value("词族", pt.families.estimate))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(i == points.count - 1 ? 70 : 25)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) / 1000))k") }
            }
        }
        .chartXAxis {
            AxisMarks(values: labelDates) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .frame(height: 160)
        .accessibilityIdentifier("vocabCurve")
    }
}

/// The three Word Bands as one stacked bar with counts.
private struct BandBar: View {
    let counts: BandCounts

    var body: some View {
        let parts: [(String, Int, Color)] = [("熟词", counts.mastered, Theme.good),
                                             ("目标", counts.target, Theme.accent),
                                             ("远词", counts.distant, Theme.line)]
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        VStack(spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(parts, id: \.0) { part in
                        Rectangle().fill(part.2).frame(width: geo.size.width * CGFloat(part.1) / CGFloat(total))
                    }
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 6) {
                        Circle().fill(part.2).frame(width: 9, height: 9)
                        Text(part.0)
                        Text(part.1.grouped).font(Theme.number(13, weight: .semibold))
                    }
                    if part.0 != parts.last?.0 { Spacer(minLength: 4) }
                }
            }
            .font(.system(size: 13))
            .accessibilityIdentifier("bandCounts")
        }
    }
}

private struct LevelMasteryChart: View {
    let levels: [LevelMastery]

    var body: some View {
        Chart(levels, id: \.level) { l in
            BarMark(x: .value("频段", l.level), y: .value("掌握率", l.mastery))
                .foregroundStyle(l.mastery >= 0.8 ? Theme.good : Theme.accent)
                .cornerRadius(2)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%") }
            }
        }
        .chartXAxis {
            AxisMarks(values: levels.map(\.level).filter { $0 == 1 || $0 % 5 == 0 }) { v in
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)k") }
            }
        }
        .frame(height: 160)
        .accessibilityIdentifier("levelMastery")
    }
}
