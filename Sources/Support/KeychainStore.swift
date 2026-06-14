import Foundation
import Security

/// Minimal generic-password Keychain wrapper used to persist the Frame.io / Adobe
/// IMS OAuth token set. Values are stored as a single JSON blob under one account
/// key so refresh/access tokens stay in sync.
struct KeychainStore {
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    let service: String

    init(service: String = "com.cjgammon.Spool.tokens") {
        self.service = service
    }

    /// Store (or replace) `data` for `account`.
    func set(_ data: Data, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Delete any existing item first so we always end up with a single entry.
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Fetch the stored data for `account`, or `nil` if nothing is stored.
    func get(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Remove any stored data for `account`.
    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Codable convenience

    func setValue<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        try set(data, account: account)
    }

    func getValue<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        guard let data = try get(account: account) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
