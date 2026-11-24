import Foundation
import Security

enum KeychainHelper {
    private static let service = (Bundle.main.bundleIdentifier ?? "org.ehrdemo.ios") + ".smart-session"
    private static let account = "active-session"

    struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? { "The session could not be accessed in the iOS Keychain (\(status))." }
    }

    static func save<Value: Encodable>(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        let query = itemQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func read<Value: Decodable>(_ type: Value.Type) throws -> Value? {
        var query = itemQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status == errSecSuccess ? errSecDecode : status)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    static func delete() throws {
        let status = SecItemDelete(itemQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private static func itemQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}
