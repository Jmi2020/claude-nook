//
//  PairingCodeManager.swift
//  ClaudeNook
//
//  Manages temporary 6-digit pairing codes for iOS app connection.
//

import Combine
import Foundation
import os.log

private nonisolated(unsafe) let logger = Logger(subsystem: "com.jmi2020.claudenook", category: "Pairing")

/// Manages temporary pairing codes for iOS app authentication
@MainActor
class PairingCodeManager: ObservableObject {
    static let shared = PairingCodeManager()

    /// Current active pairing code (if any)
    @Published private(set) var currentCode: String?

    /// When the current code expires
    @Published private(set) var expiresAt: Date?

    /// Whether a pairing code is currently active and valid
    var isCodeActive: Bool {
        guard let code = currentCode, let expires = expiresAt else { return false }
        return !code.isEmpty && Date() < expires
    }

    /// Remaining seconds until code expires
    var remainingSeconds: Int {
        guard let expires = expiresAt else { return 0 }
        return max(0, Int(expires.timeIntervalSinceNow))
    }

    /// How long codes are valid (in seconds)
    private let codeValidityDuration: TimeInterval = 120 // 2 minutes

    /// Timer for expiration
    private var expirationTimer: Timer?

    private init() {}

    /// Generate a new 6-digit pairing code
    func generateCode() -> String {
        // Cancel any existing timer
        expirationTimer?.invalidate()

        // Generate a random 6-digit code
        let code = String(format: "%06d", Int.random(in: 0...999999))
        currentCode = code
        expiresAt = Date().addingTimeInterval(codeValidityDuration)

        // Set up expiration timer
        expirationTimer = Timer.scheduledTimer(withTimeInterval: codeValidityDuration, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.expireCode()
            }
        }

        logger.info("Generated pairing code: \(code.prefix(2), privacy: .public)****")
        return code
    }

    /// Validate a pairing code and return the auth token if valid
    /// Returns nil if the code is invalid or expired
    nonisolated func validateCode(_ code: String) -> String? {
        // Get current values on main actor
        var isValid = false
        var token: String?

        // Use synchronous main queue dispatch since this is called from socket handler
        DispatchQueue.main.sync {
            guard let currentCode = PairingCodeManager.shared.currentCode,
                  let expiresAt = PairingCodeManager.shared.expiresAt,
                  Date() < expiresAt,
                  code == currentCode else {
                return
            }

            isValid = true
            token = NetworkSettings.shared.currentToken
        }

        if isValid {
            logger.info("Pairing code validated successfully")
            // Expire the code after successful use
            DispatchQueue.main.async {
                PairingCodeManager.shared.expireCode()
            }
            return token
        } else {
            logger.warning("Invalid or expired pairing code")
            return nil
        }
    }

    /// Manually expire the current code
    func expireCode() {
        expirationTimer?.invalidate()
        expirationTimer = nil
        currentCode = nil
        expiresAt = nil
        logger.info("Pairing code expired")
    }
}
