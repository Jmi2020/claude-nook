//
//  iOSConnectionManager.swift
//  ClaudeNook
//
//  Manages connected iOS clients in SUBSCRIBE mode.
//  Broadcasts session updates and handles permission responses.
//

import ClaudeNookShared
import Foundation
import os.log

/// Logger for iOS connection management
private let logger = Logger(subsystem: "com.jmi2020.claudenook", category: "iOSConnection")

/// Represents a connected iOS client
struct iOSClient: Sendable {
    let socket: Int32
    let address: String
    let connectedAt: Date
    let id: UUID

    init(socket: Int32, address: String) {
        self.socket = socket
        self.address = address
        self.connectedAt = Date()
        self.id = UUID()
    }
}

/// Callback for iOS client messages
typealias iOSMessageHandler = @Sendable (_ clientId: UUID, _ message: iOSClientMessage) -> Void

/// Messages from iOS clients
enum iOSClientMessage: Sendable {
    case approve(sessionId: String, toolUseId: String)
    case deny(sessionId: String, toolUseId: String, reason: String?)
    case pong
    case disconnect
}

/// Manages iOS clients connected via SUBSCRIBE mode
class iOSConnectionManager {
    static let shared = iOSConnectionManager()

    private var clients: [UUID: iOSClient] = [:]
    private let clientsLock = NSLock()
    private let queue = DispatchQueue(label: "com.jmi2020.claudenook.ios", qos: .userInitiated)

    private var messageHandler: iOSMessageHandler?
    private var readSources: [UUID: DispatchSourceRead] = [:]

    /// Heartbeat timer
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatInterval: TimeInterval = 30

    private init() {}

    /// Set handler for incoming messages from iOS clients
    func setMessageHandler(_ handler: @escaping iOSMessageHandler) {
        messageHandler = handler
    }

    /// Add a new iOS client in SUBSCRIBE mode
    func addClient(socket: Int32, address: String) -> UUID {
        let client = iOSClient(socket: socket, address: address)

        clientsLock.lock()
        clients[client.id] = client
        clientsLock.unlock()

        // Set up read source for incoming messages
        setupReadSource(for: client)

        // Start heartbeat if this is the first client
        startHeartbeatIfNeeded()

        logger.info("iOS client connected: \(address, privacy: .public) (id: \(client.id.uuidString.prefix(8), privacy: .public))")

        return client.id
    }

    /// Remove an iOS client
    func removeClient(_ clientId: UUID) {
        clientsLock.lock()
        guard let client = clients.removeValue(forKey: clientId) else {
            clientsLock.unlock()
            return
        }
        clientsLock.unlock()

        // Cancel read source
        if let source = readSources.removeValue(forKey: clientId) {
            source.cancel()
        }

        close(client.socket)

        // Stop heartbeat if no clients
        stopHeartbeatIfEmpty()

        logger.info("iOS client disconnected: \(client.address, privacy: .public)")
    }

    /// Broadcast a server message to all connected iOS clients
    func broadcast(_ message: ServerMessageWrapper) {
        guard let data = encodeMessage(message) else { return }

        clientsLock.lock()
        let clientsCopy = clients
        clientsLock.unlock()

        for (clientId, client) in clientsCopy {
            queue.async { [weak self] in
                self?.sendData(data, to: client, clientId: clientId)
            }
        }
    }

    /// Send a message to a specific client
    func send(_ message: ServerMessageWrapper, to clientId: UUID) {
        guard let data = encodeMessage(message) else { return }

        clientsLock.lock()
        guard let client = clients[clientId] else {
            clientsLock.unlock()
            return
        }
        clientsLock.unlock()

        queue.async { [weak self] in
            self?.sendData(data, to: client, clientId: clientId)
        }
    }

    /// Get count of connected clients
    var clientCount: Int {
        clientsLock.lock()
        defer { clientsLock.unlock() }
        return clients.count
    }

    /// Check if any clients are connected
    var hasClients: Bool {
        clientCount > 0
    }

    // MARK: - Private Methods

    private func encodeMessage(_ message: ServerMessageWrapper) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard var data = try? encoder.encode(message) else {
            logger.error("Failed to encode server message")
            return nil
        }

        // Append newline as message delimiter
        data.append(contentsOf: [0x0A]) // \n
        return data
    }

    private func sendData(_ data: Data, to client: iOSClient, clientId: UUID) {
        let result = data.withUnsafeBytes { bytes -> Int in
            guard let baseAddress = bytes.baseAddress else { return -1 }
            return write(client.socket, baseAddress, data.count)
        }

        if result < 0 {
            logger.warning("Failed to send to iOS client \(client.address, privacy: .public): errno \(errno)")
            // Remove disconnected client
            removeClient(clientId)
        }
    }

    private func setupReadSource(for client: iOSClient) {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: client.socket, queue: queue)

        readSource.setEventHandler { [weak self] in
            self?.handleClientData(clientId: client.id, socket: client.socket)
        }

        readSource.setCancelHandler { [weak self] in
            self?.messageHandler?(client.id, .disconnect)
        }

        readSources[client.id] = readSource
        readSource.resume()
    }

    private func handleClientData(clientId: UUID, socket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(socket, &buffer, buffer.count)

        if bytesRead <= 0 {
            // Client disconnected
            removeClient(clientId)
            messageHandler?(clientId, .disconnect)
            return
        }

        guard let jsonString = String(bytes: buffer[0..<bytesRead], encoding: .utf8) else {
            return
        }

        // Parse each line as a separate message
        let lines = jsonString.components(separatedBy: "\n").filter { !$0.isEmpty }

        for line in lines {
            parseAndHandleMessage(line, from: clientId)
        }
    }

    private func parseAndHandleMessage(_ jsonString: String, from clientId: UUID) {
        guard let data = jsonString.data(using: .utf8),
              let wrapper = try? JSONDecoder().decode(ClientMessageWrapper.self, from: data) else {
            logger.warning("Failed to parse iOS client message: \(jsonString.prefix(100), privacy: .public)")
            return
        }

        let message: iOSClientMessage
        switch wrapper.type {
        case "approve":
            guard let sessionId = wrapper.sessionId,
                  let toolUseId = wrapper.toolUseId else {
                logger.warning("Approve message missing required fields")
                return
            }
            message = .approve(sessionId: sessionId, toolUseId: toolUseId)

        case "deny":
            guard let sessionId = wrapper.sessionId,
                  let toolUseId = wrapper.toolUseId else {
                logger.warning("Deny message missing required fields")
                return
            }
            message = .deny(sessionId: sessionId, toolUseId: toolUseId, reason: wrapper.reason)

        case "pong":
            message = .pong

        default:
            logger.warning("Unknown iOS client message type: \(wrapper.type, privacy: .public)")
            return
        }

        logger.debug("Received from iOS: \(wrapper.type, privacy: .public)")
        messageHandler?(clientId, message)
    }

    // MARK: - Heartbeat

    private func startHeartbeatIfNeeded() {
        guard heartbeatTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.sendHeartbeat()
        }
        heartbeatTimer = timer
        timer.resume()

        logger.debug("Started iOS heartbeat timer")
    }

    private func stopHeartbeatIfEmpty() {
        clientsLock.lock()
        let isEmpty = clients.isEmpty
        clientsLock.unlock()

        if isEmpty {
            heartbeatTimer?.cancel()
            heartbeatTimer = nil
            logger.debug("Stopped iOS heartbeat timer")
        }
    }

    private func sendHeartbeat() {
        broadcast(ServerMessageWrapper(type: "ping"))
    }
}

// MARK: - Wire Protocol Types

/// Server message wrapper for JSON encoding
struct ServerMessageWrapper: Codable {
    let type: String
    var payload: AnyCodable?

    init(type: String, payload: Any? = nil) {
        self.type = type
        self.payload = payload.map { AnyCodable($0) }
    }

    // Convenience initializers for specific message types
    static func state(_ snapshot: StateSnapshotData) -> ServerMessageWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot),
           let dict = try? JSONSerialization.jsonObject(with: data) {
            return ServerMessageWrapper(type: "state", payload: dict)
        }
        return ServerMessageWrapper(type: "state")
    }

    static func sessionUpdate(_ session: SessionStateLightData) -> ServerMessageWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(SessionUpdateData(session: session)),
           let dict = try? JSONSerialization.jsonObject(with: data) {
            return ServerMessageWrapper(type: "sessionUpdate", payload: dict)
        }
        return ServerMessageWrapper(type: "sessionUpdate")
    }

    static func sessionRemoved(sessionId: String) -> ServerMessageWrapper {
        return ServerMessageWrapper(type: "sessionRemoved", payload: sessionId)
    }

    static func permissionRequest(_ request: PermissionRequestData) -> ServerMessageWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(request),
           let dict = try? JSONSerialization.jsonObject(with: data) {
            return ServerMessageWrapper(type: "permissionRequest", payload: dict)
        }
        return ServerMessageWrapper(type: "permissionRequest")
    }

    static func permissionResolved(sessionId: String, toolUseId: String) -> ServerMessageWrapper {
        return ServerMessageWrapper(type: "permissionResolved", payload: [
            "sessionId": sessionId,
            "toolUseId": toolUseId
        ])
    }
}

/// Client message wrapper for JSON decoding
struct ClientMessageWrapper: Codable {
    let type: String
    var sessionId: String?
    var toolUseId: String?
    var reason: String?
}

// MARK: - Data Transfer Objects

/// Lightweight session state for iOS
struct SessionStateLightData: Codable {
    let sessionId: String
    let projectName: String
    let phase: String
    let lastActivity: Date
    let createdAt: Date
    let displayTitle: String
    let pendingToolName: String?
    let pendingToolInput: String?
    let needsAttention: Bool

    init(from session: SessionState) {
        self.sessionId = session.sessionId
        self.projectName = session.projectName
        self.phase = session.phase.rawValue
        self.lastActivity = session.lastActivity
        self.createdAt = session.createdAt
        self.displayTitle = session.displayTitle
        self.pendingToolName = session.pendingToolName
        self.pendingToolInput = session.pendingToolInput
        self.needsAttention = session.needsAttention
    }
}

/// Session update wrapper
struct SessionUpdateData: Codable {
    let session: SessionStateLightData
}

/// Full state snapshot for iOS
struct StateSnapshotData: Codable {
    let sessions: [SessionStateLightData]
    let timestamp: Date

    init(sessions: [SessionState]) {
        self.sessions = sessions.map { SessionStateLightData(from: $0) }
        self.timestamp = Date()
    }
}

/// Permission request for iOS
struct PermissionRequestData: Codable {
    let sessionId: String
    let toolUseId: String
    let toolName: String
    let toolInput: String?
    let projectName: String
    let receivedAt: Date

    init(sessionId: String, toolUseId: String, toolName: String, toolInput: String?, projectName: String) {
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.projectName = projectName
        self.receivedAt = Date()
    }
}
