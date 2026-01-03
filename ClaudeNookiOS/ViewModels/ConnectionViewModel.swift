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
                        } else if self?.connectedHost != nil {
                            // Was connected, now disconnected
                            self?.connectedHost = nil
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
            }
        }
    }

    /// Disconnect from the server
    func disconnect() {
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
}
