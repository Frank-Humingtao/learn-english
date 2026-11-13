import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import ProfileEngineCLI
import Testing

/// The App (进度 tab via `ProgressPage.report`) and GitHub Actions (`profile-engine profile`) must
/// publish the same Learner Profile from the same Observations.
@Suite struct AppParityTests {
    @Test func appAndCommandLineGiveIdenticalProfiles() throws {
        let lexicon = try Lexicon.load(directory: fixtures.appendingPathComponent("lexicon"))
        let text = contents(fixtures.appendingPathComponent("observations/iphone/2026-11.jsonl"))
        let observations = text.split(separator: "\n").compactMap {
            try? JSONDecoder().decode(Observation.self, from: Data($0.utf8))
        }

        // CLI path: the Observations as the App syncs them (JSONL).
        let dir = tempDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonl = try observations.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("obs/iphone"), withIntermediateDirectories: true)
        try (jsonl + "\n").write(to: dir.appendingPathComponent("obs/iphone/2026-11.jsonl"), atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("out")
        let r = run(["profile", "--lexicon", fixtures.appendingPathComponent("lexicon").path,
                     "--observations", dir.appendingPathComponent("obs").path, "--out", out.path])
        #expect(r.code == 0, "\(r.err)")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: Timestamp.epochSeconds("2026-12-25T00:00:00Z")!)
        let app = ProgressPage.report(observations: observations, lexicon: lexicon, now: now, calendar: utc).profile

        #expect(ProfileFiles.summaryJSON(app) == contents(out.appendingPathComponent("summary.json")))
        #expect(ProfileFiles.wordsTSV(app) == contents(out.appendingPathComponent("words.tsv")))
    }
}
