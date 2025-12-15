//
//  NetworkSettings.swift
//  ClaudeNook
//
//  Manages TCP socket configuration for remote connections
//

import Foundation
import Combine
import Security

/// TCP socket bind mode
enum TCPBindMode: String, Codable, CaseIterable {
    case disabled = "Disabled"           // TCP completely off
    case localhost = "Localhost Only"    // 127.0.0.1 only (for SSH tunnels)
    case anyInterface = "All Interfaces" // 0.0.0.0 (for direct remote connections)

    /// Description for UI
    var description: String {
        switch self {
        case .disabled:
            return "TCP connections disabled"
        case .localhost:
            return "Accept local TCP only (for SSH tunnels)"
        case .anyInterface:
            return "Accept remote connections"
        }
    }

    /// The address to bind to
    var bindAddress: String? {
        switch self {
        case .disabled:
            return nil
        case .localhost:
            return "127.0.0.1"
        case .anyInterface:
            return "0.0.0.0"
        }
    }
}

/// Configuration for TCP network settings
struct TCPConfiguration: Codable, Equatable {
    var bindMode: TCPBindMode = .disabled
    var port: UInt16 = 4851
    var authToken: String = ""

    /// Generate a cryptographically secure 64-character hex token
    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            // Fallback to UUID-based token if SecRandom fails
            return UUID().uuidString.replacingOccurrences(of: "-", with: "") +
                   UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Notification posted when TCP configuration changes
extension Notification.Name {
    static let tcpConfigurationChanged = Notification.Name("tcpConfigurationChanged")
}

@MainActor
class NetworkSettings: ObservableObject {
    static let shared = NetworkSettings()

    // MARK: - Published State

    @Published private(set) var configuration: TCPConfiguration
    @Published var isPickerExpanded: Bool = false

    // MARK: - UserDefaults Keys

    private let configKey = "tcpConfiguration"

    // MARK: - Computed Properties

    /// Whether TCP server is enabled
    var isTCPEnabled: Bool {
        configuration.bindMode != .disabled
    }

    /// Whether remote connections are allowed (not just localhost)
    var isRemoteEnabled: Bool {
        configuration.bindMode == .anyInterface
    }

    /// Whether a valid token exists
    var hasValidToken: Bool {
        !configuration.authToken.isEmpty
    }

    /// Extra height needed when picker is expanded
    var expandedPickerHeight: CGFloat {
        guard isPickerExpanded else { return 0 }
        // Base options (3 modes) + token section if enabled + port section if enabled + copy button
        var height: CGFloat = CGFloat(TCPBindMode.allCases.count) * 50
        if isTCPEnabled {
            height += 120 // Token section (field + hint text)
            height += 50  // Port section
            height += 50  // Copy setup info button
        }
        return height
    }

    // MARK: - Initialization

    private init() {
        configuration = Self.loadConfiguration()
    }

    // MARK: - Public API

    /// Update the TCP bind mode
    func updateBindMode(_ mode: TCPBindMode) {
        guard configuration.bindMode != mode else { return }
        configuration.bindMode = mode

        // Generate token if enabling TCP and no token exists
        if mode != .disabled && configuration.authToken.isEmpty {
            configuration.authToken = TCPConfiguration.generateToken()
        }

        saveConfiguration()
        notifyConfigurationChanged()
    }

    /// Update the TCP port
    func updatePort(_ port: UInt16) {
        guard configuration.port != port else { return }
        configuration.port = port
        saveConfiguration()
        notifyConfigurationChanged()
    }

    /// Generate a new auth token
    @discardableResult
    func regenerateToken() -> String {
        configuration.authToken = TCPConfiguration.generateToken()
        saveConfiguration()
        notifyConfigurationChanged()
        return configuration.authToken
    }

    /// Get the current token (for display/copy)
    var currentToken: String {
        configuration.authToken
    }

    /// Get masked token for display
    var maskedToken: String {
        let token = configuration.authToken
        guard token.count > 8 else { return token }
        return String(token.prefix(4)) + "..." + String(token.suffix(4))
    }

    /// Get connection info for remote setup
    func getConnectionInfo(host: String? = nil) -> String {
        let displayHost = host ?? "<your-mac-ip-or-hostname>"
        return """
        # Claude Nook Remote Configuration
        CLAUDE_NOOK_HOST=\(displayHost)
        CLAUDE_NOOK_PORT=\(configuration.port)
        CLAUDE_NOOK_TOKEN=\(configuration.authToken)
        CLAUDE_NOOK_MODE=tcp
        """
    }

    // MARK: - Private Methods

    private static func loadConfiguration() -> TCPConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "tcpConfiguration"),
              let config = try? JSONDecoder().decode(TCPConfiguration.self, from: data) else {
            return TCPConfiguration()
        }
        return config
    }

    private func saveConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    private func notifyConfigurationChanged() {
        NotificationCenter.default.post(
            name: .tcpConfigurationChanged,
            object: nil,
            userInfo: ["configuration": configuration]
        )
    }
}
