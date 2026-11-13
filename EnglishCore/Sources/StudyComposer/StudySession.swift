import CoreModels
import Foundation

/// One study session: due reviews, then a stop point ("复习完成，开始 N 个新词？"), then new cards.
/// Rating a card returns the review Observation to store. Cards whose next step is due within
/// the learn-ahead window (learning steps) come back later in the same phase.
public struct StudySession: Sendable {
    public enum Phase: Sendable, Equatable {
        case review(String)
        /// Reviews done; `newCount` new cards are waiting. The Learner may stop here.
        case separator(newCount: Int)
        case newCard(String)
        case done
    }

    public struct Summary: Sendable, Equatable {
        /// Distinct cards reviewed in the review phase.
        public var reviewed = 0
        /// New cards started (excluding those rated 太简单 at once).
        public var learned = 0
        /// New cards rated 太简单 at once (paused, replaced from the plan).
        public var tooEasy = 0
        /// Total button presses.
        public var ratings = 0

        public init(reviewed: Int = 0, learned: Int = 0, tooEasy: Int = 0, ratings: Int = 0) {
            self.reviewed = reviewed
            self.learned = learned
            self.tooEasy = tooEasy
            self.ratings = ratings
        }
    }

    /// As composed (replacements for 太简单 are appended to `newCards`).
    public private(set) var reviews: [String]
    public private(set) var newCards: [String]
    public private(set) var phase: Phase
    public private(set) var summary = Summary()
    public let plan: StudyPlan?
    public let sessionID: String?
    public let lexiconVersion: String?
    /// The Study Plan's state when the session was composed (stale / running low / used up).
    public let planStatus: PlanStatus

    private var queue: [String]
    private var pendingNew: [String]
    private var spare: [String]
    private var memories: [String: CardMemory]
    private var rated: Set<String> = []
    private let scheduler: CardScheduler
    private let learnAhead: TimeInterval

    init(reviews: [String], newCards: [String], spare: [String], memories: [String: CardMemory], plan: StudyPlan?,
         scheduler: CardScheduler, learnAhead: TimeInterval, sessionID: String?, lexiconVersion: String?,
         planStatus: PlanStatus = .current) {
        self.planStatus = planStatus
        self.reviews = reviews
        self.newCards = newCards
        self.spare = spare
        self.memories = memories
        self.plan = plan
        self.scheduler = scheduler
        self.learnAhead = learnAhead
        self.sessionID = sessionID
        self.lexiconVersion = lexiconVersion
        if let first = reviews.first {
            queue = reviews
            pendingNew = newCards
            phase = .review(first)
        } else {
            queue = newCards
            pendingNew = []
            phase = newCards.first.map(Phase.newCard) ?? .done
        }
    }

    /// The lemma on screen, if a card is showing.
    public var current: String? {
        switch phase {
        case .review(let l), .newCard(let l): l
        case .separator, .done: nil
        }
    }

    public var isEmpty: Bool { reviews.isEmpty && newCards.isEmpty }

    /// Cards left in the current phase, including the one showing.
    public var remainingInPhase: Int { queue.count }

    /// Time until the card is due again for each button, as swift-fsrs computes it.
    public func intervals(at now: Date) -> [Grade: TimeInterval] {
        guard let l = current, let m = memories[l] else { return [:] }
        return scheduler.intervals(m, at: now)
    }

    /// Rates the current card and moves on. Returns the review Observation to record.
    public mutating func rate(_ grade: Grade, rtMs: Int?, at now: Date) -> Observation? {
        guard let lemma = current, let before = memories[lemma] else { return nil }
        let newCardPhase = isNewPhase
        let after = scheduler.review(before, grade, at: now)
        memories[lemma] = after
        queue.removeFirst()
        summary.ratings += 1

        let firstSight = rated.insert(lemma).inserted
        if newCardPhase && firstSight && before.phase == .new && grade == .easy {
            // 太简单 on first sight: paused for good; take the next plan word instead.
            summary.tooEasy += 1
            if !spare.isEmpty {
                let next = spare.removeFirst()
                memories[next] = scheduler.newCard(at: now)
                newCards.append(next)
                queue.append(next)
            }
        } else {
            if firstSight { if newCardPhase { summary.learned += 1 } else { summary.reviewed += 1 } }
            if after.due <= now + learnAhead { queue.append(lemma) }
        }
        advance()
        return Observation(ts: Timestamp.iso(now.timeIntervalSince1970), lemma: lemma, source: .review,
                           result: grade.result, rtMs: rtMs, session: sessionID, lexicon: lexiconVersion,
                           review: scheduler.reviewLog(before: before, after: after, grade: grade, at: now, rtMs: rtMs))
    }

    /// From the separator: go on to the new cards.
    public mutating func startNewCards() {
        guard case .separator = phase else { return }
        queue = pendingNew
        pendingNew = []
        advance()
    }

    /// Stop now (e.g. at the separator). Progress so far is already recorded.
    public mutating func finish() {
        queue = []
        pendingNew = []
        phase = .done
    }

    private mutating func advance() {
        if let next = queue.first {
            phase = isNewPhase ? .newCard(next) : .review(next)
        } else if !pendingNew.isEmpty {
            phase = .separator(newCount: pendingNew.count)
        } else {
            phase = .done
        }
    }

    private var isNewPhase: Bool {
        switch phase {
        case .newCard: true
        case .separator: true
        default: false
        }
    }
}
