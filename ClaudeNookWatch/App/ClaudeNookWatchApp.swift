//
//  ClaudeNookWatchApp.swift
//  ClaudeNookWatch
//
//  Apple Watch companion for Claude Nook.
//  Shows session status and handles permission approvals.
//

import SwiftUI

@main
struct ClaudeNookWatchApp: App {
    @StateObject private var sessionStore = WatchSessionStore()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isConnected = false
    @State private var isConnecting = false
    @State private var host = ""
    @State private var port = "4851"
    @State private var token = ""
    @State private var nookClient: WatchNookClient?

    private var isConfigured: Bool {
        WatchKeychainHelper.getLastHost() != nil
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                isConnected: $isConnected,
                isConfigured: .constant(isConfigured || !host.isEmpty),
                host: $host,
                port: $port,
                token: $token,
                onConnect: { connect() }
            )
            .environmentObject(sessionStore)
            .task {
                // Try to reconnect to last saved host
                if let last = WatchKeychainHelper.getLastHost() {
                    host = last.host
                    port = String(last.port)
                    token = WatchKeychainHelper.getToken(for: last.host) ?? ""
                    connect()
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active && !isConnected && !isConnecting && !host.isEmpty {
                    connect()
                }
            }
        }
    }

    private func connect() {
        guard !isConnecting, !host.isEmpty else { return }
        isConnecting = true

        let client = WatchNookClient()
        nookClient = client

        let connectHost = host
        let connectPort = Int(port) ?? 4851
        let connectToken = token.isEmpty ? nil : token

        Task {
            do {
                await client.setConnectionHandler { [self] connected in
                    Task { @MainActor in
                        isConnected = connected
                        isConnecting = false
                        if connected {
                            WatchKeychainHelper.saveLastHost(connectHost, port: connectPort)
                            if let t = connectToken {
                                try? WatchKeychainHelper.save(token: t, for: connectHost)
                            }
                        } else if !isConnecting {
                            // Schedule reconnect after delay
                            Task {
                                try? await Task.sleep(nanoseconds: 5_000_000_000)
                                if !isConnected && !isConnecting {
                                    connect()
                                }
                            }
                        }
                    }
                }

                try await client.connect(host: connectHost, port: connectPort, token: connectToken)
                await sessionStore.setClient(client)
            } catch {
                await MainActor.run {
                    isConnecting = false
                }
            }
        }
    }
}
