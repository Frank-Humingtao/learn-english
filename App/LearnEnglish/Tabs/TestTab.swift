import ProfileEngine
import SwiftUI
import TestEngine

/// 测试 tab (prototype #13, variant A): the vocabulary number centred, its 95% interval, a link to
/// the latest Progress Report, and one button that starts whatever is due — the Baseline Test,
/// its resumption, or a short test.
struct TestTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            SyncErrorBanner()
            if let profile = model.profile {
                content(profile)
            } else {
                LoadingState().frame(maxHeight: .infinity)
            }
        }
        .background(Theme.background)
    }

    private func content(_ profile: LearnerProfile) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if let url = model.progressReportURL {
                    Button { openURL(url) } label: {
                        Text("报告 ↗").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("openReport")
                }
            }
            .frame(minHeight: 34)
            Spacer()
            VStack(spacing: 10) {
                if let v = profile.families {
                    Text(v.estimate.grouped)
                        .font(Theme.number(76))
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText(value: Double(v.estimate)))
                        .accessibilityIdentifier("vocabEstimate")
                    Text("词族").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text("\(v.low.grouped) – \(v.high.grouped)")
                        .font(Theme.number(17, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("vocabInterval")
                } else {
                    Text("–").font(Theme.number(76)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            startButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    @ViewBuilder private var startButton: some View {
        if model.baselinePending, let b = model.baseline {
            Button { model.startBaseline() } label: {
                label("继续基线", detail: "\(model.baselineAnswered) / \(b.total)")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("resumeBaseline")
        } else if model.baseline == nil {
            Button { model.startBaseline() } label: {
                label("开始基线", detail: "\(TestConfig.baseline.yesNoCount) 题")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("startBaseline")
        } else {
            Button { model.startTest() } label: {
                label("短测", detail: "\(TestConfig.short.yesNoCount) 题")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("startTest")
        }
    }

    private func label(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
            Text(detail).font(Theme.number(14, weight: .semibold)).opacity(0.8)
        }
    }
}

/// A rounded estimate with its 95% interval.
struct RoundedRange: Equatable {
    var estimate: Int
    var low: Int
    var high: Int

    init(_ e: Estimate) {
        estimate = Int(e.estimate.rounded())
        low = Int(e.low.rounded())
        high = Int(e.high.rounded())
    }
}

extension LearnerProfile {
    /// Word-family estimate; nil before any evidence.
    var families: RoundedRange? {
        counts.evidence > 0 ? RoundedRange(vocabulary.families) : nil
    }
}
