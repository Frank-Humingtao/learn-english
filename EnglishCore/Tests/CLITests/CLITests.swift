import Foundation
import ProfileEngineCLI
import Testing

let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

/// Captures what the CLI prints.
final class Capture: @unchecked Sendable {
    var out = ""
    var err = ""
}

func run(_ args: [String]) -> (code: Int32, out: String, err: String) {
    let c = Capture()
    let code = ProfileEngineCLI.run(args, stdout: { c.out += $0 }, stderr: { c.err += $0 })
    return (code, c.out, c.err)
}

func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-engine-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func contents(_ url: URL) -> String {
    String(decoding: FileManager.default.contents(atPath: url.path) ?? Data(), as: UTF8.self)
}

@Suite struct CLITests {
    let lexicon = fixtures.appendingPathComponent("lexicon").path
    let observations = fixtures.appendingPathComponent("observations").path

    /// The committed golden files were produced on macOS; the same test on Linux proves parity.
    @Test func profileOutputMatchesGoldenFiles() {
        let out = tempDir()
        let r = run(["profile", "--lexicon", lexicon, "--observations", observations, "--out", out.path])
        #expect(r.code == 0, "\(r.err)")
        let expected = fixtures.appendingPathComponent("expected")
        for name in ["summary.json", "words.tsv"] {
            let got = contents(out.appendingPathComponent(name))
            let want = contents(expected.appendingPathComponent(name))
            #expect(!want.isEmpty, "missing golden \(name)")
            #expect(got == want, "\(name) differs from golden")
        }
        #expect(r.err.contains("skipped 1 malformed"), "\(r.err)")
    }

    @Test func outputIsIndependentOfFileOrderAndRepeatable() {
        let a = tempDir(), b = tempDir()
        let file = fixtures.appendingPathComponent("observations/iphone/2026-11.jsonl").path
        _ = run(["profile", "--lexicon", lexicon, "--observations", observations, "--out", a.path])
        _ = run(["profile", "--lexicon", lexicon, "--observations", file, "--out", b.path])
        #expect(contents(a.appendingPathComponent("summary.json")) == contents(b.appendingPathComponent("summary.json")))
        #expect(contents(a.appendingPathComponent("words.tsv")) == contents(b.appendingPathComponent("words.tsv")))
    }

    @Test func lookupPrintsDefinitionPhoneticRankAndExample() {
        let r = run(["lookup", "--lexicon", lexicon, "Taxes", "be"])
        #expect(r.code == 0)
        #expect(r.out.contains("tax"))
        #expect(r.out.contains("tæks"))
        #expect(r.out.contains("rank 459"))
        #expect(r.out.contains("税"))
        #expect(r.out.contains("example:"))
        let missing = run(["lookup", "--lexicon", lexicon, "qwzx"])
        #expect(missing.code == 1)
    }

    @Test func versionPrintsLexiconVersion() {
        let r = run(["version", "--lexicon", lexicon])
        #expect(r.code == 0)
        #expect(r.out.hasPrefix("lex-"))
    }

    @Test func coverageOfAText() throws {
        let dir = tempDir()
        let text = dir.appendingPathComponent("t.txt")
        try "Be the accepted tax, London!".write(to: text, atomically: true, encoding: .utf8)
        let r = run(["coverage", "--lexicon", lexicon, "--observations", observations, "--text", text.path])
        #expect(r.code == 0, "\(r.err)")
        #expect(r.out.contains("\"tokens\": "))
        #expect(r.out.contains("\"known\": "))
    }

    @Test func usageErrorsExitNonZero() {
        #expect(run([]).code == 2)
        #expect(run(["profile", "--lexicon", lexicon]).code == 2)
        #expect(run(["lookup", "--lexicon", "/nonexistent", "x"]).code == 1)
    }
}
