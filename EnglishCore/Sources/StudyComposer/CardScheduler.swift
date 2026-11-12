import CoreModels
import FSRS
import Foundation

/// The four review buttons: 忘了 / 模糊 / 想起 / 太简单 = FSRS Again / Hard / Good / Easy.
/// Raw values match Anki's revlog `ease`.
public enum Grade: Int, CaseIterable, Sendable, Hashable {
    case again = 1, hard, good, easy

    /// The Observation `result` string.
    public var result: String {
        switch self {
        case .again: ObservationResult.again
        case .hard: ObservationResult.hard
        case .good: ObservationResult.good
        case .easy: ObservationResult.easy
        }
    }

    public init?(result: String) {
        guard let g = Grade.allCases.first(where: { $0.result == result }) else { return nil }
        self = g
    }

    var rating: Rating { Rating(rawValue: rawValue)! }
}

/// FSRS parameters. Defaults are FSRS-6's published defaults with desired retention 0.9;
/// ticket 10 injects personal weights (the 21st weight, `w[20]`, is the forgetting-curve decay).
public struct FSRSConfig: Codable, Sendable, Equatable {
    /// 21 FSRS-6 weights (19 would select FSRS-5).
    public var weights: [Double]
    public var desiredRetention: Double
    public var learningSteps: [String]
    public var relearningSteps: [String]
    public var maximumIntervalDays: Double

    public init(weights: [Double] = FSRSDefaults.defaultWv6, desiredRetention: Double = 0.9,
                learningSteps: [String] = ["1m", "10m"], relearningSteps: [String] = ["10m"],
                maximumIntervalDays: Double = 36500) {
        self.weights = weights
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumIntervalDays = maximumIntervalDays
    }

    /// FSRS-6 decay (`w[20]`), nil for FSRS-5 weights.
    public var decay: Double? { weights.count > 20 ? weights[20] : nil }

    public static let `default` = FSRSConfig()

    enum CodingKeys: String, CodingKey {
        case weights = "w"
        case desiredRetention = "desired_retention"
        case learningSteps = "learning_steps"
        case relearningSteps = "relearning_steps"
        case maximumIntervalDays = "maximum_interval"
    }
}

/// One Card's FSRS memory state.
public struct CardMemory: Sendable, Equatable {
    public enum Phase: Int, Sendable { case new = 0, learning, review, relearning }

    var card: Card

    public var due: Date { card.due }
    public var stability: Double { card.stability }
    public var difficulty: Double { card.difficulty }
    public var phase: Phase { Phase(rawValue: card.state.rawValue)! }
    public var reps: Int { card.reps }
    public var lastReview: Date? { card.lastReview }
    /// Interval in whole days (0 while in a learning step).
    public var scheduledDays: Double { card.scheduledDays }
}

/// FSRS scheduling via swift-fsrs. Immutable and Sendable.
public struct CardScheduler: Sendable {
    public let config: FSRSConfig
    private let fsrs: FSRS

    public init(config: FSRSConfig = .default) {
        self.config = config
        fsrs = FSRS(parameters: FSRSParameters(
            requestRetention: config.desiredRetention, maximumInterval: config.maximumIntervalDays,
            w: config.weights, enableFuzz: false, enableShortTerm: true,
            learningSteps: config.learningSteps, relearningSteps: config.relearningSteps))
    }

    /// A card never reviewed, due at `now`.
    public func newCard(at now: Date) -> CardMemory {
        CardMemory(card: FSRSDefaults().createEmptyCard(now: now))
    }

    /// The card after rating it `grade` at `now`.
    public func review(_ memory: CardMemory, _ grade: Grade, at now: Date) -> CardMemory {
        // swift-fsrs only throws for `.manual` or invalid parameters (checked at init by FSRS itself).
        CardMemory(card: try! fsrs.next(card: memory.card, now: now, grade: grade.rating).card)
    }

    /// For each button, how long until the card is due again if pressed at `now` (seconds).
    public func intervals(_ memory: CardMemory, at now: Date) -> [Grade: TimeInterval] {
        let preview = try! fsrs.repeat(card: memory.card, now: now)
        var out: [Grade: TimeInterval] = [:]
        for g in Grade.allCases {
            if let item = preview[g.rating] { out[g] = item.card.due.timeIntervalSince(now) }
        }
        return out
    }

    /// The revlog-aligned fields stored with a review Observation.
    public func reviewLog(before: CardMemory, after: CardMemory, grade: Grade, at now: Date, rtMs: Int?) -> CoreModels.ReviewLog {
        func ivl(_ m: CardMemory, from: Date) -> Int {
            m.scheduledDays >= 1 ? Int(m.scheduledDays) : -Int(m.due.timeIntervalSince(from).rounded())
        }
        let type: Int = switch before.phase {
        case .new, .learning: 0
        case .review: 1
        case .relearning: 2
        }
        return CoreModels.ReviewLog(ease: grade.rawValue, ivl: ivl(after, from: now),
                         lastIvl: before.phase == .new ? 0 : ivl(before, from: before.lastReview ?? now),
                         type: type, time: rtMs, stability: after.stability, difficulty: after.difficulty,
                         due: Timestamp.iso(after.due.timeIntervalSince1970))
    }
}
