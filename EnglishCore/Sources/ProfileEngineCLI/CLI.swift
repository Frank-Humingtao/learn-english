import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import ProfileEval

/// `profile-engine` command line. Kept in a library so tests drive it in-process.
public enum ProfileEngineCLI {
    public static let usage = """
    usage:
      profile-engine profile  --lexicon DIR --observations PATH... --out DIR [--as-of ISO8601] [--half-life-days N]
          Recompute the Learner Profile; writes summary.json and words.tsv to DIR.
          PATH is a .jsonl file or a directory searched recursively for *.jsonl.
      profile-engine lookup   --lexicon DIR WORD...
      profile-engine coverage --lexicon DIR --observations PATH... [--text FILE]   (text from stdin if omitted)
      profile-engine version  --lexicon DIR
      profile-engine eval     --lexicon DIR --observations PATH... [--out DIR] [--models current,frequency]
                              [--folds N] [--sim-learners N] [--sim-seed N]
          Offline evaluation of each model side by side (held-out prediction, calibration, interval
          width, split-half and retest consistency, simulated Learners). Prints a Markdown table;
          with --out also writes eval.json and eval.md. --sim-learners is per ability × answer style
          (0 = no simulation).

    """

    struct UsageError: Error { var message: String }

    /// Runs the command; returns the process exit code (0 ok, 1 failure, 2 usage).
    public static func run(_ args: [String], stdout: (String) -> Void, stderr: (String) -> Void) -> Int32 {
        guard let command = args.first else {
            stderr(usage)
            return 2
        }
        do {
            let opts = try Options(Array(args.dropFirst()))
            switch command {
            case "profile": return try profile(opts, stdout: stdout, stderr: stderr)
            case "lookup": return try lookup(opts, stdout: stdout)
            case "coverage": return try coverage(opts, stdout: stdout, stderr: stderr)
            case "eval": return try eval(opts, stdout: stdout, stderr: stderr)
            case "version":
                stdout(try opts.lexicon().version + "\n")
                return 0
            case "help", "--help", "-h":
                stdout(usage)
                return 0
            default:
                throw UsageError(message: "unknown command \(command)")
            }
        } catch let e as UsageError {
            stderr("error: \(e.message)\n\n\(usage)")
            return 2
        } catch {
            stderr("error: \(error)\n")
            return 1
        }
    }

    struct Options {
        var values: [String: [String]] = [:]
        var positional: [String] = []

        init(_ args: [String]) throws {
            var key: String?
            for a in args {
                if a.hasPrefix("--") {
                    key = String(a.dropFirst(2))
                    values[key!, default: []] += []
                } else if let k = key {
                    values[k, default: []].append(a)
                    if k != "observations" { key = nil }
                } else {
                    positional.append(a)
                }
            }
        }

        func one(_ k: String) throws -> String {
            guard let v = values[k]?.first else { throw UsageError(message: "missing --\(k)") }
            return v
        }

        func lexicon() throws -> Lexicon {
            try Lexicon.load(directory: URL(fileURLWithPath: one("lexicon")))
        }

        func config() throws -> ProfileConfig {
            var c = ProfileConfig()
            if let s = values["as-of"]?.first {
                guard Timestamp.epochSeconds(s) != nil else { throw UsageError(message: "bad --as-of \(s)") }
                c.asOf = s
            }
            if let s = values["half-life-days"]?.first {
                guard let d = Double(s), d > 0 else { throw UsageError(message: "bad --half-life-days \(s)") }
                c.halfLifeDays = d
            }
            return c
        }

        func observationPaths() throws -> [String] {
            guard let paths = values["observations"], !paths.isEmpty else {
                throw UsageError(message: "missing --observations")
            }
            return paths
        }
    }

    // MARK: commands

    static func profile(_ o: Options, stdout: (String) -> Void, stderr: (String) -> Void) throws -> Int32 {
        let paths = try o.observationPaths()
        let outDir = try o.one("out")
        let config = try o.config()
        let lexicon = try o.lexicon()
        let observations = try loadObservations(paths, stderr: stderr)
        let p = ProfileEngine.compute(observations: observations, lexicon: lexicon, config: config)
        let out = URL(fileURLWithPath: outDir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try write(ProfileFiles.summaryJSON(p), to: out.appendingPathComponent("summary.json"))
        try write(ProfileFiles.wordsTSV(p), to: out.appendingPathComponent("words.tsv"))
        stdout("vocabulary ≈ \(Int(p.vocabulary.families.estimate.rounded())) families "
            + "[\(Int(p.vocabulary.families.low.rounded())), \(Int(p.vocabulary.families.high.rounded()))]; "
            + "mastered \(p.bandCounts.mastered), target \(p.bandCounts.target), distant \(p.bandCounts.distant)\n")
        return 0
    }

    static func lookup(_ o: Options, stdout: (String) -> Void) throws -> Int32 {
        guard !o.positional.isEmpty else { throw UsageError(message: "lookup needs at least one word") }
        let lexicon = try o.lexicon()
        var missing = false
        for w in o.positional {
            guard let e = lexicon.lookup(w) else {
                stdout("\(w): not in lexicon \(lexicon.version)\n\n")
                missing = true
                continue
            }
            var s = "\(e.lemma)  /\(e.phonetic)/\n"
            s += "rank \(e.rank) · family \(e.family) (#\(e.familyRank)) · level \(e.level)k"
            if !e.tags.isEmpty { s += " · \(e.tags)" }
            s += "\n"
            if !e.definition.isEmpty { s += "definition:\n" + indent(e.definition) }
            if !e.translation.isEmpty { s += "中文:\n" + indent(e.translation) }
            s += "example: \(e.example.isEmpty ? "-" : e.example)\n"
            s += "audio: \(e.audio.isEmpty ? "-" : e.audio)\n\n"
            stdout(s)
        }
        return missing ? 1 : 0
    }

    static func coverage(_ o: Options, stdout: (String) -> Void, stderr: (String) -> Void) throws -> Int32 {
        let paths = try o.observationPaths()
        let config = try o.config()
        let lexicon = try o.lexicon()
        let text: String
        if let file = o.values["text"]?.first {
            guard let data = FileManager.default.contents(atPath: file) else { throw UsageError(message: "cannot read \(file)") }
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        let p = ProfileEngine.compute(observations: try loadObservations(paths, stderr: stderr), lexicon: lexicon,
                                      config: config)
        let c = p.coverage(of: text)
        stdout("{\"tokens\": \(c.tokens), \"known\": \(ProfileFiles.fixed(c.known, 4)), "
            + "\"mastered\": \(ProfileFiles.fixed(c.mastered, 4)), \"out_of_lexicon\": \(c.outOfLexicon)}\n")
        return 0
    }

    /// Models `eval` can compare, by name.
    static func evalModels(_ names: String, config: ProfileConfig) throws -> [any VocabularyModel] {
        try names.split(separator: ",").map { name -> any VocabularyModel in
            switch name {
            case "current": return CurrentProfileModel(config: config)
            case "frequency": return FrequencyBaselineModel()
            default: throw UsageError(message: "unknown model \(name) (known: current, frequency)")
            }
        }
    }

    static func eval(_ o: Options, stdout: (String) -> Void, stderr: (String) -> Void) throws -> Int32 {
        let paths = try o.observationPaths()
        let lexicon = try o.lexicon()
        let models = try evalModels(o.values["models"]?.first ?? "current,frequency", config: o.config())
        var options = EvalOptions()
        if let s = o.values["folds"]?.first {
            guard let k = Int(s), k >= 0 else { throw UsageError(message: "bad --folds \(s)") }
            options.folds = k
        }
        if let s = o.values["sim-learners"]?.first {
            guard let k = Int(s), k >= 0 else { throw UsageError(message: "bad --sim-learners \(s)") }
            if k == 0 { options.simulation = nil } else { options.simulation?.learnersPerSetting = k }
        }
        if let s = o.values["sim-seed"]?.first {
            guard let k = UInt64(s) else { throw UsageError(message: "bad --sim-seed \(s)") }
            options.simulation?.seed = k
        }
        let observations = try loadObservations(paths, stderr: stderr)
        let report = Evaluation.run(observations: observations, lexicon: lexicon, models: models, options: options)
        let table = report.table()
        if let dir = o.values["out"]?.first {
            let out = URL(fileURLWithPath: dir)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try write(try report.json(), to: out.appendingPathComponent("eval.json"))
            try write(table, to: out.appendingPathComponent("eval.md"))
        }
        stdout(table)
        return 0
    }

    // MARK: helpers

    /// Reads Observations from .jsonl files / directories. Malformed lines are skipped
    /// (reported on stderr) so one bad line can never block recomputation of an
    /// append-only history.
    public static func loadObservations(_ paths: [String], stderr: (String) -> Void) throws -> [Observation] {
        var files: [String] = []
        let fm = FileManager.default
        for path in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                throw UsageError(message: "no such file or directory: \(path)")
            }
            if isDir.boolValue {
                let base = URL(fileURLWithPath: path)
                guard let e = fm.enumerator(atPath: path) else { continue }
                var found: [String] = []
                while let rel = e.nextObject() as? String {
                    if rel.hasSuffix(".jsonl") { found.append(rel) }
                }
                files += found.sorted().map { base.appendingPathComponent($0).path }
            } else {
                files.append(path)
            }
        }
        let decoder = JSONDecoder()
        var out: [Observation] = []
        var bad = 0
        for f in files {
            guard let data = fm.contents(atPath: f) else { throw UsageError(message: "cannot read \(f)") }
            for line in data.split(separator: UInt8(ascii: "\n")) where !line.allSatisfy({ $0 == 32 || $0 == 13 }) {
                if let o = try? decoder.decode(Observation.self, from: Data(line)) {
                    out.append(o)
                } else {
                    bad += 1
                }
            }
        }
        if bad > 0 { stderr("warning: skipped \(bad) malformed observation line(s)\n") }
        return out
    }

    static func write(_ s: String, to url: URL) throws {
        try Data(s.utf8).write(to: url)
    }

    static func indent(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n") + "\n"
    }
}
