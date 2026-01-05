//
//  NookClient.swift
//  ClaudeNookiOS
//
//  TCP client for connecting to Claude Nook Mac server.
//

import ClaudeNookShared
import Foundation
import Network
import os.log

/// TCP client for connecting to the Claude Nook server
actor NookClient {
    private var connection: NWConnection?
    private var messageHandler: (@Sendable (ServerMessage) -> Void)?
    private var connectionHandler: (@Sendable (Bool) -> Void)?
    private var buffer = Data()

    private let queue = DispatchQueue(label: "com.jmi2020.claudenook-ios.client")
    private let logger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "NookClient")

    var isConnected: Bool {
        connection?.state == .ready
    }

    /// Connect to the server
    func connect(host: String, port: Int, token: String?) async throws {
        logger.info("Connecting to \(host):\(port), token=\(token?.prefix(8) ?? "nil")")

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection

        return try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                Task { [weak self] in
                    await self?.handleConnectionState(state, token: token, continuation: continuation)
                }
            }

            connection.start(queue: queue)
        }
    }

    private func handleConnectionState(
        _ state: NWConnection.State,
        token: String?,
        continuation: CheckedContinuation<Void, Error>?
    ) async {
        switch state {
        case .ready:
            logger.info("Connection ready, sending AUTH and SUBSCRIBE")

            // Authenticate
            if let token = token {
                let authMessage = "AUTH \(token)\n"
                logger.info("Sending AUTH (len=\(authMessage.count))")
                connection?.send(content: authMessage.data(using: .utf8)!, completion: .contentProcessed { [self] error in
                    if let error = error {
                        logger.error("Failed to send AUTH: \(error)")
                    } else {
                        logger.info("AUTH sent successfully")
                    }
                })
            } else {
                logger.warning("No token provided, skipping AUTH")
            }

            // Send SUBSCRIBE to enter persistent mode
            let subscribeMessage = "SUBSCRIBE\n"
            logger.info("Sending SUBSCRIBE")
            connection?.send(content: subscribeMessage.data(using: .utf8)!, completion: .contentProcessed { [self] error in
                if let error = error {
                    logger.error("Failed to send SUBSCRIBE: \(error)")
                } else {
                    logger.info("SUBSCRIBE sent successfully")
                }
            })

            // Start receiving messages
            startReceiving()

            continuation?.resume()

            // Call connection handler
            if let handler = connectionHandler {
                handler(true)
            }

        case .failed(let error):
            logger.error("Connection failed: \(error)")
            continuation?.resume(throwing: error)
            if let handler = connectionHandler {
                handler(false)
            }

        case .cancelled:
            logger.info("Connection cancelled")
            if let handler = connectionHandler {
                handler(false)
            }

        default:
            break
        }
    }

    /// Disconnect from the server
    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    /// Send a client message to the server
    func send(_ message: ClientMessage) async throws {
        guard let connection = connection else {
            throw NookClientError.notConnected
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        var messageData = data
        messageData.append(contentsOf: "\n".utf8)

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: messageData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Set the handler for incoming messages
    func setMessageHandler(_ handler: @escaping @Sendable (ServerMessage) -> Void) {
        messageHandler = handler
    }

    /// Set the handler for connection state changes
    func setConnectionHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        connectionHandler = handler
    }

    private func startReceiving() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task {
                await self?.handleReceive(content: content, isComplete: isComplete, error: error)
            }
        }
    }

    private func handleReceive(content: Data?, isComplete: Bool, error: NWError?) async {
        if let error = error {
            logger.error("Receive error: \(error)")
            return
        }

        if let content = content {
            buffer.append(content)
            processBuffer()
        }

        if isComplete {
            logger.info("Connection closed by server")
            disconnect()
        } else {
            startReceiving()
        }
    }

    private func processBuffer() {
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer = Data(buffer.suffix(from: buffer.index(after: newlineIndex)))

            guard !lineData.isEmpty else { continue }

            // Check for simple OK/ERR responses
            if let line = String(data: lineData, encoding: .utf8) {
                if line == "OK" {
                    logger.info("Received OK response")
                    continue
                }
                if line.hasPrefix("ERR:") {
                    logger.error("Received error: \(line)")
                    continue
                }
            }

            // Try to decode as ServerMessage
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let message = try decoder.decode(ServerMessage.self, from: lineData)

                if let handler = messageHandler {
                    handler(message)
                }
            } catch {
                logger.error("Failed to decode message: \(error)")
            }
        }
    }
}

enum NookClientError: Error, LocalizedError {
    case notConnected
    case authFailed(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to server"
        case .authFailed(let message):
            return "Authentication failed: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}
