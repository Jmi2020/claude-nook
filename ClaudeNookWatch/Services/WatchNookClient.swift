//
//  WatchNookClient.swift
//  ClaudeNookWatch
//
//  Simplified TCP client for watchOS.
//  Connects to Mac's Claude Nook server using NookProtocol.
//

import ClaudeNookShared
import Foundation
import Network
import os.log

actor WatchNookClient {
    private nonisolated let logger = Logger(subsystem: "com.jmi2020.claudenook-watch", category: "NookClient")
    private var connection: NWConnection?
    private var messageHandler: (@Sendable (ServerMessage) -> Void)?
    private var connectionHandler: (@Sendable (Bool) -> Void)?
    private var buffer = Data()

    private let queue = DispatchQueue(label: "com.jmi2020.claudenook-watch.client")

    var isConnected: Bool {
        connection?.state == .ready
    }

    func connect(host: String, port: Int, token: String?) async throws {
        logger.info("Connecting to \(host):\(port)")

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection

        let clientQueue = self.queue
        return try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.handleConnectionState(state, token: token, continuation: continuation)
                }
            }
            connection.start(queue: clientQueue)
        }
    }

    private func handleConnectionState(
        _ state: NWConnection.State,
        token: String?,
        continuation: CheckedContinuation<Void, Error>?
    ) async {
        switch state {
        case .ready:
            logger.info("Connection ready")
            if let token = token {
                let authMessage = "AUTH \(token)\n"
                connection?.send(content: authMessage.data(using: .utf8)!, completion: .contentProcessed { _ in })
            }
            let subscribeMessage = "SUBSCRIBE\n"
            connection?.send(content: subscribeMessage.data(using: .utf8)!, completion: .contentProcessed { _ in })
            startReceiving()
            continuation?.resume()
            connectionHandler?(true)

        case .failed(let error):
            logger.error("Connection failed: \(error)")
            continuation?.resume(throwing: error)
            connectionHandler?(false)

        case .cancelled:
            connectionHandler?(false)

        default:
            break
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ message: ClientMessage) async throws {
        guard let connection = connection else { throw WatchClientError.notConnected }
        let data = try JSONEncoder().encode(message)
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

    func setMessageHandler(_ handler: @escaping @Sendable (ServerMessage) -> Void) {
        messageHandler = handler
    }

    func setConnectionHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        connectionHandler = handler
    }

    private func startReceiving() {
        guard let connection = connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { await self?.handleReceive(content: content, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(content: Data?, isComplete: Bool, error: NWError?) async {
        if let content = content {
            buffer.append(content)
            processBuffer()
        }
        if isComplete {
            logger.info("Connection closed by server")
            disconnect()
            connectionHandler?(false)
        } else {
            startReceiving()
        }
    }

    private func processBuffer() {
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer = Data(buffer.suffix(from: buffer.index(after: newlineIndex)))
            guard !lineData.isEmpty else { continue }

            if let line = String(data: lineData, encoding: .utf8) {
                if line == "OK" { continue }
                if line.hasPrefix("ERR:") {
                    logger.error("Server error: \(line)")
                    continue
                }
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let message = try decoder.decode(ServerMessage.self, from: lineData)
                messageHandler?(message)
            } catch {
                logger.error("Failed to decode: \(error)")
            }
        }
    }
}

enum WatchClientError: Error, LocalizedError {
    case notConnected
    var errorDescription: String? { "Not connected to server" }
}
