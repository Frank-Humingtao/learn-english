import Foundation
import SyncCore
import XCTest

final class GitHubClientTests: XCTestCase {
    let repo = RepoRef(owner: "learner", name: "english-data")

    func testReadFileThroughContentsAPI() async throws {
        let fake = FakeGitHub(files: ["plans/2026-11-12.md": "# 今日计划\n"])
        let client = GitHubClient(token: "good-token", transport: fake)

        let data = try await client.readFile(repo, path: "plans/2026-11-12.md")
        let missing = try await client.readFile(repo, path: "plans/2026-11-13.md")

        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "# 今日计划\n")
        XCTAssertNil(missing)
    }

    func testTokenInfoReportsOwnerAndExpiry() async throws {
        let fake = FakeGitHub()
        let info = try await GitHubClient(token: "good-token", transport: fake).tokenInfo()
        XCTAssertEqual(info.login, "learner")
        XCTAssertEqual(info.expiresAt, Date(timeIntervalSince1970: 1_801_353_600)) // 2027-01-31 00:00 UTC

        fake.tokenExpiration = nil
        let noExpiry = try await GitHubClient(token: "good-token", transport: fake).tokenInfo()
        XCTAssertNil(noExpiry.expiresAt)
    }

    func testBadTokenIsUnauthorized() async {
        let fake = FakeGitHub()
        do {
            _ = try await GitHubClient(token: "nope", transport: fake).tokenInfo()
            XCTFail("expected 401")
        } catch {
            XCTAssertEqual(error as? GitHubError, .unauthorized)
        }
    }

    func testStaleHeadPredicate() {
        XCTAssertTrue(GitHubErrors.isStaleHead(type: "STALE_DATA", message: ""))
        XCTAssertTrue(GitHubErrors.isStaleHead(type: nil, message: #"Expected branch to point to "abc" but it did not. Pull and try again."#))
        XCTAssertFalse(GitHubErrors.isStaleHead(type: "NOT_FOUND", message: "Could not resolve to a Repository"))
    }
}
