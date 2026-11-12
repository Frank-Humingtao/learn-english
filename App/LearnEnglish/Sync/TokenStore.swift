import Foundation
import Security

/// Where the GitHub fine-grained PAT for `english-data` lives. Only ever the Keychain:
/// never SQLite, UserDefaults, logs or files.
///
/// Ticket 05 defines this minimal store; ticket 04 (onboarding) owns first-launch paste.
/// If 04 lands its own store, keep one of the two and point the other's callers at it.
protocol TokenStore: Sendable {
    func readToken() -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

struct KeychainTokenStore: TokenStore {
    var service = "LearnEnglish.github"
    var account = "english-data-pat"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func readToken() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        let token = String(decoding: data, as: UTF8.self)
        return token.isEmpty ? nil : token
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func deleteToken() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

struct KeychainError: Error, CustomStringConvertible {
    var status: OSStatus
    var description: String { "Keychain error \(status)" }
}
