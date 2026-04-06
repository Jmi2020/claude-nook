//
//  WatchKeychainHelper.swift
//  ClaudeNookWatch
//
//  Keychain storage for Watch connection credentials.
//

import Foundation
import Security

struct WatchKeychainHelper {
    private static let service = "com.jmi2020.claudenook-watch"
    private static let lastHostKey = "lastHost"

    static func save(token: String, for host: String) throws {
        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func getToken(for host: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveLastHost(_ host: String, port: Int) {
        UserDefaults.standard.set("\(host):\(port)", forKey: lastHostKey)
    }

    static func getLastHost() -> (host: String, port: Int)? {
        guard let saved = UserDefaults.standard.string(forKey: lastHostKey) else { return nil }
        let parts = saved.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]) else { return nil }
        return (String(parts[0]), port)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
