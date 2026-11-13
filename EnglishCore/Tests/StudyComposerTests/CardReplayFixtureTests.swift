import CoreModels
import Foundation
import Testing

/// `Fixtures/card-replay/` is shared with the Python scripts (`english-data-template/scripts/obs_io.py`,
/// test_obs_io.py): both replays must produce exactly `expected.json` (hand-derived from the rules).
@Suite struct CardReplayFixtureTests {
    struct Expected: Decodable {
        struct Card: Decodable {
            var lemma: String
            var active: Bool
            var paused: String?
            var lapses: Int
            var firstEase: Int?
            var leechSince: String?
            var resetAt: String?
            var reintroduced: Bool
        }
        var asOf: String
        var leechLapses: Int
        var leechCooldownDays: Double
        var cards: [Card]
    }

    @Test func replayMatchesTheSharedFixture() throws {
        let dir = fixtures.appendingPathComponent("card-replay")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let expected = try decoder.decode(Expected.self,
                                          from: FileManager.default.contents(atPath: dir.appendingPathComponent("expected.json").path)!)
        let text = String(decoding: FileManager.default.contents(
            atPath: dir.appendingPathComponent("observations.jsonl").path)!, as: UTF8.self)
        let observations = text.split(separator: "\n").compactMap {
            try? JSONDecoder().decode(Observation.self, from: Data($0.utf8))
        }
        var rule = LeechRule()
        rule.lapses = expected.leechLapses
        rule.cooldownDays = expected.leechCooldownDays
        let replay = CardReplay(observations: observations, rule: rule,
                                asOf: Timestamp.epochSeconds(expected.asOf)!)

        #expect(replay.cards.keys.sorted() == expected.cards.map(\.lemma))
        for want in expected.cards {
            guard let got = replay.cards[want.lemma] else { continue }
            #expect(got.isActive == want.active, "\(want.lemma)")
            #expect(got.paused?.rawValue == want.paused, "\(want.lemma)")
            #expect(got.lapses == want.lapses, "\(want.lemma)")
            #expect(got.firstEase == want.firstEase, "\(want.lemma)")
            #expect(got.leechSince == want.leechSince.flatMap(Timestamp.epochSeconds), "\(want.lemma)")
            #expect(got.resetAt == want.resetAt.flatMap(Timestamp.epochSeconds), "\(want.lemma)")
            #expect(got.reintroduced == want.reintroduced, "\(want.lemma)")
        }
        #expect(replay.activeLemmas == Set(expected.cards.filter(\.active).map(\.lemma)))
    }
}
