import CoreModels
import Foundation
import SyncCore
import XCTest

final class ObservationSyncTests: XCTestCase {
    let repo = RepoRef(owner: "learner", name: "english-data", branch: "main")

    func obs(_ lemma: String, _ ts: String = "2026-11-12T08:30:00.000Z", result: String = "yes") -> Observation {
        Observation(ts: ts, lemma: lemma, source: .test, result: result, rtMs: 812, session: "s1")
    }

    func syncer(_ fake: FakeGitHub, token: String? = "good-token") -> ObservationSyncer {
        ObservationSyncer(token: token, repo: repo, writer: "iphone", transport: fake)
    }

    func testBatchOfObservationsBecomesOneCommitAppendingJSONLLines() async {
        let fake = FakeGitHub()
        let items = [OutboxItem(id: 1, observation: obs("apple")), OutboxItem(id: 2, observation: obs("pear", result: "no"))]

        let outcome = await syncer(fake).push(items)

        XCTAssertEqual(outcome, .pushed(ids: [1, 2]))
        XCTAssertEqual(fake.commitCount, 1)
        XCTAssertEqual(fake.files["observations/iphone/2026-11.jsonl"], """
        {"lemma":"apple","result":"yes","rt_ms":812,"session":"s1","source":"test","ts":"2026-11-12T08:30:00.000Z"}
        {"lemma":"pear","result":"no","rt_ms":812,"session":"s1","source":"test","ts":"2026-11-12T08:30:00.000Z"}

        """)
        XCTAssertEqual(fake.files["README.md"], "# english-data\n", "other files untouched")
    }

    func testAppendsToExistingMonthFileAndSplitsByMonth() async {
        let existing = #"{"lemma":"old","result":"yes","source":"test","ts":"2026-10-30T23:59:59Z"}"# + "\n"
        let fake = FakeGitHub(files: ["observations/iphone/2026-10.jsonl": existing])
        let items = [
            OutboxItem(id: 7, observation: obs("late", "2026-10-31T23:00:00.000Z")),
            OutboxItem(id: 8, observation: obs("early", "2026-11-01T00:10:00.000Z")),
        ]

        let outcome = await syncer(fake).push(items)

        XCTAssertEqual(outcome, .pushed(ids: [7, 8]))
        XCTAssertEqual(fake.commitCount, 1, "both months in one commit")
        let october = fake.files["observations/iphone/2026-10.jsonl"]!.split(separator: "\n")
        XCTAssertEqual(october.count, 2)
        XCTAssertEqual(String(october[0]), existing.trimmingCharacters(in: .newlines), "existing lines kept as-is")
        XCTAssertTrue(october[1].contains(#""lemma":"late""#))
        XCTAssertTrue(fake.files["observations/iphone/2026-11.jsonl"]!.contains(#""lemma":"early""#))
    }

    func testHeadMovedByAnotherWriterIsReReadAndRetriedOnce() async {
        let fake = FakeGitHub()
        fake.externalCommitsBeforeNextCommits = 1

        let outcome = await syncer(fake).push([OutboxItem(id: 1, observation: obs("apple"))])

        XCTAssertEqual(outcome, .pushed(ids: [1]))
        XCTAssertEqual(fake.commitCount, 2, "the external commit and ours")
        XCTAssertNotNil(fake.files["plans/external-0.md"], "the other writer's file survives")
        XCTAssertNotNil(fake.files["observations/iphone/2026-11.jsonl"])
    }

    func testHeadMovingAgainOnRetryLeavesItemsInOutbox() async {
        let fake = FakeGitHub()
        fake.externalCommitsBeforeNextCommits = 2

        let outcome = await syncer(fake).push([OutboxItem(id: 1, observation: obs("apple"))])

        guard case .failed = outcome else { return XCTFail("expected failure, got \(outcome)") }
        XCTAssertNil(fake.files["observations/iphone/2026-11.jsonl"])
        let mutations = fake.requests.filter { String(decoding: $0.body ?? Data(), as: UTF8.self).contains("createCommitOnBranch") }
        XCTAssertEqual(mutations.count, 2, "one try plus exactly one retry")
    }

    func testRejectedTokenIsATokenError() async {
        let fake = FakeGitHub()
        fake.validToken = "new-token"

        let outcome = await syncer(fake, token: "revoked-token").push([OutboxItem(id: 1, observation: obs("apple"))])

        XCTAssertEqual(outcome, .tokenError(.rejected))
        XCTAssertEqual(fake.commitCount, 0)
    }

    func testMissingTokenIsATokenErrorWithoutNetwork() async {
        let fake = FakeGitHub()

        let outcome = await syncer(fake, token: nil).push([OutboxItem(id: 1, observation: obs("apple"))])

        XCTAssertEqual(outcome, .tokenError(.missing))
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testTokenWithoutAccessToTheRepository() async {
        let fake = FakeGitHub()
        let other = ObservationSyncer(token: "good-token", repo: RepoRef(owner: "learner", name: "elsewhere"),
                                      transport: fake)

        let outcome = await other.push([OutboxItem(id: 1, observation: obs("apple"))])

        XCTAssertEqual(outcome, .tokenError(.noAccess))
    }

    func testOffline() async {
        let fake = FakeGitHub()
        fake.offline = true

        let outcome = await syncer(fake).push([OutboxItem(id: 1, observation: obs("apple"))])

        XCTAssertEqual(outcome, .offline)
    }

    func testRetryAfterLostResponseDoesNotDuplicateLines() async {
        let fake = FakeGitHub()
        fake.dropNextCommitResponse = true
        let items = [OutboxItem(id: 1, observation: obs("apple")), OutboxItem(id: 2, observation: obs("pear"))]

        let first = await syncer(fake).push(items)
        let second = await syncer(fake).push(items + [OutboxItem(id: 3, observation: obs("plum"))])

        guard case .failed = first else { return XCTFail("expected failure, got \(first)") }
        XCTAssertEqual(second, .pushed(ids: [1, 2, 3]))
        let lines = fake.files["observations/iphone/2026-11.jsonl"]!.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
    }

    func testAllLinesAlreadyPresentMakesNoCommit() async {
        let fake = FakeGitHub()
        let items = [OutboxItem(id: 1, observation: obs("apple"))]
        _ = await syncer(fake).push(items)

        let again = await syncer(fake).push(items)

        XCTAssertEqual(again, .pushed(ids: [1]))
        XCTAssertEqual(fake.commitCount, 1)
    }

    func testEmptyOutboxDoesNothing() async {
        let fake = FakeGitHub()
        let outcome = await syncer(fake).push([])
        XCTAssertEqual(outcome, .nothingToPush)
        XCTAssertTrue(fake.requests.isEmpty)
    }
}
