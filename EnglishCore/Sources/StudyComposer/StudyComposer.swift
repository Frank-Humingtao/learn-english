import CoreModels
import Foundation

/// Study Session Composer: given the Observation history, the Study Plan and the daily limit,
/// decides what one study session contains (due reviews first, then new cards).
public struct StudyComposer: Sendable {
    public let scheduler: CardScheduler
    public let rules: CardRules

    public init(scheduler: CardScheduler = CardScheduler(), rules: CardRules = CardRules()) {
        self.scheduler = scheduler
        self.rules = rules
    }

    public func ledger(observations: [Observation], now: Date) -> CardLedger {
        CardLedger(observations: observations, scheduler: scheduler, rules: rules, now: now)
    }

    /// - Parameters:
    ///   - dailyNewLimit: the Learner's setting; new cards per day = min(plan.dailyNew, this).
    ///   - isMastered: Word Band check from the Learner Profile (P ≥ 0.9). Mastered words get no
    ///     new card, and an existing card on a Mastered word is paused.
    ///   - isKnownLemma: words not in the bundled lexicon are skipped.
    ///   - calendar: its time zone decides what "today" is.
    public func compose(observations: [Observation], plan: StudyPlan?, dailyNewLimit: Int,
                        isMastered: (String) -> Bool, isKnownLemma: (String) -> Bool = { _ in true },
                        now: Date, calendar: Calendar,
                        sessionID: String? = nil, lexiconVersion: String? = nil) -> StudySession {
        let ledger = ledger(observations: observations, now: now)
        let cards = ledger.cards
        let today = calendar.startOfDay(for: now)

        let reviews = cards.values
            .filter { !$0.isNew && $0.suspended == nil && !isMastered($0.lemma) && isDue($0.memory, now: now, calendar: calendar) }
            .sorted { ($0.memory.due, $0.lemma) < ($1.memory.due, $1.lemma) }
            .map(\.lemma)

        // Cards started today count toward today's limit, except those rated 太简单 at once
        // (each of those is replaced from the plan).
        let startedToday = cards.values.filter {
            guard let first = $0.firstReviewAt, $0.firstGrade != .easy else { return false }
            return calendar.startOfDay(for: first) == today
        }.count
        let limit = min(plan?.dailyNew ?? dailyNewLimit, dailyNewLimit)
        var remaining = max(0, limit - startedToday)

        // Reintroduced Leeches go first and count toward the limit.
        let reintroduced = cards.values
            .filter { $0.isNew && $0.reintroduced && !isMastered($0.lemma) }
            .sorted { ($0.resetAt ?? now, $0.lemma) < ($1.resetAt ?? now, $1.lemma) }
            .map(\.lemma)
        var newCards = Array(reintroduced.prefix(remaining))
        remaining -= newCards.count

        var seen = Set<String>()
        let candidates = (plan?.newWords ?? []).map(\.lemma).filter {
            cards[$0] == nil && !isMastered($0) && isKnownLemma($0) && seen.insert($0).inserted
        }
        newCards += candidates.prefix(remaining)
        let spare = Array(candidates.dropFirst(remaining))

        var memories: [String: CardMemory] = [:]
        for l in reviews + newCards { memories[l] = cards[l]?.memory ?? scheduler.newCard(at: now) }
        return StudySession(reviews: reviews, newCards: newCards, spare: spare, memories: memories,
                            plan: plan, scheduler: scheduler, learnAhead: rules.learnAhead,
                            sessionID: sessionID, lexiconVersion: lexiconVersion)
    }

    /// Learning-step cards are due once within `learnAhead`; review cards are due all day on their due date.
    func isDue(_ m: CardMemory, now: Date, calendar: Calendar) -> Bool {
        if m.due <= now + rules.learnAhead { return true }
        return m.phase == .review && calendar.startOfDay(for: m.due) <= calendar.startOfDay(for: now)
    }
}

/// Observations the study features write besides reviews.
public enum StudyObservations {
    /// 加词: "I want to learn this word" (Word Planning schedules it first).
    public static func wish(_ lemma: String, at now: Date, lexiconVersion: String? = nil) -> Observation {
        Observation(ts: Timestamp.iso(now.timeIntervalSince1970), lemma: lemma, source: .wish,
                    result: ObservationResult.add, lexicon: lexiconVersion)
    }

    /// 每日新词上限.
    public static func dailyNewLimit(_ limit: Int, at now: Date) -> Observation {
        Observation(ts: Timestamp.iso(now.timeIntervalSince1970), lemma: SettingKey.dailyNewLimit,
                    source: .setting, result: String(limit))
    }

    /// 重新学 on a Leech.
    public static func relearn(_ lemma: String, at now: Date) -> Observation {
        Observation(ts: Timestamp.iso(now.timeIntervalSince1970), lemma: lemma, source: .relearn,
                    result: ObservationResult.reset)
    }
}

public enum StudySettings {
    public static let defaultDailyNewLimit = 10

    /// The latest daily-limit setting Observation, or the default.
    public static func dailyNewLimit(from observations: [Observation]) -> Int {
        observations.last { $0.source == .setting && $0.lemma == SettingKey.dailyNewLimit }
            .flatMap { Int($0.result) } ?? defaultDailyNewLimit
    }
}
