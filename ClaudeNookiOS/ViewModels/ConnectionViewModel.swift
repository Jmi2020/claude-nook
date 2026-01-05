//
//  ConnectionViewModel.swift
//  ClaudeNookiOS
//
//  Manages connection state and discovery.
//

import ClaudeNookShared
import Foundation
import os.log

private let logger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "ConnectionVM")

@MainActor
class ConnectionViewModel: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var connectedHost: String?

    @Published var showError = false
    @Published var errorMessage = ""

    private let discovery = BonjourDiscovery()
    private var nookClient: NookClient?
    private var sessionStore: iOSSessionStore?

    /// For auto-reconnect
    private var lastHost: String?
    private var lastPort: Int?
    private var lastToken: String?
    private var reconnectTask: Task<Void, Never>?

    init() {
        // Observe discovery updates
        Task {
            for await hosts in discovery.$discoveredHosts.values {
                self.discoveredHosts = hosts
            }
        }

        Task {
            for await scanning in discovery.$isScanning.values {
                self.isScanning = scanning
            }
        }
    }

    /// Set the session store to update on connection
    func setSessionStore(_ store: iOSSessionStore) {
        sessionStore = store
    }

    /// Start scanning for servers
    func startDiscovery() {
        discovery.startDiscovery()
    }

    /// Connect to a discovered host
    func connect(to host: DiscoveredHost) {
        let token = KeychainHelper.getToken(for: host.address)
        connectManually(host: host.address, port: host.port, token: token)
    }

    /// Connect manually with specified parameters
    func connectManually(host: String, port: Int, token: String?) {
        guard !isConnecting else { return }

        // Cancel any pending reconnect
        reconnectTask?.cancel()
        reconnectTask = nil

        // Save connection details for auto-reconnect
        lastHost = host
        lastPort = port
        lastToken = token

        isConnecting = true
        let client = NookClient()
        nookClient = client

        Task {
            do {
                await client.setConnectionHandler { [weak self] connected in
                    Task { @MainActor in
                        self?.isConnected = connected
                        self?.isConnecting = false

                        if connected {
                            self?.connectedHost = host
                            KeychainHelper.saveLastHost(host, port: port)
                            if let token = token {
                                try? KeychainHelper.save(token: token, for: host)
                            }
                            logger.info("Connection established to \(host)")
                        } else if self?.connectedHost != nil {
                            // Was connected, now disconnected - try to reconnect
                            logger.warning("Connection lost to \(self?.connectedHost ?? "unknown")")
                            self?.connectedHost = nil
                            self?.scheduleReconnect()
                        }
                    }
                }

                try await client.connect(host: host, port: port, token: token)

                // Set up the session store
                if let store = sessionStore {
                    await store.setClient(client)
                }

                logger.info("Connected to \(host):\(port)")

            } catch {
                logger.error("Connection failed: \(error)")
                isConnecting = false
                errorMessage = error.localizedDescription
                showError = true
                // Schedule reconnect on failure
                scheduleReconnect()
            }
        }
    }

    /// Schedule auto-reconnect after delay
    private func scheduleReconnect() {
        guard lastHost != nil, reconnectTask == nil else { return }

        reconnectTask = Task {
            logger.info("Scheduling reconnect in 5 seconds...")
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if !isConnected, !isConnecting, let host = lastHost, let port = lastPort {
                    logger.info("Attempting auto-reconnect to \(host):\(port)")
                    reconnectTask = nil
                    connectManually(host: host, port: port, token: lastToken)
                }
            }
        }
    }

    /// Disconnect from the server
    func disconnect() {
        // Cancel auto-reconnect
        reconnectTask?.cancel()
        reconnectTask = nil
        lastHost = nil
        lastPort = nil
        lastToken = nil

        Task {
            await nookClient?.disconnect()
            nookClient = nil
            isConnected = false
            connectedHost = nil
        }
    }

    /// Try to reconnect to last host
    func reconnectToLastHost() {
        guard let last = KeychainHelper.getLastHost() else { return }
        let token = KeychainHelper.getToken(for: last.host)
        connectManually(host: last.host, port: last.port, token: token)
    }

    /// Approve a permission request
    func approve(sessionId: String, toolUseId: String) {
        print("[iOS] ConnectionVM.approve: sessionId=\(sessionId.prefix(8))..., toolUseId=\(toolUseId.prefix(12))..., connected=\(isConnected)")

        guard nookClient != nil else {
            print("[iOS] ConnectionVM.approve: ERROR - nookClient is nil!")
            return
        }

        Task {
            do {
                try await nookClient?.send(.approve(sessionId: sessionId, toolUseId: toolUseId))
                print("[iOS] ConnectionVM.approve: sent successfully")
                logger.info("Approved \(toolUseId) for session \(sessionId)")
            } catch {
                print("[iOS] ConnectionVM.approve: ERROR - \(error)")
                logger.error("Failed to approve: \(error)")
            }
        }
    }

    /// Deny a permission request
    func deny(sessionId: String, toolUseId: String, reason: String?) {
        print("[iOS] ConnectionVM.deny: sessionId=\(sessionId.prefix(8))..., toolUseId=\(toolUseId.prefix(12))...")

        guard nookClient != nil else {
            print("[iOS] ConnectionVM.deny: ERROR - nookClient is nil!")
            return
        }

        Task {
            do {
                try await nookClient?.send(.deny(sessionId: sessionId, toolUseId: toolUseId, reason: reason))
                print("[iOS] ConnectionVM.deny: sent successfully")
                logger.info("Denied \(toolUseId) for session \(sessionId)")
            } catch {
                print("[iOS] ConnectionVM.deny: ERROR - \(error)")
                logger.error("Failed to deny: \(error)")
            }
        }
    }
}
