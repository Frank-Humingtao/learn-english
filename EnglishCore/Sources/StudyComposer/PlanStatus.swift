import CoreModels
import Foundation

/// Whether the Study Plan needs the Learner's attention (the 学习 tab's yellow line).
///
/// Word Planning runs on the Learner's Mac; when it stops (Mac asleep, credentials, a failed
/// validation) the App is the place the Learner notices.
public enum PlanStatus: Sendable, Equatable {
    /// Nothing to show.
    case current
    /// No Study Plan synced yet: only reviews.
    case missing
    /// Every plan word has a card or is Mastered: only reviews.
    case usedUp
    /// `generated_at` is more than `PlanStatus.staleAfterDays` days ago (whole days elapsed).
    case stale(days: Int)
    /// Fewer than `PlanStatus.lowDays` days of new words left.
    case runningLow(remaining: Int)

    public static let staleAfterDays = 3.0
    public static let lowDays = 2

    /// - Parameters:
    ///   - remaining: plan words that can still become new cards (no card, not Mastered, known).
    ///   - perDay: new cards per day, min(plan.dailyNew, limit).
    public static func evaluate(plan: StudyPlan?, remaining: Int, perDay: Int, now: Date) -> PlanStatus {
        guard let plan else { return .missing }
        if remaining == 0 { return .usedUp }
        if let generated = Timestamp.epochSeconds(plan.generatedAt) {
            let age = now.timeIntervalSince1970 - generated
            if age > staleAfterDays * 86400 { return .stale(days: Int(age / 86400)) }
        }
        if remaining < lowDays * perDay { return .runningLow(remaining: remaining) }
        return .current
    }
}
