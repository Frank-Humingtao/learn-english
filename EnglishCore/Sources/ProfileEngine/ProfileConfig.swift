import CoreModels

/// Tunable parameters of the Profile Engine. Defaults were chosen with the offline evaluation
/// (`profile-engine eval`, ticket 02); Observations are append-only, so a change just means recomputing.
public struct ProfileConfig: Sendable, Equatable {
    /// Evidence older than this many days counts half as much.
    public var halfLifeDays: Double = 180
    /// Mastered when P >= this.
    public var masteredThreshold: Double = 0.9
    /// Target window: lemma rank within (estimated lemma vocabulary + this).
    public var targetWindow: Int = 2000
    /// Totals are also reported split into BNC/COCA levels ≤ this and above it.
    public var coreLevels: Int = 14

    // Knowledge layer: P_know(w) = σ(θ − β·x_w).
    /// Word features x_w; the first one is the main frequency scale, the rest are regularized toward 0.
    public var features: [WordFeature] = WordFeature.defaultSet
    public var thetaPriorMean: Double = 2.0
    public var thetaPriorSD: Double = 3.0
    /// Prior of the main feature's weight (difficulty per unit of ln frequency rank).
    public var mainSlopePriorMean: Double = 1.6
    public var mainSlopePriorSD: Double = 1.0
    /// Ridge prior SD of every other feature weight.
    public var featurePriorSD: Double = 0.5
    /// Per-word deviation u_w ~ N(0, τ²) from the feature prediction: π_w = E_u σ(θ − β·x_w − u).
    /// τ is estimated from the data (it shapes the curve: flatter middle, frequency-driven tails)
    /// under a log-normal prior with this median and SD on the log scale.
    public var wordSDPrior: Double = 1.0
    public var wordSDPriorSD: Double = 0.5

    // Response layer.
    /// P("no" | word known) on Yes/No items (mis-taps, inattention).
    public var slipRate: Double = 0.03
    /// P(wrong | word known) on meaning checks.
    public var verifySlipRate: Double = 0.05
    /// Prior of the pseudoword false-alarm rate f₀ (logit-normal: median, SD on the logit scale).
    public var pseudowordFalseAlarmPrior: Double = 0.03
    public var pseudowordFalseAlarmPriorSD: Double = 1.5
    /// Real unknown words look more familiar than pseudowords: logit f = logit f₀ + δ, δ ~ N(mean, SD²).
    public var realWordExtraPriorMean: Double = 0.5
    public var realWordExtraPriorSD: Double = 0.5
    /// Prior of the guessing rate r of a meaning check about an unknown word (four choices plus
    /// "不认识"; Stoeckel et al. 2020: 14%–63%), logit-normal.
    public var verifyGuessPrior: Double = 0.3
    public var verifyGuessPriorSD: Double = 0.7

    // Evidence weights.
    /// A "yes" answered faster than this (ms) is implausibly fast for reading a word and deciding…
    public var fastYesMs: Int = 400
    /// …and counts only this much of a normal answer.
    public var fastYesWeight: Double = 0.5
    /// Session quality gate: a session whose pseudoword false-alarm rate exceeds this (with at least
    /// `gateMinPseudowords` pseudowords)…
    public var gateFalseAlarmRate: Double = 0.10
    public var gateMinPseudowords: Int = 10
    /// …or whose meaning checks after "yes" fail more often than this (with at least
    /// `gateMinChecks` checks) counts with this weight instead of being dropped.
    public var gateVerifyFailRate: Double = 0.30
    public var gateMinChecks: Int = 5
    public var gateWeight: Double = 0.5

    /// Person fit (lz) needs at least this many Yes/No answers to real words.
    public var personFitMinItems: Int = 20

    /// Reference time for decay (ISO 8601). Default: the latest Observation.
    public var asOf: String?

    public init() {}
}
