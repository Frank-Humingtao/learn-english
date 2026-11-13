import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import Testing

let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

/// The committed fixture Observations (one malformed line is skipped, as the CLI does).
func fixtureObservations() -> [Observation] {
    let text = String(decoding: FileManager.default.contents(
        atPath: fixtures.appendingPathComponent("observations/iphone/2026-11.jsonl").path) ?? Data(), as: UTF8.self)
    return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Observation.self, from: Data($0.utf8)) }
}

func fixtureLexicon() -> Lexicon {
    try! Lexicon.load(directory: fixtures.appendingPathComponent("lexicon"))
}

/// UTC calendar so "today" is the same on every machine.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-11-<day> <hour>:<minute> UTC.
func at(day: Int, hour: Int = 9, minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

func iso(_ d: Date) -> String { Timestamp.iso(d.timeIntervalSince1970) }

func testAnswer(_ lemma: String, _ yes: Bool, _ date: Date, session: String) -> Observation {
    Observation(ts: iso(date), lemma: lemma, source: .test, result: yes ? "yes" : "no", session: session)
}

@Suite struct ProgressTests {
    /// `Fixtures/expected/summary.json` is what `profile-engine profile` prints for the fixture (CLITests).
    @Test func progressNumbersMatchTheProfileEngineCommandLine() {
        let report = ProgressPage.report(observations: fixtureObservations(), lexicon: fixtureLexicon(),
                                         now: at(day: 12), calendar: utc)
        let golden = String(decoding: FileManager.default.contents(
            atPath: fixtures.appendingPathComponent("expected/summary.json").path) ?? Data(), as: UTF8.self)
        #expect(ProfileFiles.summaryJSON(report.profile) == golden)
    }

    /// One curve point per test session, at that session's end, from the Observations up to then.
    @Test func curveFollowsEachTestSession() {
        let lexicon = fixtureLexicon()
        let words = lexicon.entries.sorted { $0.rank < $1.rank }.map(\.lemma)
        var obs: [Observation] = []
        // Three tests: the learner says yes to more of the list each time.
        for (k, known) in [10, 60, 150].enumerated() {
            for (i, w) in words.prefix(200).enumerated() {
                obs.append(testAnswer(w, i < known, at(day: 1 + k * 3, hour: 9, minute: i / 10), session: "t\(k)"))
            }
        }
        let curve = ProgressPage.curve(observations: obs, lexicon: lexicon)
        #expect(curve.map(\.session) == ["t0", "t1", "t2"])
        #expect(curve.map(\.ts) == [iso(at(day: 1, minute: 19)), iso(at(day: 4, minute: 19)), iso(at(day: 7, minute: 19))])
        let sizes = curve.map(\.families.estimate)
        #expect(sizes[0] < sizes[1] && sizes[1] < sizes[2], "\(sizes)")

        // A point equals the profile computed from the Observations up to that session's end.
        let upToFirst = obs.filter { $0.ts <= curve[0].ts }
        #expect(curve[0].families == ProfileEngine.compute(observations: upToFirst, lexicon: lexicon).vocabulary.families)

        // Cached points are reused as is; only new sessions are computed.
        var cached = curve
        cached[0].families.estimate = -1
        let again = ProgressPage.curve(observations: obs, lexicon: lexicon, reusing: Array(cached.prefix(2)))
        #expect(again.map(\.families.estimate) == [-1, sizes[1], sizes[2]])
    }

    @Test func fixtureCurveHasOnePointPerTest() {
        let curve = ProgressPage.curve(observations: fixtureObservations(), lexicon: fixtureLexicon())
        #expect(curve.map(\.session) == ["baseline-1", "short-3", "short-5"])
    }

    /// Same rule as the public dashboard (连续天数): consecutive days with a test answer,
    /// ending today or yesterday. Retired card-study sources do not count.
    @Test func streakCountsConsecutiveTestDays() {
        let obs = [3, 5, 6, 7].map { testAnswer("a", true, at(day: $0), session: "d\($0)") }
            + [Observation(ts: iso(at(day: 8)), lemma: "a", source: ObservationSource(rawValue: "review"), result: "good")]
        let today = ProgressPage.activity(observations: obs, now: at(day: 8, hour: 20), calendar: utc)
        #expect(today.lastTestDay == "2026-11-07")
        #expect(today.streakDays == 3, "test days 5, 6, 7; the review on day 8 is not a test")
        #expect(ProgressPage.activity(observations: obs, now: at(day: 9), calendar: utc).streakDays == 0)
        let none = ProgressPage.activity(observations: [], now: at(day: 9), calendar: utc)
        #expect(none.lastTestDay == nil && none.streakDays == 0)
    }
}
