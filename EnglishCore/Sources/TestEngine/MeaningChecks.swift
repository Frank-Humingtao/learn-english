import Lexicon

/// Chinese four-choice meaning checks. Distractors are the glosses of other lexicon words with the
/// same part of speech and nearby frequency rank (never AI-generated).
public enum MeaningChecks {
    /// A short Chinese gloss and its part of speech, parsed from an ECDICT translation such as
    /// `"vt. 发展, 使发达, 进步\nvi. 发展"` → (`v`, `发展；使发达；进步`). Domain lines (`[计] ...`) are skipped.
    public struct Gloss: Sendable, Equatable {
        public var pos: String
        public var text: String
        var firstSense: String
    }

    public static func gloss(_ entry: LexiconEntry) -> Gloss? {
        for raw in entry.translation.split(separator: "\n") {
            var line = raw.trimmingSpaces()
            guard !line.isEmpty, !line.hasPrefix("[") else { continue }
            var pos = ""
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy({ $0.isASCII && $0.isLetter }),
               line.distance(from: line.startIndex, to: dot) <= 5 {
                pos = normalizePOS(String(line[..<dot]))
                line = String(line[line.index(after: dot)...]).trimmingSpaces()
            }
            let senses = line.split(whereSeparator: { ",，;；".contains($0) })
                .map { $0.trimmingSpaces() }.filter { !$0.isEmpty }
            guard let first = senses.first, first.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF })
            else { continue }
            return Gloss(pos: pos, text: senses.prefix(3).joined(separator: "；"), firstSense: first)
        }
        return nil
    }

    static func normalizePOS(_ p: String) -> String {
        switch p.lowercased() {
        case "v", "vt", "vi", "aux": return "v"
        case "a", "adj", "s": return "adj"
        case "ad", "adv", "r": return "adv"
        default: return p.lowercased()
        }
    }

    /// Distractors are drawn at random from this many nearest same-POS words.
    static let neighborhood = 8

    static func item(for lemma: String, lexicon: Lexicon, rng: inout SplitMix64) -> MeaningCheckItem? {
        guard let idx = lexicon.index(of: lemma), let g = gloss(lexicon.entries[idx]) else { return nil }
        let entries = lexicon.entries
        func neighbors(samePOS: Bool) -> [Gloss] {
            var found: [Gloss] = []
            var firstSenses: Set<String> = [g.firstSense]
            var step = 1
            while found.count < neighborhood && step <= entries.count {
                for j in [idx - step, idx + step] where j >= 0 && j < entries.count {
                    guard let h = gloss(entries[j]), !samePOS || h.pos == g.pos, !firstSenses.contains(h.firstSense),
                          h.text != g.text
                    else { continue }
                    firstSenses.insert(h.firstSense)
                    found.append(h)
                }
                step += 1
                if samePOS && step > 2000 { break }
            }
            return found
        }
        var pool = neighbors(samePOS: true)
        if pool.count < 3 { pool = neighbors(samePOS: false) }
        guard pool.count >= 3 else { return nil }
        pool.shuffle(using: &rng)
        var options = [g.text] + pool.prefix(3).map(\.text)
        options.shuffle(using: &rng)
        return MeaningCheckItem(lemma: lemma, options: options, correctIndex: options.firstIndex(of: g.text)!)
    }
}

extension StringProtocol {
    func trimmingSpaces() -> String {
        var s = Substring(self)
        while let f = s.first, f.isWhitespace { s.removeFirst() }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return String(s)
    }
}
