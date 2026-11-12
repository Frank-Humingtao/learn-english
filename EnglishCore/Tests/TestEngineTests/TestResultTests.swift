import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import ProfileEngineCLI
import TestEngine
import Testing

@Suite struct TestResultTests {
    let lexicon = fixtureLexicon()

    /// Two sessions on the fixture lexicon: returns (history before the second test, the second session).
    func twoSessions(_ lexicon: Lexicon? = nil) -> ([Observation], TestSession) {
        let lexicon = lexicon ?? self.lexicon
        var learner = ThresholdLearner(knownUpTo: 4000, falseAlarmEvery: 7)
        var first = TestSession(lexicon: lexicon, profile: ProfileEngine.compute(observations: [], lexicon: lexicon),
                                history: [], config: .short, sessionID: "a", seed: 1)
        runSession(&first, learner: &learner, lexicon: lexicon, day: 10)
        let history = first.observations
        var second = TestSession(lexicon: lexicon, profile: ProfileEngine.compute(observations: history, lexicon: lexicon),
                                 history: history, config: .short, sessionID: "b", seed: 2)
        runSession(&second, learner: &learner, lexicon: lexicon, day: 11)
        return (history, second)
    }

    @Test func resultNumbersMatchTheProfileEngineCommandLine() throws {
        let (history, session) = twoSessions()
        let result = TestResult(history: history, session: session.observations, lexicon: lexicon)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("te-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        let lines = try (history + session.observations).map { String(decoding: try enc.encode($0), as: UTF8.self) }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: dir.appendingPathComponent("obs.jsonl"))
        var err = ""
        let code = ProfileEngineCLI.run(["profile", "--lexicon", fixtures.appendingPathComponent("lexicon").path,
                                         "--observations", dir.appendingPathComponent("obs.jsonl").path,
                                         "--out", dir.appendingPathComponent("out").path],
                                        stdout: { _ in }, stderr: { err += $0 })
        #expect(code == 0, "\(err)")
        let summary = try JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("out/summary.json"))) as! [String: Any]
        let families = (summary["vocab_size"] as! [String: Any])["families"] as! [String: Int]
        #expect(result.vocabulary == TestResult.Range(estimate: families["estimate"]!, low: families["low"]!,
                                                      high: families["high"]!))
        let obs = summary["observations"] as! [String: Int]
        let pseudoInSession = session.observations.filter { $0.pseudo == true }
        #expect(result.pseudowords.total == pseudoInSession.count)
        #expect(result.pseudowords.falseAlarms == obs["false_alarms"]! - history.filter { $0.pseudo == true && $0.result == "yes" }.count)
    }

    @Test func changeIsMeasuredAgainstTheProfileBeforeThisTest() {
        let (history, session) = twoSessions()
        let result = TestResult(history: history, session: session.observations, lexicon: lexicon)
        let before = ProfileEngine.compute(observations: history, lexicon: lexicon).vocabulary.families.estimate
        #expect(result.change == result.vocabulary.estimate - Int(before.rounded()))

        let firstEver = TestResult(history: [], session: history, lexicon: lexicon)
        #expect(firstEver.change == nil)
    }

    /// Dense synthetic lexicon: the fixture is a 1/50 sample, so its ΣP-based Target window is too small.
    @Test func spotChecksAndNewTargetWordsAreCounted() {
        let lexicon = syntheticLexicon(count: 8000)
        let (history, session) = twoSessions(lexicon)
        let result = TestResult(history: history, session: session.observations, lexicon: lexicon)
        let spot = session.observations.filter { $0.source == .spotcheck }
        #expect(result.spotcheck.correct == spot.filter { $0.result == "yes" }.count)
        #expect(result.spotcheck.wrong == spot.filter { $0.result == "no" }.count)

        let after = ProfileEngine.compute(observations: history + session.observations, lexicon: lexicon)
        // New Target words: words of this test the Learner did not show as known, now in the Target band.
        let unknown = Set(session.observations.filter {
            $0.pseudo != true && ["no", "wrong", "unknown"].contains($0.result)
        }.map(\.lemma))
        #expect(result.newTargetWords == unknown.filter { after.band(of: $0) == .target }.sorted())
        #expect(!result.newTargetWords.isEmpty)
    }
}
