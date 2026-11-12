import CoreModels
import Foundation
import Lexicon
import ProfileEngine

/// Vocabulary size at the end of one test session (a point on the 进度 curve).
public struct VocabPoint: Sendable, Equatable {
    public var session: String
    /// Timestamp of the session's last answer.
    public var ts: String
    public var families: Estimate
}

/// Test days as the public dashboard counts them (`source == test` only).
public struct TestActivity: Sendable, Equatable {
    /// Local calendar day (yyyy-MM-dd) of the latest test answer.
    public var lastTestDay: String?
    /// Consecutive test days ending today or yesterday (0 once a full day is missed).
    public var streakDays: Int
}

/// Everything the 进度 tab shows, recomputed on device.
public struct ProgressReport: Sendable {
    public var profile: LearnerProfile
    public var leeches: [Leech]
    public var activity: TestActivity
}

/// The 进度 tab's numbers. Pure: Observations in, report out.
public enum ProgressPage {
    /// The current profile with the card ledger's active cards (so 重新学 and the Leech cooldown
    /// are respected), the Leech list and the test streak.
    public static func report(observations: [Observation], lexicon: Lexicon, composer: StudyComposer,
                              config: ProfileConfig = ProfileConfig(), now: Date, calendar: Calendar) -> ProgressReport {
        let ledger = composer.ledger(observations: observations, now: now)
        let profile = ProfileEngine.compute(observations: observations, lexicon: lexicon, config: config,
                                            activeCards: ledger.activeCards)
        return ProgressReport(profile: profile, leeches: ledger.leeches,
                              activity: testActivity(observations: observations, now: now, calendar: calendar))
    }

    /// One point per test session (by `session` id; Observations without one are grouped by day),
    /// ordered by session end. Each point is the profile computed from the Observations up to
    /// that session's end. Points in `reusing` with the same session and end are kept as is.
    public static func curve(observations: [Observation], lexicon: Lexicon, config: ProfileConfig = ProfileConfig(),
                             reusing cached: [VocabPoint] = []) -> [VocabPoint] {
        var ends: [String: (t: Double, ts: String)] = [:]
        for o in observations where o.source == .test {
            guard let t = Timestamp.epochSeconds(o.ts) else { continue }
            let key = o.session ?? String(o.ts.prefix(10))
            if let cur = ends[key], cur.t >= t { continue }
            ends[key] = (t, o.ts)
        }
        let timed = observations.map { (Timestamp.epochSeconds($0.ts), $0) }
        let cache = Dictionary(cached.map { ($0.session, $0) }, uniquingKeysWith: { a, _ in a })
        return ends.sorted { ($0.value.t, $0.key) < ($1.value.t, $1.key) }.map { session, end in
            if let hit = cache[session], hit.ts == end.ts { return hit }
            let upTo = timed.compactMap { t, o in t.map { $0 <= end.t } == true ? o : nil }
            var c = config
            c.asOf = end.ts
            let p = ProfileEngine.compute(observations: upTo, lexicon: lexicon, config: c)
            return VocabPoint(session: session, ts: end.ts, families: p.vocabulary.families)
        }
    }

    public static func testActivity(observations: [Observation], now: Date, calendar: Calendar) -> TestActivity {
        let days = Set(observations.compactMap { o -> Date? in
            guard o.source == .test, let t = Timestamp.epochSeconds(o.ts) else { return nil }
            return calendar.startOfDay(for: Date(timeIntervalSince1970: t))
        })
        let last = days.max().map { d -> String in
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        }
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return TestActivity(lastTestDay: last, streakDays: streak)
    }
}
