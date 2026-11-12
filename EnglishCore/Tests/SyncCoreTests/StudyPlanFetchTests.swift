import Foundation
import SyncCore
import XCTest

/// The App pulls the newest `plan/YYYY-MM-DD.json` written by Word Planning on the Mac.
final class StudyPlanFetchTests: XCTestCase {
    let repo = RepoRef(owner: "learner", name: "english-data")

    func testFetchesTheNewestDatedPlan() async throws {
        let fake = FakeGitHub(files: [
            "plan/2026-11-10.json": "{\"old\":true}",
            "plan/2026-11-12.json": "{\"new\":true}",
            "plan/2026-11-09.json": "{\"older\":true}",
            "plan/README.md": "notes",
            "observations/iphone/2026-11.jsonl": "{}\n",
        ])
        let latest = try await GitHubClient(token: "good-token", transport: fake).latestStudyPlan(repo)
        XCTAssertEqual(latest?.path, "plan/2026-11-12.json")
        XCTAssertEqual(latest.map { String(decoding: $0.data, as: UTF8.self) }, "{\"new\":true}")
    }

    func testNoPlanDirectoryMeansNoPlan() async throws {
        let fake = FakeGitHub()
        let latest = try await GitHubClient(token: "good-token", transport: fake).latestStudyPlan(repo)
        XCTAssertNil(latest)
    }

    func testRejectedTokenThrows() async {
        let fake = FakeGitHub(files: ["plan/2026-11-12.json": "{}"])
        do {
            _ = try await GitHubClient(token: "bad", transport: fake).latestStudyPlan(repo)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? GitHubError, .unauthorized)
        }
    }
}
