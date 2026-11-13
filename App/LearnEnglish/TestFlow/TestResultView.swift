import SwiftUI
import TestEngine

/// Result screen: the new number, the change since last time, and one warning line only when
/// the session looked abnormal. Details live in the Progress Report.
struct TestResultView: View {
    let result: TestResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(result.vocabulary.estimate.grouped)
                .font(Theme.number(84))
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("resultVocabulary")
            if let change = result.change {
                Text(change.signed)
                    .font(Theme.number(22))
                    .foregroundStyle(change >= 0 ? Theme.good : Theme.bad)
                    .accessibilityIdentifier("resultChange")
            }
            if let warning = result.warning {
                Text(warning)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.bad)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.badSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("aberrantWarning")
            }
            Spacer()
            Button("完成", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("doneTest")
        }
        .padding(16)
    }
}

extension TestResult {
    /// Share of pseudowords answered "认识" above which the session is flagged.
    static let pseudowordWarningRate = 0.10

    /// One line when this session looks unreliable, else nil.
    var warning: String? {
        let (falseAlarms, total) = pseudowords
        if total >= 10, Double(falseAlarms) / Double(total) >= Self.pseudowordWarningRate {
            return "假词点了 \(falseAlarms) 次认识，这次可能偏高"
        }
        if looksAberrant { return "这次作答和词频规律不一致" }
        return nil
    }
}
