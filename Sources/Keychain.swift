import Foundation
import Security

/// Small wrapper for storing secrets (the session token and the master key) in the iPad's Keychain.
enum Keychain {
    private static let service = "au.com.neurofaith.inkwell"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    static func set(_ data: Data, for key: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = data
        // Available after the first unlock, and never copied to another device or backup.
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
