import Foundation
import SyncCore

/// In-memory stand-in for the slice of GitHub that SyncCore uses: GraphQL `viewer`, branch head
/// lookup, `createCommitOnBranch`, and REST `GET /repos/{owner}/{repo}/contents/{path}` (raw).
///
/// The stale-head error mirrors the format we expect from GitHub (see `GitHubErrors.isStaleHead`);
/// it is an assumption until ticket 02 lets us measure the real response.
final class FakeGitHub: HTTPTransport, @unchecked Sendable {
    let owner = "learner"
    let repo = "english-data"
    let branch = "main"
    var validToken = "good-token"
    var tokenExpiration: String? = "2027-01-31 00:00:00 UTC"

    /// When true every request fails like a device with no network.
    var offline = false
    /// Number of upcoming commits that another writer will "win": just before each, an external
    /// commit moves the head so the client's `expectedHeadOid` is stale.
    var externalCommitsBeforeNextCommits = 0
    /// When true the next commit is applied but the response is lost (transport error).
    var dropNextCommitResponse = false

    private(set) var head: String
    private var snapshots: [String: [String: Data]] = [:]
    private var counter = 0
    private(set) var commitMessages: [String] = []
    private(set) var requests: [HTTPRequest] = []

    init(files: [String: String] = ["README.md": "# english-data\n"]) {
        head = "oid0"
        snapshots[head] = files.mapValues { Data($0.utf8) }
    }

    var files: [String: String] { (snapshots[head] ?? [:]).mapValues { String(decoding: $0, as: UTF8.self) } }
    var commitCount: Int { commitMessages.count }

    /// Simulates a commit by another writer (e.g. the Mac adding a Study Plan).
    func externalCommit(path: String = "plans/2026-11-12.md", text: String = "plan\n") {
        var next = snapshots[head]!
        next[path] = Data(text.utf8)
        advance(to: next, message: "external")
    }

    private func advance(to files: [String: Data], message: String) {
        counter += 1
        head = "oid\(counter)"
        snapshots[head] = files
        commitMessages.append(message)
    }

    // MARK: HTTPTransport

    /// Requests are handled one at a time (tests call the syncer sequentially).
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try handle(request)
    }

    private func handle(_ request: HTTPRequest) throws -> HTTPResponse {
        requests.append(request)
        if offline { throw TransportError.offline }
        guard request.headers["Authorization"] == "Bearer \(validToken)" else {
            return json(401, ["message": "Bad credentials", "documentation_url": "https://docs.github.com/rest"])
        }
        let url = request.url
        if url.path == "/graphql" { return try graphQL(request) }
        let prefix = "/repos/\(owner)/\(repo)/contents/"
        if url.path.hasPrefix(prefix) {
            let path = String(url.path.dropFirst(prefix.count))
            let ref = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ref" })?.value ?? branch
            let snapshot = snapshots[ref == branch ? head : ref]
            let children = (snapshot ?? [:]).keys.filter { $0.hasPrefix(path + "/") }
                .map { String($0.dropFirst(path.count + 1).split(separator: "/")[0]) }
            if snapshot?[path] == nil, !children.isEmpty { // directory listing
                let names = Set(children).sorted()
                return json(200, names.map { ["name": $0, "path": "\(path)/\($0)", "type": "file"] })
            }
            guard let data = snapshot?[path] else { return json(404, ["message": "Not Found"]) }
            return HTTPResponse(status: 200, headers: baseHeaders, body: data)
        }
        return json(404, ["message": "Not Found"])
    }

    private var baseHeaders: [String: String] {
        var h = ["Content-Type": "application/json"]
        if let tokenExpiration { h["github-authentication-token-expiration"] = tokenExpiration }
        return h
    }

    private func json(_ status: Int, _ object: Any) -> HTTPResponse {
        HTTPResponse(status: status, headers: baseHeaders, body: try! JSONSerialization.data(withJSONObject: object))
    }

    private func graphQL(_ request: HTTPRequest) throws -> HTTPResponse {
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data()) as! [String: Any]
        let query = body["query"] as! String
        let variables = body["variables"] as? [String: Any] ?? [:]
        if query.contains("createCommitOnBranch") {
            return try createCommit(variables["input"] as! [String: Any])
        }
        if query.contains("viewer") {
            return json(200, ["data": ["viewer": ["login": owner]]])
        }
        if query.contains("ref(") {
            guard variables["owner"] as? String == owner, variables["name"] as? String == repo else {
                return json(200, ["data": ["repository": NSNull()],
                                  "errors": [["type": "NOT_FOUND", "message": "Could not resolve to a Repository"]]])
            }
            return json(200, ["data": ["repository": ["ref": ["target": ["oid": head]]]]])
        }
        return json(400, ["message": "unsupported query"])
    }

    private func createCommit(_ input: [String: Any]) throws -> HTTPResponse {
        if externalCommitsBeforeNextCommits > 0 {
            externalCommitsBeforeNextCommits -= 1
            externalCommit(path: "plans/external-\(counter).md")
        }
        let expected = input["expectedHeadOid"] as! String
        guard expected == head else {
            return json(200, [
                "data": ["createCommitOnBranch": NSNull()],
                "errors": [[
                    "type": "STALE_DATA",
                    "path": ["createCommitOnBranch"],
                    "message": "Expected branch to point to \"\(expected)\" but it did not. Pull and try again.",
                ]],
            ])
        }
        var next = snapshots[head]!
        let changes = input["fileChanges"] as! [String: Any]
        for add in changes["additions"] as? [[String: Any]] ?? [] {
            next[add["path"] as! String] = Data(base64Encoded: add["contents"] as! String)!
        }
        let message = (input["message"] as! [String: Any])["headline"] as! String
        advance(to: next, message: message)
        if dropNextCommitResponse {
            dropNextCommitResponse = false
            throw TransportError.failed("connection reset")
        }
        return json(200, ["data": ["createCommitOnBranch": ["commit": ["oid": head]]]])
    }
}
