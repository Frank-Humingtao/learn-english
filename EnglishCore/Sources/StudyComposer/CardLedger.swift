import CoreModels
import Foundation

/// Leech and auto-reintroduction thresholds (initial values; see spec "阈值未定稿").
public struct CardRules: Sendable, Equatable {
    /// "忘了" this many times since the card was (re)started makes it a Leech.
    public var leechLapses = 8
    /// A Leech restarts as a new card this long after it was paused.
    public var leechCooldownDays = 30.0
    /// Learning-step cards due within this window count as due now (Anki's "learn ahead").
    public var learnAhead: TimeInterval = 20 * 60

    public init() {}
}

/// Why a card is not being shown. Mastered is not here: that depends on P, which the composer checks.
public enum SuspendReason: Sendable, Equatable {
    /// A new card's first rating was 太简单.
    case firstEasy
    /// Forgotten `leechLapses` times; paused until reintroduced.
    case leech
}

/// One Card as reconstructed from the Observation history.
public struct CardRecord: Sendable, Equatable {
    public var lemma: String
    public var memory: CardMemory
    /// First rating since the card was (re)started; nil while new.
    public var firstGrade: Grade?
    public var firstReviewAt: Date?
    /// "忘了" count since the card was (re)started.
    public var lapses: Int
    public var suspended: SuspendReason?
    /// When the card became a Leech.
    public var leechSince: Date?
    /// True for a former Leech restarted as a new card (manually or after the cooldown).
    public var reintroduced: Bool
    /// When it was last restarted.
    public var resetAt: Date?

    public var isNew: Bool { firstGrade == nil }
}

/// A paused Leech, for the 进度 tab's list.
public struct Leech: Sendable, Equatable {
    public var lemma: String
    public var lapses: Int
    public var since: Date
    /// When it comes back automatically.
    public var reintroduceAt: Date
}

/// Every Card's current state, replayed from review / relearn Observations with the scheduler.
/// Cards are not stored anywhere else: Observations are the source of truth.
public struct CardLedger: Sendable {
    public private(set) var cards: [String: CardRecord] = [:]
    public let now: Date

    public init(observations: [Observation], scheduler: CardScheduler, rules: CardRules = CardRules(), now: Date) {
        self.now = now
        let events = observations.compactMap { o -> (Date, Observation)? in
            guard o.source == .review || o.source == .relearn,
                  let t = Timestamp.epochSeconds(o.ts), t <= now.timeIntervalSince1970 else { return nil }
            return (Date(timeIntervalSince1970: t), o)
        }
        .enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element)

        let cooldown = rules.leechCooldownDays * 86400
        func restart(_ r: inout CardRecord, at t: Date) {
            r = CardRecord(lemma: r.lemma, memory: scheduler.newCard(at: t), firstGrade: nil, firstReviewAt: nil,
                           lapses: 0, suspended: nil, leechSince: nil, reintroduced: true, resetAt: t)
        }

        for (t, o) in events {
            var r = cards[o.lemma] ?? CardRecord(lemma: o.lemma, memory: scheduler.newCard(at: t), firstGrade: nil,
                                                 firstReviewAt: nil, lapses: 0, suspended: nil, leechSince: nil,
                                                 reintroduced: false, resetAt: nil)
            if let since = r.leechSince, t.timeIntervalSince(since) >= cooldown { restart(&r, at: since + cooldown) }
            if o.source == .relearn {
                if cards[o.lemma] != nil { restart(&r, at: t) }
            } else if let g = Grade(result: o.result) {
                r.memory = scheduler.review(r.memory, g, at: t)
                if r.firstGrade == nil {
                    r.firstGrade = g
                    r.firstReviewAt = t
                    if g == .easy { r.suspended = .firstEasy }
                }
                if g == .again {
                    r.lapses += 1
                    if r.lapses >= rules.leechLapses && r.leechSince == nil {
                        r.leechSince = t
                        r.suspended = .leech
                    }
                }
            }
            if cards[o.lemma] != nil || o.source == .review { cards[o.lemma] = r }
        }
        for (lemma, var r) in cards {
            if let since = r.leechSince, now.timeIntervalSince(since) >= cooldown {
                restart(&r, at: since + cooldown)
                cards[lemma] = r
            }
        }
        leechCooldown = cooldown
    }

    private var leechCooldown: TimeInterval = 0

    /// Paused Leeches, longest-paused first.
    public var leeches: [Leech] {
        cards.values.compactMap { r in
            r.leechSince.map { Leech(lemma: r.lemma, lapses: r.lapses, since: $0, reintroduceAt: $0 + leechCooldown) }
        }
        .sorted { ($0.since, $0.lemma) < ($1.since, $1.lemma) }
    }

    /// Words with a card being studied (not new-and-unseen, not suspended).
    public var activeCards: Set<String> {
        Set(cards.values.filter { !$0.isNew && $0.suspended == nil }.map(\.lemma))
    }
}
