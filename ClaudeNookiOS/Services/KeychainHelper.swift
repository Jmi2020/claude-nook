//
//  KeychainHelper.swift
//  ClaudeNookiOS
//
//  Secure storage for authentication tokens.
//

import Foundation
import Security

/// Helper for storing and retrieving tokens from Keychain
enum KeychainHelper {
    private static let service = "com.jmi2020.claudenook-ios"

    /// Save a token to the Keychain
    static func save(token: String, for host: String) throws {
        let key = "token-\(host)"
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve a token from the Keychain
    static func getToken(for host: String) -> String? {
        let key = "token-\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    /// Delete a token from the Keychain
    static func deleteToken(for host: String) {
        let key = "token-\(host)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// Save the last connected host
    static func saveLastHost(_ host: String, port: Int) {
        UserDefaults.standard.set(host, forKey: "lastHost")
        UserDefaults.standard.set(port, forKey: "lastPort")
    }

    /// Get the last connected host
    static func getLastHost() -> (host: String, port: Int)? {
        guard let host = UserDefaults.standard.string(forKey: "lastHost") else {
            return nil
        }
        let port = UserDefaults.standard.integer(forKey: "lastPort")
        return (host, port > 0 ? port : 4851)
    }
}

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode token"
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .notFound:
            return "Token not found in Keychain"
        }
    }
}
