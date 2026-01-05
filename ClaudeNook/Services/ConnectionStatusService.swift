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

@MainActor
class ConnectionStatusService: ObservableObject {
    static let shared = ConnectionStatusService()

    @Published private(set) var unixState: ConnectionState = .disconnected
    @Published private(set) var tcpState: ConnectionState = .disconnected
    @Published private(set) var tcpEndpoint: String? = nil

    var isAnyConnected: Bool {
        unixState == .connected || tcpState == .connected
    }

    private var configObserver: NSObjectProtocol?
    private var socketObserver: NSObjectProtocol?

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

        updateFromConfiguration()
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = socketObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateFromConfiguration() {
        let config = NetworkSettings.shared.configuration

        switch config.bindMode {
        case .disabled:
            tcpState = .disconnected
            tcpEndpoint = nil
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
        }
    }
}
