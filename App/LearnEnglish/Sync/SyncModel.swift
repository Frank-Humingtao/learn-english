import Foundation
import Network
import Observation
import SyncCore
import UIKit

/// Drives sync of the local outbox to `english-data` and exposes the status the UI shows.
///
/// Triggers (no iOS background tasks): end of a test/study session (`AppModel.sessionEnded`),
/// App becoming active, network coming back, "立即同步", and a replaced token.
/// Push logic lives in `SyncCore.ObservationSyncer`; this class only wires DB, Keychain and UI.
@Observable @MainActor
final class SyncModel {
    static let defaultRepoName = "english-data"
    static let batchSize = 500

    private(set) var state: SyncState
    private(set) var pendingCount = 0
    private(set) var hasToken: Bool
    private(set) var isSyncing = false
    /// GitHub login that owns `english-data`, learned from the token.
    private(set) var repoOwner: String?

    @ObservationIgnored let database: AppDatabase
    @ObservationIgnored let tokenStore: any TokenStore
    @ObservationIgnored let transport: any HTTPTransport
    @ObservationIgnored let apiBase: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var pendingRun = false

    init(database: AppDatabase, tokenStore: any TokenStore = KeychainTokenStore(),
         transport: any HTTPTransport = URLSessionTransport(), defaults: UserDefaults = .standard) {
        self.database = database
        self.tokenStore = tokenStore
        self.transport = transport
        self.defaults = defaults
        var base = GitHubClient.defaultAPIBase
        #if DEBUG
        // Simulator verification against a local fake GitHub (see ticket 05 Comments).
        if let s = ProcessInfo.processInfo.environment["LE_GITHUB_API"], let u = URL(string: s) { base = u }
        if let t = ProcessInfo.processInfo.environment["LE_GITHUB_TOKEN"] { try? tokenStore.saveToken(t) }
        #endif
        apiBase = base
        state = defaults.data(forKey: Keys.state).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) } ?? SyncState()
        repoOwner = defaults.string(forKey: Keys.owner)
        hasToken = tokenStore.readToken() != nil
        refreshCount()
    }

    var status: SyncStatus { state.status(pending: pendingCount, hasToken: hasToken) }
    var repoDisplayName: String { "\(repoOwner ?? "…")/\(Self.defaultRepoName)" }

    /// Call after anything was written to `observation` (the outbox is filled by a DB trigger).
    func refreshCount() {
        if let n = try? database.outboxCount() { pendingCount = n }
    }

    func syncSoon() {
        Task { await syncNow() }
    }

    /// Pushes the whole outbox in batches. Concurrent calls collapse into one extra run.
    func syncNow() async {
        guard !isSyncing else { pendingRun = true; return }
        isSyncing = true
        let background = UIApplication.shared.beginBackgroundTask(withName: "sync")
        defer {
            isSyncing = false
            UIApplication.shared.endBackgroundTask(background)
            if pendingRun { pendingRun = false; syncSoon() }
        }
        hasToken = tokenStore.readToken() != nil
        refreshCount()
        guard let token = tokenStore.readToken() else {
            apply(.tokenError(.missing))
            return
        }
        if repoOwner == nil {
            do {
                let info = try await client(token).tokenInfo()
                learned(info)
            } catch let error as GitHubError {
                apply(ObservationSyncer.outcome(for: error))
                return
            } catch {
                apply(.failed("\(error)"))
                return
            }
        }
        guard let owner = repoOwner else { return }
        let syncer = ObservationSyncer(token: token, repo: RepoRef(owner: owner, name: Self.defaultRepoName),
                                       transport: transport, apiBase: apiBase)
        while true {
            guard let batch = try? database.outboxBatch(limit: Self.batchSize) else { return }
            let outcome = await syncer.push(batch)
            apply(outcome)
            guard case .pushed(let ids) = outcome else { break }
            try? database.removeFromOutbox(ids: ids)
            refreshCount()
            if batch.count < Self.batchSize { break }
        }
    }

    /// Validates a new token with GitHub, stores it in the Keychain and catches up the outbox.
    /// Throws a user-facing message when GitHub rejects it.
    func replaceToken(_ raw: String) async throws {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw TokenReplaceError(message: "令牌为空") }
        let info: TokenInfo
        do {
            info = try await client(token).tokenInfo()
        } catch GitHubError.unauthorized {
            throw TokenReplaceError(message: "GitHub 不认这个令牌（无效、过期或已撤销）")
        } catch GitHubError.offline {
            throw TokenReplaceError(message: "离线中，联网后再试")
        } catch {
            throw TokenReplaceError(message: "验证失败：\(error)")
        }
        try tokenStore.saveToken(token)
        hasToken = true
        learned(info)
        state.tokenReplaced(expiresAt: info.expiresAt)
        persist()
        await syncNow()
    }

    /// Starts watching connectivity; when the network comes back, the outbox is pushed.
    func startNetworkMonitor() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.state.offline else { return }
                self.state.networkRestored()
                self.persist()
                self.syncSoon()
            }
        }
        m.start(queue: DispatchQueue(label: "sync.network"))
        monitor = m
    }

    // MARK: private

    private func client(_ token: String) -> GitHubClient {
        GitHubClient(token: token, transport: transport, apiBase: apiBase)
    }

    private func learned(_ info: TokenInfo) {
        repoOwner = info.login
        defaults.set(info.login, forKey: Keys.owner)
        state.tokenExpiresAt = info.expiresAt
        persist()
    }

    private func apply(_ outcome: PushOutcome) {
        state.apply(outcome, at: Date())
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Keys.state) }
    }

    private enum Keys {
        static let state = "sync.state"
        static let owner = "sync.repoOwner"
    }
}

struct TokenReplaceError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
