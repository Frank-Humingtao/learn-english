import CoreModels
import Foundation

/// One Observation waiting in the local outbox. `id` is the local row id.
public struct OutboxItem: Sendable, Equatable {
    public var id: Int64
    public var observation: Observation

    public init(id: Int64, observation: Observation) {
        self.id = id
        self.observation = observation
    }
}

/// Why the token cannot be used.
public enum TokenProblem: String, Sendable, Equatable, Codable {
    /// No token stored.
    case missing
    /// GitHub answered 401: revoked or otherwise invalid.
    case rejected
    /// GitHub answered 401 and the token's known expiry date has passed.
    case expired
    /// Token works but cannot see the repository.
    case noAccess
}

public enum PushOutcome: Sendable, Equatable {
    case nothingToPush
    /// These outbox items are now in the repository; remove them from the outbox.
    case pushed(ids: [Int64])
    case offline
    case tokenError(TokenProblem)
    /// Anything else (head kept moving, rate limit, 5xx, timeout). Items stay in the outbox.
    case failed(String)
}

/// Pushes outbox Observations to `observations/<writer>/YYYY-MM.jsonl` in one commit.
///
/// Flow: read the branch head, read the month file(s) at that head, append the lines that are
/// not already there, `createCommitOnBranch` with `expectedHeadOid`. If the head moved, do it
/// all once more from the new head; if that fails too, give up (items stay in the outbox).
/// Skipping lines already present makes a retry after a lost response idempotent.
public struct ObservationSyncer: Sendable {
    public let repo: RepoRef
    public let writer: String
    let client: GitHubClient?

    public init(token: String?, repo: RepoRef, writer: String = "iphone", transport: any HTTPTransport,
                apiBase: URL = GitHubClient.defaultAPIBase) {
        self.repo = repo
        self.writer = writer
        client = token.flatMap { $0.isEmpty ? nil : GitHubClient(token: $0, transport: transport, apiBase: apiBase) }
    }

    public func push(_ items: [OutboxItem]) async -> PushOutcome {
        guard let client else { return .tokenError(.missing) }
        guard !items.isEmpty else { return .nothingToPush }
        var attempts = 0
        while true {
            attempts += 1
            do {
                try await pushOnce(items, client: client)
                return .pushed(ids: items.map(\.id))
            } catch GitHubError.staleHead where attempts < 2 {
                continue
            } catch let error as GitHubError {
                return Self.outcome(for: error)
            } catch {
                return .failed("\(error)")
            }
        }
    }

    private func pushOnce(_ items: [OutboxItem], client: GitHubClient) async throws {
        let head = try await client.headOid(repo)
        var byPath: [String: [String]] = [:]
        var order: [String] = []
        for item in items {
            let path = JSONL.path(writer: writer, observation: item.observation)
            if byPath[path] == nil { order.append(path) }
            byPath[path, default: []].append(JSONL.line(item.observation))
        }
        var files: [(path: String, contents: Data)] = []
        for path in order {
            let existing = try await client.readFile(repo, path: path, ref: head).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let present = Set(existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
            let new = byPath[path]!.filter { !present.contains($0) }
            guard !new.isEmpty else { continue }
            var text = existing
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += new.joined(separator: "\n") + "\n"
            files.append((path, Data(text.utf8)))
        }
        guard !files.isEmpty else { return }
        let count = items.count
        _ = try await client.createCommit(repo, expectedHeadOid: head,
                                          message: "iphone: \(count) observation\(count == 1 ? "" : "s")", files: files)
    }

    public static func outcome(for error: GitHubError) -> PushOutcome {
        switch error {
        case .offline: .offline
        case .unauthorized: .tokenError(.rejected)
        case .noAccess: .tokenError(.noAccess)
        case .staleHead: .failed("分支一直在变，稍后再试")
        case .network(let m): .failed(m)
        case .server(let status, let m): .failed("HTTP \(status): \(m)")
        case .graphQL(_, let m): .failed(m)
        }
    }
}

/// On-disk JSONL format of Observations in `english-data`.
public enum JSONL {
    /// One line, no trailing newline: compact JSON, keys sorted, nil fields omitted.
    public static func line(_ observation: Observation) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! e.encode(observation), as: UTF8.self)
    }

    /// `observations/<writer>/YYYY-MM.jsonl`, month taken from the UTC timestamp.
    public static func path(writer: String, observation: Observation) -> String {
        "observations/\(writer)/\(observation.ts.prefix(7)).jsonl"
    }
}
