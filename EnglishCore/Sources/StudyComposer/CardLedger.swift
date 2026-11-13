import CoreModels
import Foundation

/// Card study thresholds. The Leech rule is the shared `LeechRule` (also used by the Profile Engine).
public struct CardRules: Sendable, Equatable {
    public var leech = LeechRule()
    /// Learning-step cards due within this window count as due now (Anki's "learn ahead").
    public var learnAhead: TimeInterval = 20 * 60

    public init() {}
}

/// Why a card is not being shown. Mastered is not here: that depends on P, which the composer checks.
public enum SuspendReason: Sendable, Equatable {
    /// A new card's first rating was 太简单.
    case firstEasy
    /// Forgotten `LeechRule.lapses` times; paused until reintroduced.
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

/// Every Card's current state: the shared `CardReplay` (first rating, lapses, Leech, cooldown,
/// 重新学) plus FSRS memory from replaying each card's ratings since its (re)start.
/// Cards are not stored anywhere else: Observations are the source of truth.
public struct CardLedger: Sendable {
    public private(set) var cards: [String: CardRecord] = [:]
    public let now: Date
    private let leechCooldown: TimeInterval

    public init(observations: [Observation], scheduler: CardScheduler, rules: CardRules = CardRules(), now: Date) {
        self.now = now
        leechCooldown = rules.leech.cooldownSeconds
        let replay = CardReplay(observations: observations, rule: rules.leech, asOf: now.timeIntervalSince1970)
        func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }
        for (lemma, h) in replay.cards {
            var memory = scheduler.newCard(at: date(h.startedAt))
            for r in h.reviews { memory = scheduler.review(memory, Grade(rawValue: r.ease)!, at: date(r.t)) }
            let suspended: SuspendReason? = switch h.paused {
            case .firstEasy: .firstEasy
            case .leech: .leech
            case nil: nil
            }
            cards[lemma] = CardRecord(lemma: lemma, memory: memory, firstGrade: h.firstEase.flatMap(Grade.init(rawValue:)),
                                      firstReviewAt: h.firstReviewAt.map(date), lapses: h.lapses, suspended: suspended,
                                      leechSince: h.leechSince.map(date), reintroduced: h.reintroduced,
                                      resetAt: h.resetAt.map(date))
        }
    }

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
