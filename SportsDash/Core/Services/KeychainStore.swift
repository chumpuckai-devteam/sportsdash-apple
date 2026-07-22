import Foundation
import Security

/// Small secret store for API keys.
/// Prefers Keychain; falls back to UserDefaults if Keychain write/read fails
/// (seen on some free Personal Team installs). Never log secret values.
enum KeychainStore {
    private static let service = "com.samirpatel.sportsdash"
    private static let defaultsPrefix = "sd_secret_"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)

        // Keychain first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)

        let keychainOK: Bool
        if status == errSecSuccess {
            keychainOK = getFromKeychain(account: account) == value
        } else {
            keychainOK = false
        }

        // Always keep a verified UserDefaults fallback so ratings work even if Keychain flakes.
        UserDefaults.standard.set(value, forKey: defaultsPrefix + account)

        // Prefer Keychain when it works; fallback is still readable via get().
        return keychainOK || (UserDefaults.standard.string(forKey: defaultsPrefix + account) == value)
    }

    static func get(account: String) -> String? {
        if let v = getFromKeychain(account: account), !v.isEmpty {
            return v
        }
        if let v = UserDefaults.standard.string(forKey: defaultsPrefix + account), !v.isEmpty {
            return v
        }
        return nil
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: defaultsPrefix + account)
    }

    static func hasValue(account: String) -> Bool {
        guard let v = get(account: account) else { return false }
        return !v.isEmpty
    }

    /// Masked preview for UI only (never full secret).
    static func maskedPreview(account: String) -> String? {
        guard let v = get(account: account), v.count >= 4 else {
            return hasValue(account: account) ? "••••" : nil
        }
        let tail = v.suffix(4)
        return "••••\(tail)"
    }

    private static func getFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
