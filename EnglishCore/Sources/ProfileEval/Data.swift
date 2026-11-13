import CoreModels
import Foundation
import Lexicon

/// One real-word answer the evaluation can score: a Yes/No answer (y = 1 for "yes") or a
/// meaning check (y = 1 for correct; wrong and "不认识" are 0) about a word in the lexicon.
public struct ScoredItem: Sendable, Equatable {
    /// Position in the input Observation array.
    public var observation: Int
    /// Index into `lexicon.entries`.
    public var entry: Int
    public var kind: ItemKind
    public var y: Double

    /// Scorable items of `observations`, in input order. Pseudowords, words outside the lexicon,
    /// other sources and unparsable results are skipped.
    public static func extract(_ observations: [Observation], lexicon: Lexicon) -> [ScoredItem] {
        var out: [ScoredItem] = []
        for (i, o) in observations.enumerated() where o.pseudo != true {
            guard let item = item(o, at: i, lexicon: lexicon) else { continue }
            out.append(item)
        }
        return out
    }

    static func item(_ o: Observation, at i: Int, lexicon: Lexicon) -> ScoredItem? {
        guard o.pseudo != true, let lemma = lexicon.lemma(for: o.lemma), let e = lexicon.index(of: lemma) else {
            return nil
        }
        switch o.source {
        case .test, .spotcheck:
            guard o.result == ObservationResult.yes || o.result == ObservationResult.no else { return nil }
            return ScoredItem(observation: i, entry: e, kind: .yesNo, y: o.result == ObservationResult.yes ? 1 : 0)
        case .verify:
            return ScoredItem(observation: i, entry: e, kind: .verify, y: o.result == ObservationResult.correct ? 1 : 0)
        default:
            return nil
        }
    }
}

/// Observations of one Vocabulary Test sitting, grouped by the `session` field
/// (Observations without one are grouped by UTC day).
struct Session {
    var id: String
    var start: Double
    /// Observation indices in time order (ties by input order).
    var observations: [Int]
    var items: [ScoredItem]
    var pseudowords: Int

    static func group(_ observations: [Observation], lexicon: Lexicon) -> [Session] {
        var byID: [String: [(t: Double, i: Int)]] = [:]
        for (i, o) in observations.enumerated() {
            guard let t = Timestamp.epochSeconds(o.ts) else { continue }
            let id = o.session ?? "day-" + String(o.ts.prefix(10))
            byID[id, default: []].append((t, i))
        }
        var sessions: [Session] = []
        for (id, list) in byID {
            let sorted = list.sorted { $0.t != $1.t ? $0.t < $1.t : $0.i < $1.i }
            let idx = sorted.map(\.i)
            let items = idx.compactMap { ScoredItem.item(observations[$0], at: $0, lexicon: lexicon) }
            let pseudo = idx.filter { observations[$0].pseudo == true }.count
            sessions.append(Session(id: id, start: sorted[0].t, observations: idx, items: items, pseudowords: pseudo))
        }
        return sessions.sorted { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
    }
}

/// Deterministic SplitMix64 (the same sequence on every platform).
public struct SeededRNG: RandomNumberGenerator, Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func gaussian() -> Double {
        let u1 = max(uniform(), 1e-12), u2 = uniform()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// FNV-1a: a stable string hash (Swift's `hashValue` is seeded per process).
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 0x0000_0100_0000_01B3
    }
    return h
}
