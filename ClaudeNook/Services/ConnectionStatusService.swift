//
//  ConnectionStatusService.swift
//  ClaudeNook
//
//  Lightweight observable for hook connection status
//

import Combine
import Foundation

enum ConnectionState: String, Equatable {
    case disconnected
    case connecting
    case connected
}

/// Whether any remote machine is actively communicating
enum RemoteReachability: String, Equatable {
    case disabled     // TCP is turned off
    case unknown      // TCP enabled but no remote has connected yet
    case reachable    // Remote sent data recently
    case unreachable  // Was reachable, but no data within health check window
}

@MainActor
class ConnectionStatusService: ObservableObject {
    static let shared = ConnectionStatusService()

    @Published private(set) var unixState: ConnectionState = .disconnected
    @Published private(set) var tcpState: ConnectionState = .disconnected
    @Published private(set) var tcpEndpoint: String? = nil
    @Published private(set) var remoteReachability: RemoteReachability = .disabled

    var isAnyConnected: Bool {
        unixState == .connected || tcpState == .connected
    }

    private var configObserver: NSObjectProtocol?
    private var socketObserver: NSObjectProtocol?
    private var reachabilityObserver: NSObjectProtocol?

    private init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .tcpConfigurationChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFromConfiguration()
            }
        }

        socketObserver = NotificationCenter.default.addObserver(
            forName: .hookSocketStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleSocketStateChange(notification)
            }
        }

        reachabilityObserver = NotificationCenter.default.addObserver(
            forName: .remoteReachabilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleReachabilityChange(notification)
            }
        }

        updateFromConfiguration()
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = socketObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = reachabilityObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateFromConfiguration() {
        let config = NetworkSettings.shared.configuration

        switch config.bindMode {
        case .disabled:
            tcpState = .disconnected
            tcpEndpoint = nil
            remoteReachability = .disabled
        case .localhost:
            tcpEndpoint = "127.0.0.1:\(config.port)"
        case .anyInterface:
            tcpEndpoint = "0.0.0.0:\(config.port)"
        }
    }

    private func handleSocketStateChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        if let unix = userInfo["unix"] as? Bool {
            unixState = unix ? .connected : .disconnected
        }

        if let tcp = userInfo["tcp"] as? Bool {
            let config = NetworkSettings.shared.configuration
            if config.bindMode == .disabled {
                tcpState = .disconnected
            } else {
                tcpState = tcp ? .connected : .disconnected
            }

            // When TCP stops, reset reachability
            if !tcp && config.bindMode != .disabled {
                remoteReachability = .unknown
            }
        }
    }

    private func handleReachabilityChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawValue = userInfo["reachability"] as? String,
              let newState = RemoteReachability(rawValue: rawValue) else { return }
        remoteReachability = newState
    }
}
