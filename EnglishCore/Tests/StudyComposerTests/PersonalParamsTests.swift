import FSRS
import Foundation
import StudyComposer
import Testing

/// `fsrs/params.json` as written by english-data-template/scripts/fsrs_train.py (py-fsrs 6.3.2)
/// from the simulated learner in test_fsrs_train.py (1227 review Observations).
let trainedParamsFile = """
{
  "format": 1,
  "algorithm": "FSRS-6",
  "w": [0.097439, 1.2931, 2.04213, 8.065019, 6.66132, 0.606162, 3.048128, 0.087518, 1.623416, 0.371071,
        0.543718, 1.44632, 0.067404, 0.233659, 1.666828, 0.360694, 1.668772, 0.5425, 0.0912, 0.0658, 0.1],
  "decay": 0.1,
  "review_count": 1227,
  "trained_at": "2026-11-13T04:00:00Z",
  "optimizer": "py-fsrs 6.3.2"
}
"""

@Suite struct PersonalParamsTests {
    /// A card rated 太简单 when new (due 8 days later), then 想起 when due: days until the next review.
    func goodIntervalDays(_ scheduler: CardScheduler) -> Double {
        let t0 = at(day: 1, hour: 8)
        let easy = scheduler.review(scheduler.newCard(at: t0), .easy, at: t0)
        let due = easy.due
        return scheduler.intervals(easy, at: due)[.good]! / 86400
    }

    @Test func aTrainedParamsFileIsReadWithItsWeightsAndDecay() throws {
        let params = try #require(PersonalFSRSParams.decode(Data(trainedParamsFile.utf8)))
        #expect(params.weights.count == 21)
        #expect(params.weights[20] == 0.1)
        #expect(params.reviewCount == 1227)
        #expect(params.trainedAt == "2026-11-13T04:00:00Z")
        let config = FSRSConfig.resolved(paramsFile: Data(trainedParamsFile.utf8))
        #expect(config.weights == params.weights)
        #expect(config.decay == 0.1)
        // Everything else stays as the App's defaults.
        #expect(config.desiredRetention == FSRSConfig.default.desiredRetention)
        #expect(config.learningSteps == FSRSConfig.default.learningSteps)
    }

    @Test func personalParamsChangeTheNextIntervalOfTheSameCard() {
        let personal = CardScheduler(config: .resolved(paramsFile: Data(trainedParamsFile.utf8)))
        let defaults = CardScheduler(config: .default)
        // Same review history, same buttons; py-fsrs 6.3.2 with the same steps gives 39 and 18 days.
        #expect(goodIntervalDays(defaults) == 39)
        #expect(goodIntervalDays(personal) == 18)
    }

    @Test func personalIntervalsMatchSwiftFSRSWithThoseWeights() throws {
        let config = FSRSConfig.resolved(paramsFile: Data(trainedParamsFile.utf8))
        let scheduler = CardScheduler(config: config)
        let fsrs = FSRS(parameters: FSRSParameters(
            requestRetention: 0.9, maximumInterval: 36500, w: config.weights, enableFuzz: false,
            enableShortTerm: true, learningSteps: ["1m", "10m"], relearningSteps: ["10m"]))
        let t0 = at(day: 1, hour: 8)
        let easy = try fsrs.next(card: FSRSDefaults().createEmptyCard(now: t0), now: t0, grade: .easy).card
        let expected = try fsrs.repeat(card: easy, now: easy.due)
        let mine = scheduler.review(scheduler.newCard(at: t0), .easy, at: t0)
        let got = scheduler.intervals(mine, at: mine.due)
        for grade in Grade.allCases {
            let rating = Rating(rawValue: grade.rawValue)!
            #expect(got[grade] == expected[rating]!.card.due.timeIntervalSince(easy.due))
        }
    }

    @Test(arguments: [
        nil,
        "",
        "not json",
        #"{"w": [1, 2, 3], "review_count": 10}"#,                                   // FSRS-5 or truncated
        #"{"w": "x", "review_count": 10}"#,
        #"{"review_count": 10}"#,
        #"{"format": 2, "w": [0.2,1.3,2.3,8.3,6.4,0.8,3,0.001,1.9,0.17,0.8,1.5,0.06,0.26,1.6,0.6,1.9,0.5,0.09,0.07,0.15]}"#,
        #"{"w": [-1,1.3,2.3,8.3,6.4,0.8,3,0.001,1.9,0.17,0.8,1.5,0.06,0.26,1.6,0.6,1.9,0.5,0.09,0.07,0.15]}"#,
    ] as [String?])
    func absentOrInvalidFilesFallBackToDefaults(_ file: String?) {
        #expect(FSRSConfig.resolved(paramsFile: file.map { Data($0.utf8) }) == .default)
    }
}
