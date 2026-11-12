import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import ProfileEngineCLI
import StudyComposer
import Testing

/// The App (进度 tab via `ProgressPage.report`) and GitHub Actions (`profile-engine profile`) must
/// publish the same Learner Profile from the same Observations, including Leeches and 重新学.
@Suite struct AppParityTests {
    func review(_ lemma: String, _ result: String, _ ts: String) -> Observation {
        Observation(ts: ts, lemma: lemma, source: .review, result: result, session: "study-x")
    }

    @Test func appAndCommandLineGiveIdenticalProfilesWithLeechAndRelearn() throws {
        let lexicon = try Lexicon.load(directory: fixtures.appendingPathComponent("lexicon"))
        let text = contents(fixtures.appendingPathComponent("observations/iphone/2026-11.jsonl"))
        var observations = text.split(separator: "\n").compactMap {
            try? JSONDecoder().decode(Observation.self, from: Data($0.utf8))
        }
        let byRank = lexicon.entries.sorted { $0.rank > $1.rank }.map(\.lemma)
        let leech = byRank[0], relearned = byRank[1]
        for k in 0..<8 {
            observations.append(review(leech, "again", "2026-11-10T08:0\(k):00Z"))
            observations.append(review(relearned, "again", "2026-11-10T09:0\(k):00Z"))
        }
        observations.append(Observation(ts: "2026-11-11T08:00:00Z", lemma: relearned, source: .relearn, result: "reset"))
        observations.append(review(relearned, "good", "2026-11-11T08:01:00Z"))

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

        // App path, opened well after the last Observation (past the Leech cooldown on the device clock).
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: Timestamp.epochSeconds("2026-12-25T00:00:00Z")!)
        let app = ProgressPage.report(observations: observations, lexicon: lexicon, composer: StudyComposer(),
                                      now: now, calendar: utc).profile

        #expect(app.band(of: leech) == .distant, "a Leech is not an active card")
        #expect(app.band(of: relearned) == .target, "a relearned card being studied is active")
        #expect(ProfileFiles.summaryJSON(app) == contents(out.appendingPathComponent("summary.json")))
        #expect(ProfileFiles.wordsTSV(app) == contents(out.appendingPathComponent("words.tsv")))
    }
}
