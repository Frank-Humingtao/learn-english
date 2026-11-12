import Foundation
import Security

/// Where the GitHub fine-grained PAT lives. The token is kept ONLY here: never in SQLite,
/// UserDefaults, files or logs. Callers read it right before a request and do not cache it.
///
/// Onboarding (ticket 04) saves it; sync (ticket 05) reads, replaces and deletes it.
protocol TokenStore: Sendable {
    /// The stored token, or nil if none was saved.
    func token() throws -> String?
    /// Saves or replaces the token.
    func save(_ token: String) throws
    /// Removes the token (no error if there is none).
    func delete() throws
}

extension TokenStore {
    var hasToken: Bool { ((try? token()) ?? nil) != nil }
}

/// What a pasted PAT must look like before it is saved.
enum PATFormat {
    /// Trims whitespace/newlines; returns nil unless it looks like a GitHub token
    /// (`github_pat_…` fine-grained, or classic `ghp_…`).
    static func normalized(_ input: String) -> String? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("github_pat_") || t.hasPrefix("ghp_"), t.count >= 20,
              t.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        return t
    }
}

/// The device Keychain (generic password, this device only, readable after first unlock so
/// background sync can use it).
struct KeychainTokenStore: TokenStore {
    var service = "local.learnenglish.github"
    var account = "english-data-pat"

    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "Keychain 错误 \(status)" }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func token() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
