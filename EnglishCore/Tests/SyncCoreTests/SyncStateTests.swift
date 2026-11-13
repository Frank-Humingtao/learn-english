import CoreModels
import Foundation
import SyncCore
import XCTest

/// The four statuses the UI shows, driven by push outcomes, outbox size and token changes.
final class SyncStateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testNothingPendingIsSyncedEvenWhenOffline() {
        var s = SyncState()
        s.apply(.offline, at: t0)
        XCTAssertEqual(s.status(pending: 0, hasToken: true), .synced)
    }

    func testPendingCount() {
        XCTAssertEqual(SyncState().status(pending: 12, hasToken: true), .pending(12))
    }

    func testOfflineWithPendingThenBackOnline() {
        var s = SyncState()
        s.apply(.offline, at: t0)
        XCTAssertEqual(s.status(pending: 3, hasToken: true), .offline(3))
        s.apply(.pushed(ids: [1, 2, 3]), at: t0)
        XCTAssertEqual(s.status(pending: 0, hasToken: true), .synced)
        XCTAssertEqual(s.lastSuccess, t0)
    }

    func testNetworkPathRestoredClearsOffline() {
        var s = SyncState()
        s.apply(.offline, at: t0)
        s.networkRestored()
        XCTAssertEqual(s.status(pending: 3, hasToken: true), .pending(3))
    }

    func testTokenErrorsShowEvenWithNothingPending() {
        XCTAssertEqual(SyncState().status(pending: 0, hasToken: false), .tokenError(.missing))
        var s = SyncState()
        s.apply(.tokenError(.rejected), at: t0)
        XCTAssertEqual(s.status(pending: 0, hasToken: true), .tokenError(.rejected))
    }

    func testExpiredTokenIsReportedAsExpired() {
        var s = SyncState()
        s.tokenExpiresAt = t0.addingTimeInterval(-60)
        s.apply(.tokenError(.rejected), at: t0)
        XCTAssertEqual(s.status(pending: 1, hasToken: true, now: t0), .tokenError(.expired))
    }

    func testFailureKeepsPendingAndRemembersReason() {
        var s = SyncState()
        s.apply(.failed("HTTP 502: bad gateway"), at: t0)
        XCTAssertEqual(s.status(pending: 4, hasToken: true), .pending(4))
        XCTAssertEqual(s.lastError, "HTTP 502: bad gateway")
    }

    /// Replacing the token clears the red bar; the next push (with the new token) catches up.
    func testReplacingTokenThenCatchingUp() async {
        let fake = FakeGitHub()
        let repo = RepoRef(owner: "learner", name: "english-data")
        let items = (1...3).map {
            OutboxItem(id: Int64($0), observation: Observation(ts: "2026-11-12T08:30:0\($0).000Z", lemma: "w\($0)",
                                                              source: .test, result: "yes"))
        }
        var s = SyncState()

        s.apply(await ObservationSyncer(token: "expired", repo: repo, transport: fake).push(items), at: t0)
        XCTAssertEqual(s.status(pending: 3, hasToken: true), .tokenError(.rejected))

        s.tokenReplaced(expiresAt: nil)
        XCTAssertEqual(s.status(pending: 3, hasToken: true), .pending(3))
        s.apply(await ObservationSyncer(token: "good-token", repo: repo, transport: fake).push(items), at: t0)
        XCTAssertEqual(s.status(pending: 0, hasToken: true), .synced)
        XCTAssertEqual(fake.files["observations/iphone/2026-11.jsonl"]?.split(separator: "\n").count, 3)
    }
}
