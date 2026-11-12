/// Leech thresholds (initial values; see spec "阈值未定稿"). One copy, used by the Profile Engine,
/// the card study ledger and — mirrored and checked against a shared fixture — the Python scripts.
public struct LeechRule: Sendable, Equatable {
    /// "忘了" this many times since the card was (re)started makes it a Leech.
    public var lapses = 8
    /// A Leech restarts as a new card this long after it was paused.
    public var cooldownDays = 30.0

    public init() {}

    public var cooldownSeconds: Double { cooldownDays * 86400 }
}

/// Why a card is paused. Mastered is not here: that depends on P, which callers check.
public enum CardPause: String, Sendable, Equatable {
    /// A new card's first rating was 太简单.
    case firstEasy = "first_easy"
    /// Forgotten `LeechRule.lapses` times; paused until reintroduced.
    case leech
}

/// One Card's scheduler-independent history: what is known from its review / relearn
/// Observations alone (no FSRS memory state).
public struct CardHistory: Sendable, Equatable {
    public var lemma: String
    /// When the current card (re)started: its first review, or the restart time.
    public var startedAt: Double
    /// Ratings (Anki ease 1-4) since the card (re)started, with their times, oldest first.
    public var reviews: [(t: Double, ease: Int)]
    /// First rating since the card was (re)started; nil while new.
    public var firstEase: Int? { reviews.first?.ease }
    public var firstReviewAt: Double? { reviews.first?.t }
    /// "忘了" count since the card was (re)started.
    public var lapses: Int
    public var paused: CardPause?
    /// When the card became a Leech.
    public var leechSince: Double?
    /// True for a former Leech restarted as a new card (manually or after the cooldown).
    public var reintroduced: Bool
    /// When it was last restarted.
    public var resetAt: Double?

    public var isNew: Bool { reviews.isEmpty }
    /// Being studied: started and not paused.
    public var isActive: Bool { !isNew && paused == nil }

    public static func == (a: CardHistory, b: CardHistory) -> Bool {
        a.lemma == b.lemma && a.startedAt == b.startedAt && a.reviews.map(\.t) == b.reviews.map(\.t)
            && a.reviews.map(\.ease) == b.reviews.map(\.ease) && a.lapses == b.lapses && a.paused == b.paused
            && a.leechSince == b.leechSince && a.reintroduced == b.reintroduced && a.resetAt == b.resetAt
    }
}

/// Replays review and relearn Observations up to `asOf` into every Card's history: first rating,
/// lapses since (re)start, Leech, the Leech cooldown and 重新学. The single implementation of these
/// rules: the Profile Engine's active cards and the study ledger both come from here.
///
/// Rules, in Observation time order (ties keep input order):
/// - a review with a valid rating (`result` again/hard/good/easy, else `review.ease` 1-4) starts a
///   card if there is none; invalid ratings are ignored;
/// - a Leech whose cooldown has passed by the next event (or by `asOf`) restarts at
///   `leechSince + cooldown`;
/// - a relearn Observation restarts an existing card at its time (ignored without a card);
/// - the first rating since (re)start being 太简单 pauses the card; the `lapses`-th 忘了 since
///   (re)start makes it a Leech.
public struct CardReplay: Sendable {
    public private(set) var cards: [String: CardHistory] = [:]
    public let rule: LeechRule
    public let asOf: Double

    public init(observations: [Observation], rule: LeechRule = LeechRule(), asOf: Double) {
        self.rule = rule
        self.asOf = asOf
        var events: [(t: Double, i: Int)] = []
        for (i, o) in observations.enumerated() {
            guard o.source == .review || o.source == .relearn,
                  let t = Timestamp.epochSeconds(o.ts), t <= asOf else { continue }
            if o.source == .review && o.reviewEase == nil { continue }
            events.append((t, i))
        }
        events.sort { $0.t != $1.t ? $0.t < $1.t : $0.i < $1.i }

        let cooldown = rule.cooldownSeconds
        func restart(_ r: inout CardHistory, at t: Double) {
            r = CardHistory(lemma: r.lemma, startedAt: t, reviews: [], lapses: 0, paused: nil, leechSince: nil,
                            reintroduced: true, resetAt: t)
        }
        func coolDown(_ r: inout CardHistory, by t: Double) {
            if let since = r.leechSince, t - since >= cooldown { restart(&r, at: since + cooldown) }
        }

        for (t, i) in events {
            let o = observations[i]
            if o.source == .relearn {
                guard var r = cards[o.lemma] else { continue }
                coolDown(&r, by: t)
                restart(&r, at: t)
                cards[o.lemma] = r
                continue
            }
            let ease = o.reviewEase!
            var r = cards[o.lemma] ?? CardHistory(lemma: o.lemma, startedAt: t, reviews: [], lapses: 0, paused: nil,
                                                  leechSince: nil, reintroduced: false, resetAt: nil)
            coolDown(&r, by: t)
            if r.reviews.isEmpty && ease == 4 { r.paused = .firstEasy }
            r.reviews.append((t, ease))
            if ease == 1 {
                r.lapses += 1
                if r.lapses >= rule.lapses && r.leechSince == nil {
                    r.leechSince = t
                    r.paused = .leech
                }
            }
            cards[o.lemma] = r
        }
        for (lemma, var r) in cards where r.leechSince != nil {
            coolDown(&r, by: asOf)
            cards[lemma] = r
        }
    }

    /// Lemmas with a card being studied (started, not paused).
    public var activeLemmas: Set<String> {
        Set(cards.values.filter(\.isActive).map(\.lemma))
    }
}

extension Observation {
    /// The rating of a review Observation as Anki's ease (1 again … 4 easy): from `result`,
    /// else from `review.ease`; nil when neither is valid.
    public var reviewEase: Int? {
        switch result {
        case ObservationResult.again: return 1
        case ObservationResult.hard: return 2
        case ObservationResult.good: return 3
        case ObservationResult.easy: return 4
        default:
            if let e = review?.ease, (1...4).contains(e) { return e }
            return nil
        }
    }
}
