import Foundation

public enum LexiconError: Error, CustomStringConvertible {
    case missingFile(String)
    case malformed(file: String, line: Int, reason: String)

    public var description: String {
        switch self {
        case .missingFile(let f): return "lexicon file missing: \(f)"
        case .malformed(let f, let l, let r): return "\(f):\(l): \(r)"
        }
    }
}

extension Lexicon {
    /// Loads a lexicon directory produced by `tools/lexicon-build/build_lexicon.py`.
    public static func load(directory: URL) throws -> Lexicon {
        struct Meta: Decodable { var version: String }
        let meta = try JSONDecoder().decode(Meta.self, from: read(directory, "meta.json"))

        let words = try table(directory, "words.tsv")
        func col(_ name: String) throws -> Int {
            guard let i = words.header.firstIndex(of: name) else {
                throw LexiconError.malformed(file: "words.tsv", line: 1, reason: "no column \(name)")
            }
            return i
        }
        let c = try (lemma: col("lemma"), rank: col("rank"), family: col("family"), familyRank: col("family_rank"),
                     level: col("level"), phonetic: col("phonetic"), pos: col("pos"), tags: col("tags"),
                     definition: col("definition"), translation: col("translation"), example: col("example"),
                     audio: col("audio"))
        var entries: [LexiconEntry] = []
        entries.reserveCapacity(words.rows.count)
        for (n, r) in words.rows.enumerated() {
            guard r.count == words.header.count, let rank = Int(r[c.rank]), let fr = Int(r[c.familyRank]),
                  let level = Int(r[c.level])
            else { throw LexiconError.malformed(file: "words.tsv", line: n + 2, reason: "bad row") }
            entries.append(LexiconEntry(
                lemma: r[c.lemma], rank: rank, family: r[c.family], familyRank: fr, level: level,
                phonetic: r[c.phonetic], pos: r[c.pos], tags: r[c.tags], definition: r[c.definition],
                translation: r[c.translation], example: r[c.example], audio: r[c.audio]))
        }

        let formsTable = try table(directory, "forms.tsv")
        var forms: [String: String] = [:]
        for r in formsTable.rows where r.count >= 2 { forms[r[0]] = r[1] }

        let supp = String(decoding: try read(directory, "supplementary.txt"), as: UTF8.self)
        let supplementary = Set(supp.split(separator: "\n").map(String.init))

        return Lexicon(version: meta.version, entries: entries, forms: forms, supplementary: supplementary)
    }

    private static func read(_ dir: URL, _ name: String) throws -> Data {
        let url = dir.appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw LexiconError.missingFile(url.path)
        }
        return data
    }

    private static func table(_ dir: URL, _ name: String) throws -> (header: [String], rows: [[String]]) {
        let text = String(decoding: try read(dir, name), as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { throw LexiconError.malformed(file: name, line: 1, reason: "empty") }
        let header = lines.removeFirst().split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let rows = lines.map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).map { unescape($0) }
        }
        return (header, rows)
    }

    /// Reverses the build script's escaping of `\\`, `\t`, `\n`.
    static func unescape(_ s: Substring) -> String {
        guard s.contains("\\") else { return String(s) }
        var out = ""
        var it = s.makeIterator()
        while let ch = it.next() {
            guard ch == "\\", let next = it.next() else { out.append(ch); continue }
            switch next {
            case "n": out.append("\n")
            case "t": out.append("\t")
            default: out.append(next)
            }
        }
        return out
    }
}
