import Foundation

/// Probabilistic prediction scores of a set of binary outcomes.
public struct Scores: Codable, Sendable, Equatable {
    public var n: Int
    /// Mean negative log-likelihood (natural log), predictions clipped to [1e-6, 1 − 1e-6].
    public var logLoss: Double
    /// Mean squared error of the probability.
    public var brier: Double
    /// Area under the ROC curve; nil when all outcomes are the same.
    public var auc: Double?
    /// Expected calibration error over 10 equal-width bins.
    public var ece: Double
    public var meanPredicted: Double
    public var observedRate: Double

    /// nil when there is nothing to score.
    public init?(predictions p: [Double], outcomes y: [Double]) {
        precondition(p.count == y.count)
        guard !p.isEmpty else { return nil }
        n = p.count
        logLoss = rounded(Metrics.logLoss(p, y))
        brier = rounded(Metrics.brier(p, y))
        auc = Metrics.auc(p, y).map(rounded)
        ece = rounded(Metrics.ece(p, y))
        meanPredicted = rounded(p.reduce(0, +) / Double(n))
        observedRate = rounded(y.reduce(0, +) / Double(n))
    }
}

public enum Metrics {
    static let clip = 1e-6

    public static func logLoss(_ p: [Double], _ y: [Double]) -> Double {
        var s = 0.0
        for (pi, yi) in zip(p, y) {
            let q = min(max(pi, clip), 1 - clip)
            s -= yi * log(q) + (1 - yi) * log(1 - q)
        }
        return s / Double(p.count)
    }

    public static func brier(_ p: [Double], _ y: [Double]) -> Double {
        zip(p, y).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } / Double(p.count)
    }

    /// Mann–Whitney AUC with average ranks for ties.
    public static func auc(_ p: [Double], _ y: [Double]) -> Double? {
        let pos = y.filter { $0 >= 0.5 }.count, neg = y.count - pos
        guard pos > 0, neg > 0 else { return nil }
        let order = p.indices.sorted { p[$0] < p[$1] }
        var rank = [Double](repeating: 0, count: p.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count && p[order[j + 1]] == p[order[i]] { j += 1 }
            let r = Double(i + j) / 2 + 1
            for k in i...j { rank[order[k]] = r }
            i = j + 1
        }
        let sumPos = p.indices.filter { y[$0] >= 0.5 }.reduce(0.0) { $0 + rank[$1] }
        return (sumPos - Double(pos) * Double(pos + 1) / 2) / (Double(pos) * Double(neg))
    }

    /// Σ_b (n_b / N)·|mean p_b − mean y_b| over `bins` equal-width bins of p.
    public static func ece(_ p: [Double], _ y: [Double], bins: Int = 10) -> Double {
        var n = [Double](repeating: 0, count: bins), sp = n, sy = n
        for (pi, yi) in zip(p, y) {
            let b = min(bins - 1, max(0, Int(pi * Double(bins))))
            n[b] += 1
            sp[b] += pi
            sy[b] += yi
        }
        var e = 0.0
        for b in 0..<bins where n[b] > 0 { e += abs(sp[b] - sy[b]) }
        return e / Double(p.count)
    }
}
