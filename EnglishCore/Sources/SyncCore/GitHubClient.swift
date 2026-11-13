import Foundation

/// A GitHub repository branch.
public struct RepoRef: Sendable, Equatable, Codable {
    public var owner: String
    public var name: String
    public var branch: String

    public init(owner: String, name: String, branch: String = "main") {
        self.owner = owner
        self.name = name
        self.branch = branch
    }

    public var nameWithOwner: String { "\(owner)/\(name)" }
}

public enum GitHubError: Error, Equatable, Sendable {
    /// No network.
    case offline
    /// Request sent but no response (timeout, reset). The server may have acted on it.
    case network(String)
    /// HTTP 401: token missing, expired or revoked.
    case unauthorized
    /// The token works but cannot see the repository / branch (wrong repo scope).
    case noAccess(String)
    /// `createCommitOnBranch` refused because the branch moved past `expectedHeadOid`.
    case staleHead
    /// Rate limits, 5xx and other HTTP failures.
    case server(status: Int, message: String)
    /// A GraphQL error that is none of the above.
    case graphQL(type: String?, message: String)
}

/// Who the token belongs to and when it expires (fine-grained PATs report this in the
/// `GitHub-Authentication-Token-Expiration` response header; absent = no expiry).
public struct TokenInfo: Sendable, Equatable {
    public var login: String
    public var expiresAt: Date?
}

/// Minimal GitHub API client: GraphQL for commits, REST Contents for reading files.
/// Every call goes through the injected `HTTPTransport`.
public struct GitHubClient: Sendable {
    public let token: String
    let transport: any HTTPTransport
    let apiBase: URL

    public static let defaultAPIBase = URL(string: "https://api.github.com")!

    public init(token: String, transport: any HTTPTransport, apiBase: URL = defaultAPIBase) {
        self.token = token
        self.transport = transport
        self.apiBase = apiBase
    }

    // MARK: REST

    /// Reads one file through the REST Contents API (raw media type, works up to 100 MB).
    /// `ref` is a branch, tag or commit oid; nil = the repository's default branch.
    /// Returns nil when the file does not exist.
    public func readFile(_ repo: RepoRef, path: String, ref: String? = nil) async throws -> Data? {
        let url = contentsURL(repo, path: path, ref: ref)
        let response = try await send(HTTPRequest(method: "GET", url: url, headers: headers(accept: "application/vnd.github.raw+json")))
        switch response.status {
        case 200: return response.body
        case 404: return nil
        default: throw Self.httpError(response)
        }
    }

    /// Names of the entries of a directory (REST Contents, up to 1,000 entries); nil when it does not exist.
    public func listDirectory(_ repo: RepoRef, path: String, ref: String? = nil) async throws -> [String]? {
        let url = contentsURL(repo, path: path, ref: ref)
        let response = try await send(HTTPRequest(method: "GET", url: url, headers: headers(accept: "application/vnd.github+json")))
        switch response.status {
        case 200:
            guard let entries = (try? JSONSerialization.jsonObject(with: response.body)) as? [[String: Any]] else {
                return nil // a file, not a directory
            }
            return entries.compactMap { $0["name"] as? String }
        case 404: return nil
        default: throw Self.httpError(response)
        }
    }

    private func contentsURL(_ repo: RepoRef, path: String, ref: String?) -> URL {
        var c = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        let encodedPath = path.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? String($0)
        }.joined(separator: "/")
        c.percentEncodedPath = "/repos/\(repo.owner)/\(repo.name)/contents/\(encodedPath)"
        if let ref { c.queryItems = [URLQueryItem(name: "ref", value: ref)] }
        return c.url!
    }

    // MARK: GraphQL

    /// The token's owner and expiry. Fails with `.unauthorized` for a bad token.
    public func tokenInfo() async throws -> TokenInfo {
        let (data, response) = try await graphQL("query { viewer { login } }", variables: [:])
        guard let login = ((data["viewer"] as? [String: Any])?["login"]) as? String else {
            throw GitHubError.graphQL(type: nil, message: "viewer missing")
        }
        return TokenInfo(login: login, expiresAt: response.header("github-authentication-token-expiration").flatMap(Self.parseExpiration))
    }

    /// Current commit oid of `repo.branch`.
    public func headOid(_ repo: RepoRef) async throws -> String {
        let query = """
        query($owner: String!, $name: String!, $qualifiedName: String!) {
          repository(owner: $owner, name: $name) { ref(qualifiedName: $qualifiedName) { target { oid } } }
        }
        """
        let (data, _) = try await graphQL(query, variables: [
            "owner": repo.owner, "name": repo.name, "qualifiedName": "refs/heads/\(repo.branch)",
        ])
        guard let repository = data["repository"] as? [String: Any] else {
            throw GitHubError.noAccess("repository \(repo.nameWithOwner) not visible to this token")
        }
        guard let oid = (((repository["ref"] as? [String: Any])?["target"]) as? [String: Any])?["oid"] as? String else {
            throw GitHubError.noAccess("branch \(repo.branch) not found in \(repo.nameWithOwner)")
        }
        return oid
    }

    /// One commit adding/replacing `files` (path -> full new contents) on `repo.branch`,
    /// only if the branch still points at `expectedHeadOid`. Returns the new commit oid.
    public func createCommit(_ repo: RepoRef, expectedHeadOid: String, message: String,
                             files: [(path: String, contents: Data)]) async throws -> String {
        let query = """
        mutation($input: CreateCommitOnBranchInput!) {
          createCommitOnBranch(input: $input) { commit { oid } }
        }
        """
        let input: [String: Any] = [
            "branch": ["repositoryNameWithOwner": repo.nameWithOwner, "branchName": repo.branch],
            "expectedHeadOid": expectedHeadOid,
            "message": ["headline": message],
            "fileChanges": ["additions": files.map { ["path": $0.path, "contents": $0.contents.base64EncodedString()] }],
        ]
        let (data, _) = try await graphQL(query, variables: ["input": input])
        guard let oid = (((data["createCommitOnBranch"] as? [String: Any])?["commit"]) as? [String: Any])?["oid"] as? String else {
            throw GitHubError.graphQL(type: nil, message: "createCommitOnBranch returned no commit")
        }
        return oid
    }

    // MARK: plumbing

    private func headers(accept: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Accept": accept,
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "LearnEnglish-iOS",
        ]
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch TransportError.offline {
            throw GitHubError.offline
        } catch let TransportError.failed(message) {
            throw GitHubError.network(message)
        }
        if response.status == 401 { throw GitHubError.unauthorized }
        return response
    }

    private func graphQL(_ query: String, variables: [String: Any]) async throws -> ([String: Any], HTTPResponse) {
        var h = headers(accept: "application/vnd.github+json")
        h["Content-Type"] = "application/json"
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let response = try await send(HTTPRequest(method: "POST", url: apiBase.appendingPathComponent("graphql"), headers: h, body: body))
        guard response.status == 200 else { throw Self.httpError(response) }
        let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] ?? [:]
        if let errors = object["errors"] as? [[String: Any]], let first = errors.first {
            let type = first["type"] as? String
            let message = first["message"] as? String ?? ""
            if GitHubErrors.isStaleHead(type: type, message: message) { throw GitHubError.staleHead }
            if type == "NOT_FOUND" || type == "FORBIDDEN" { throw GitHubError.noAccess(message) }
            throw GitHubError.graphQL(type: type, message: message)
        }
        return (object["data"] as? [String: Any] ?? [:], response)
    }

    static func httpError(_ response: HTTPResponse) -> GitHubError {
        let message = ((try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any])?["message"] as? String
            ?? String(decoding: response.body.prefix(200), as: UTF8.self)
        if response.status == 404 { return .noAccess(message) }
        return .server(status: response.status, message: message)
    }

    /// `2026-12-01 00:00:00 UTC` or `2026-12-01 00:00:00 -0800`.
    static func parseExpiration(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss zzz", "yyyy-MM-dd HH:mm:ss Z"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
