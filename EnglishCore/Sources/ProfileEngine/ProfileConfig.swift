/// Tunable parameters of the Profile Engine. All defaults are initial values
/// meant to be adjusted with real data (Observations are append-only, so a
/// change just means recomputing).
public struct ProfileConfig: Sendable, Equatable {
    /// Evidence older than this many days counts half as much.
    public var halfLifeDays: Double = 180
    /// Mastered when P >= this.
    public var masteredThreshold: Double = 0.9
    /// Target window: lemma rank within (estimated lemma vocabulary + this).
    public var targetWindow: Int = 2000
    /// A card with this many `again` ratings is a Leech and no longer active.
    public var leechLapses: Int = 8
    /// Reference point of the difficulty scale: δ_w = slope · (ln rank_w − ln referenceRank).
    public var referenceRank: Double = 1000

    // Evidence weights.
    public var testWeight: Double = 1.0
    public var verifyWeight: Double = 1.5
    public var reviewWeight: Double = 1.0
    /// A new card's first rating of "too easy".
    public var firstEasyWeight: Double = 4.0

    // Priors of the global fit (θ = logit P at referenceRank; slope per ln rank).
    public var thetaPriorMean: Double = 2.0
    public var thetaPriorSD: Double = 3.0
    public var slopePriorMean: Double = 1.8
    public var slopePriorSD: Double = 1.5
    /// Beta prior on the pseudoword false-alarm rate (the guessing floor of Yes/No answers).
    public var falseAlarmPriorMean: Double = 0.01
    public var falseAlarmPriorStrength: Double = 50
    /// Rate of "no" to a known word in Yes/No items (mis-taps, inattention).
    public var slipRate: Double = 0.03
    /// SD of a word's own deviation from the frequency-based prediction.
    public var wordSD: Double = 2.5

    /// Reference time for decay (ISO 8601). Default: the latest Observation.
    public var asOf: String?

    public init() {}
}
