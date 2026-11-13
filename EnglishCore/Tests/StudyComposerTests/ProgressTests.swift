import CoreModels
import Foundation
import Lexicon
import ProfileEngine
import StudyComposer
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

func testAnswer(_ lemma: String, _ yes: Bool, _ date: Date, session: String) -> Observation {
    Observation(ts: iso(date), lemma: lemma, source: .test, result: yes ? "yes" : "no", session: session)
}

@Suite struct ProgressTests {
    /// `Fixtures/expected/summary.json` is what `profile-engine profile` prints for the fixture (CLITests).
    @Test func progressNumbersMatchTheProfileEngineCommandLine() {
        let observations = fixtureObservations()
        let report = ProgressPage.report(observations: observations, lexicon: fixtureLexicon(),
                                     composer: StudyComposer(), now: at(day: 12), calendar: utc)
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
            obs.append(review(words[0], .good, at(day: 2 + k * 3)))
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

    /// Same rule as the public dashboard (连续学习天数): consecutive days with a test or a review,
    /// ending today or yesterday.
    @Test func streakCountsConsecutiveStudyDays() {
        let obs = [3, 5, 6].map { testAnswer("a", true, at(day: $0), session: "d\($0)") }
            + [review("a", .good, at(day: 7)), review("a", .good, at(day: 8)),
               StudyObservations.wish("b", at: at(day: 9)), StudyObservations.dailyNewLimit(5, at: at(day: 10))]
        let today = ProgressPage.activity(observations: obs, now: at(day: 8, hour: 20), calendar: utc)
        #expect(today.lastTestDay == "2026-11-06")
        #expect(today.streakDays == 4, "test days 5, 6 and review days 7, 8")
        #expect(ProgressPage.activity(observations: obs, now: at(day: 9, hour: 23), calendar: utc).streakDays == 4)
        #expect(ProgressPage.activity(observations: obs, now: at(day: 10), calendar: utc).streakDays == 0,
                "wishes and settings are not study")
        let none = ProgressPage.activity(observations: [], now: at(day: 9), calendar: utc)
        #expect(none.lastTestDay == nil && none.streakDays == 0)
    }

    /// A relearned Leech is a new card again: it no longer counts as an active card (Target) until studied.
    @Test func profileUsesTheCardLedgersActiveCards() {
        let lexicon = fixtureLexicon()
        let far = lexicon.entries.max { $0.rank < $1.rank }!.lemma
        var obs = (0..<8).map { review(far, .again, at(day: 1, hour: 8 + $0)) }
        let leeched = ProgressPage.report(observations: obs, lexicon: lexicon, composer: StudyComposer(),
                                      now: at(day: 2), calendar: utc)
        #expect(leeched.leeches.map(\.lemma) == [far])
        #expect(leeched.profile.band(of: far) == .distant)

        obs.append(relearn(far, at(day: 2)))
        obs.append(review(far, .good, at(day: 2, hour: 10)))
        let relearned = ProgressPage.report(observations: obs, lexicon: lexicon, composer: StudyComposer(),
                                        now: at(day: 2, hour: 11), calendar: utc)
        #expect(relearned.leeches.isEmpty)
        #expect(relearned.profile.band(of: far) == .target)
    }
}
