import Foundation
import Security

enum KeychainTokenStore {
    private static let accessKey = "dev.starter.accessToken"
    private static let refreshKey = "dev.starter.refreshToken"

    static func save(accessToken: String, refreshToken: String) {
        set(key: accessKey, value: accessToken)
        set(key: refreshKey, value: refreshToken)
    }

    static func loadAccessToken() -> String? { get(key: accessKey) }
    static func loadRefreshToken() -> String? { get(key: refreshKey) }

    static func clear() {
        delete(key: accessKey)
        delete(key: refreshKey)
    }

    private static func set(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        let attrs = query.merging([kSecValueData as String: data]) { $1 }
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
