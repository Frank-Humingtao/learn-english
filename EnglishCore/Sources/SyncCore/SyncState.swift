import Foundation

/// What the UI shows about sync.
public enum SyncStatus: Sendable, Equatable {
    /// Everything is in the repository: show nothing.
    case synced
    /// N Observations wait in the outbox (tap to sync now).
    case pending(Int)
    /// N waiting and the last attempt found no network.
    case offline(Int)
    /// Sync cannot work until the token is fixed (persistent red bar).
    case tokenError(TokenProblem)
}

/// Sync bookkeeping that survives across attempts (persist it with the App's settings).
/// The outbox size is not stored here; pass it in when asking for the status.
public struct SyncState: Sendable, Equatable, Codable {
    public var lastSuccess: Date?
    public var lastAttempt: Date?
    public var lastError: String?
    public var offline = false
    public var tokenProblem: TokenProblem?
    public var tokenExpiresAt: Date?

    public init() {}

    public mutating func apply(_ outcome: PushOutcome, at date: Date) {
        lastAttempt = date
        switch outcome {
        case .nothingToPush, .pushed:
            lastSuccess = date
            lastError = nil
            offline = false
            tokenProblem = nil
        case .offline:
            offline = true
        case .tokenError(let problem):
            offline = false
            tokenProblem = problem
        case .failed(let message):
            offline = false
            lastError = message
        }
    }

    /// The network came back (e.g. NWPathMonitor reported `.satisfied`).
    public mutating func networkRestored() {
        offline = false
    }

    /// A new token was saved; forget the old token's problem until the next attempt says otherwise.
    public mutating func tokenReplaced(expiresAt: Date?) {
        tokenProblem = nil
        tokenExpiresAt = expiresAt
    }

    public func status(pending: Int, hasToken: Bool, now: Date = Date()) -> SyncStatus {
        if !hasToken { return .tokenError(.missing) }
        if let tokenProblem {
            if tokenProblem == .rejected, let tokenExpiresAt, tokenExpiresAt <= now { return .tokenError(.expired) }
            return .tokenError(tokenProblem)
        }
        if pending == 0 { return .synced }
        return offline ? .offline(pending) : .pending(pending)
    }
}
