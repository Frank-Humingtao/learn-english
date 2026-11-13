import CoreModels
import Lexicon
import ProfileEngine

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Chooses the real words of a test (research 07 §B.7, ticket 03). Only words with a usable
/// Chinese gloss are eligible, so any "yes" can be meaning-checked.
struct ItemSelector: Sendable {
    let lexicon: Lexicon
    let pseudowords: Pseudowords
    /// Whether each entry has a gloss.
    let eligible: [Bool]
    /// Token-frequency weight of each entry, raised to `TestConfig.frequencyExponent`.
    let frequencyWeight: [Double]

    init(lexicon: Lexicon, config: TestConfig) {
        self.lexicon = lexicon
        pseudowords = Pseudowords(lexicon: lexicon)
        let entries = lexicon.entries
        eligible = entries.map { MeaningChecks.gloss($0) != nil }
        // Corpus token frequency; Zipf's law (∝ 1/rank) where the lexicon has none.
        let hasFreq = entries.contains { $0.freq > 0 }
        frequencyWeight = entries.map { e in
            let f = hasFreq ? Double(max(1, e.freq)) : 1e6 / Double(max(1, e.rank))
            return pow(f, config.frequencyExponent)
        }
    }

    struct Plan {
        var schedule: [YesNoItem.Kind]
        var stratified: [Int]
        var retest: [Int]
    }

    /// The fixed part of a test: the kind of every Yes/No slot (interleaved at random), the
    /// stratified sample and the retest words.
    func plan(profile: LearnerProfile, live: LiveEstimate, config: TestConfig, rng: inout SplitMix64) -> Plan {
        let real = max(0, config.realCount)
        let a = config.allocation
        let sum = max(1e-9, a.stratified + a.uncertain + a.boundary + a.retest)
        func share(_ x: Double) -> Int { Int((Double(real) * x / sum).rounded()) }

        var retestPool = lexicon.entries.indices.filter { eligible[$0] && live.answeredBefore($0) }
        partialShuffle(&retestPool, count: retestPool.count, rng: &rng)
        let retest = Array(retestPool.prefix(share(a.retest)))
        let uncertain = share(a.uncertain), boundary = share(a.boundary)
        let stratifiedCount = max(0, real - retest.count - uncertain - boundary)
        let stratified = stratifiedSample(profile: profile, live: live, count: stratifiedCount,
                                          minPerStratum: config.minPerStratum, rng: &rng)

        var schedule = [YesNoItem.Kind](repeating: .pseudoword, count: max(0, config.pseudowordCount))
        schedule += Array(repeating: .stratified, count: stratifiedCount)
        schedule += Array(repeating: .uncertain, count: uncertain)
        schedule += Array(repeating: .boundary, count: boundary)
        schedule += Array(repeating: .retest, count: retest.count)
        schedule.shuffle(using: &rng)
        return Plan(schedule: schedule, stratified: stratified, retest: retest)
    }

    /// Stratified random sample of word families: strata are BNC/COCA 1000-family levels, the unit
    /// is a family's most frequent eligible member not answered before, and stratum h gets
    /// n_h ∝ N_h·S_h (Neyman) with S_h = √(mean p(1 − p)) at the pre-test P, at least
    /// `minPerStratum` each. Returned in random order.
    func stratifiedSample(profile: LearnerProfile, live: LiveEstimate, count: Int, minPerStratum: Int,
                          rng: inout SplitMix64) -> [Int] {
        guard count > 0 else { return [] }
        let entries = lexicon.entries
        var familySize: [Int: Int] = [:] // level → families
        var units: [Int: [Int]] = [:] // level → eligible heads
        var spread: [Int: Double] = [:] // level → Σ p(1 − p) over heads
        var seen = Set<String>()
        var headTaken = Set<String>()
        for (i, e) in entries.enumerated() {
            if seen.insert(e.family).inserted { familySize[e.level, default: 0] += 1 }
            guard eligible[i], !live.answeredBefore(i), !headTaken.contains(e.family) else { continue }
            headTaken.insert(e.family)
            units[e.level, default: []].append(i)
            let p = profile.probabilities[i]
            spread[e.level, default: 0] += p * (1 - p)
        }
        let levels = units.keys.sorted()
        var weight: [Int: Double] = [:]
        for h in levels {
            let s = (spread[h]! / Double(units[h]!.count)).squareRoot()
            weight[h] = Double(familySize[h] ?? 0) * max(s, 0.02)
        }
        let n = neyman(levels: levels, weight: weight, capacity: units.mapValues(\.count), total: count,
                       minimum: minPerStratum)
        var out: [Int] = []
        for h in levels {
            var pool = units[h]!
            partialShuffle(&pool, count: n[h] ?? 0, rng: &rng)
            out += pool.prefix(n[h] ?? 0)
        }
        partialShuffle(&out, count: out.count, rng: &rng)
        return out
    }

    /// Neyman allocation with a per-stratum minimum and capacity, largest-remainder rounding.
    func neyman(levels: [Int], weight: [Int: Double], capacity: [Int: Int], total: Int, minimum: Int) -> [Int: Int] {
        var n: [Int: Int] = [:]
        var left = total
        for h in levels {
            let m = min(minimum, capacity[h] ?? 0, left)
            n[h] = m
            left -= m
        }
        var open = Set(levels.filter { (n[$0] ?? 0) < (capacity[$0] ?? 0) })
        while left > 0 && !open.isEmpty {
            let w = open.reduce(0.0) { $0 + (weight[$1] ?? 0) }
            guard w > 0 else { break }
            var quota: [(h: Int, whole: Int, frac: Double)] = []
            for h in open {
                let q = Double(left) * (weight[h] ?? 0) / w
                quota.append((h, Int(q), q - Double(Int(q))))
            }
            var given = 0
            for q in quota {
                let add = min(q.whole, (capacity[q.h] ?? 0) - (n[q.h] ?? 0))
                n[q.h, default: 0] += add
                given += add
            }
            for q in quota.sorted(by: { $0.frac != $1.frac ? $0.frac > $1.frac : $0.h < $1.h }) where given < left {
                if (n[q.h] ?? 0) < (capacity[q.h] ?? 0) {
                    n[q.h, default: 0] += 1
                    given += 1
                }
            }
            left -= given
            open = open.filter { (n[$0] ?? 0) < (capacity[$0] ?? 0) }
            if given == 0 { break }
        }
        return n
    }

    @inline(__always)
    func available(_ i: Int, _ live: LiveEstimate, _ used: Set<Int>) -> Bool {
        eligible[i] && !used.contains(i) && !live.hasEvidence(i)
    }

    /// A random one of the `pool` unanswered words whose current P is closest to 0.5.
    func boundary(live: LiveEstimate, used: Set<Int>, pool: Int, rng: inout SplitMix64) -> Int? {
        var best: [(d: Double, i: Int)] = []
        best.reserveCapacity(pool + 1)
        for i in lexicon.entries.indices where available(i, live, used) {
            let d = abs(live.priorProbability(i) - 0.5)
            if best.count < pool || d < best[best.count - 1].d {
                let at = best.firstIndex { $0.d > d } ?? best.count
                best.insert((d, i), at: at)
                if best.count > pool { best.removeLast() }
            }
        }
        guard !best.isEmpty else { return nil }
        return best[Int(rng.next() % UInt64(best.count))].i
    }

    /// An unanswered word drawn with probability ∝ P(1 − P)·frequency weight (Efraimidis–Spirakis).
    func uncertain(live: LiveEstimate, used: Set<Int>, rng: inout SplitMix64) -> Int? {
        var bestKey = -Double.infinity
        var best: Int?
        for i in lexicon.entries.indices where available(i, live, used) {
            let p = live.priorProbability(i)
            let w = p * (1 - p) * frequencyWeight[i]
            guard w > 0 else { continue }
            let key = log(max(rng.uniform(), 1e-300)) / w
            if key > bestKey {
                bestKey = key
                best = i
            }
        }
        return best
    }
}

/// Fisher–Yates on the first `count` positions.
func partialShuffle(_ a: inout [Int], count: Int, rng: inout SplitMix64) {
    guard a.count > 1 else { return }
    for i in 0..<min(count, a.count - 1) {
        let j = i + Int(rng.next() % UInt64(a.count - i))
        a.swapAt(i, j)
    }
}
