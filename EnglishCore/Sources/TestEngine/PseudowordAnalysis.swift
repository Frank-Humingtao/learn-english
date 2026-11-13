import CoreModels
import Lexicon

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Item analysis of the pseudowords already shown (research 07 §4.1: only some pseudowords carry
/// information; Stubbe & Stewart 2012 kept 9 of 32).
///
/// Pseudowords are never reused (a remembered fake would no longer test anything), so the
/// analysis works on shape classes rather than single items: orthographic neighbourhood size and a
/// suffix-like ending. A class whose false-alarm rate is clearly above that of all other
/// pseudowords is retired: those items are mistaken for a real neighbour or a derived form, so a
/// "yes" mostly measures form confusion, inflating f₀ and over-correcting real-word "yes" answers.
/// The generator then no longer produces that class.
public struct PseudowordAnalysis: Sendable {
    public struct Row: Sendable, Equatable {
        public var shape: PseudowordShape
        public var shown: Int
        public var falseAlarms: Int
        public var rate: Double { shown > 0 ? Double(falseAlarms) / Double(shown) : 0 }
        public var retired: Bool
    }

    public var rows: [Row]
    public var retired: Set<PseudowordShape> { Set(rows.filter(\.retired).map(\.shape)) }

    /// A class needs at least this many shown pseudowords before it can be retired…
    public static let minShown = 20
    /// …and a false-alarm rate above the rest by this one-sided z (≈ p < .01) and at least twice
    /// the rest's rate.
    public static let zThreshold = 2.33

    public init(history: [Observation], lexicon: Lexicon) {
        self.init(history: history, generator: Pseudowords(lexicon: lexicon))
    }

    init(history: [Observation], generator: Pseudowords) {
        var counts: [PseudowordShape: (shown: Int, yes: Int)] = [:]
        for o in history where o.pseudo == true {
            guard o.result == ObservationResult.yes || o.result == ObservationResult.no else { continue }
            let shape = generator.shape(o.lemma.lowercased())
            var c = counts[shape] ?? (0, 0)
            c.shown += 1
            if o.result == ObservationResult.yes { c.yes += 1 }
            counts[shape] = c
        }
        let total = counts.values.reduce((0, 0)) { ($0.0 + $1.shown, $0.1 + $1.yes) }
        rows = counts.keys.sorted { ($0.neighbors, $0.suffixLike ? 1 : 0) < ($1.neighbors, $1.suffixLike ? 1 : 0) }.map { shape in
            let c = counts[shape]!
            let restShown = total.0 - c.shown, restYes = total.1 - c.yes
            var retire = false
            if c.shown >= Self.minShown && restShown >= Self.minShown {
                // Two-proportion z test against all other pseudowords (pooled variance).
                let p1 = Double(c.yes) / Double(c.shown), p2 = Double(restYes) / Double(restShown)
                let pooled = Double(total.1) / Double(total.0)
                let se = (pooled * (1 - pooled) * (1 / Double(c.shown) + 1 / Double(restShown))).squareRoot()
                retire = se > 0 && (p1 - p2) / se > Self.zThreshold && p1 >= 2 * p2
            }
            return Row(shape: shape, shown: c.shown, falseAlarms: c.yes, retired: retire)
        }
    }
}
