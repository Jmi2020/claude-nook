//
//  NookProtocol.swift
//  ClaudeNookShared
//
//  Protocol definitions for Claude Nook client-server communication.
//  Used for iOS companion app to communicate with macOS server.
//

import Foundation

// MARK: - Protocol Messages

/// Messages sent from server (macOS) to client (iOS)
public enum ServerMessage: Codable, Sendable {
    /// Full state snapshot (sent after SUBSCRIBE)
    case state(StateSnapshot)

    /// Incremental session update
    case sessionUpdate(SessionUpdate)

    /// Session was removed
    case sessionRemoved(sessionId: String)

    /// Permission request requiring action
    case permissionRequest(PermissionRequest)

    /// Permission was resolved (by macOS or another client)
    case permissionResolved(sessionId: String, toolUseId: String)

    /// Heartbeat/ping
    case ping

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case state
        case sessionUpdate
        case sessionRemoved
        case permissionRequest
        case permissionResolved
        case ping
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .state:
            let snapshot = try container.decode(StateSnapshot.self, forKey: .payload)
            self = .state(snapshot)
        case .sessionUpdate:
            let update = try container.decode(SessionUpdate.self, forKey: .payload)
            self = .sessionUpdate(update)
        case .sessionRemoved:
            let sessionId = try container.decode(String.self, forKey: .payload)
            self = .sessionRemoved(sessionId: sessionId)
        case .permissionRequest:
            let request = try container.decode(PermissionRequest.self, forKey: .payload)
            self = .permissionRequest(request)
        case .permissionResolved:
            let resolved = try container.decode(PermissionResolved.self, forKey: .payload)
            self = .permissionResolved(sessionId: resolved.sessionId, toolUseId: resolved.toolUseId)
        case .ping:
            self = .ping
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .state(let snapshot):
            try container.encode(MessageType.state, forKey: .type)
            try container.encode(snapshot, forKey: .payload)
        case .sessionUpdate(let update):
            try container.encode(MessageType.sessionUpdate, forKey: .type)
            try container.encode(update, forKey: .payload)
        case .sessionRemoved(let sessionId):
            try container.encode(MessageType.sessionRemoved, forKey: .type)
            try container.encode(sessionId, forKey: .payload)
        case .permissionRequest(let request):
            try container.encode(MessageType.permissionRequest, forKey: .type)
            try container.encode(request, forKey: .payload)
        case .permissionResolved(let sessionId, let toolUseId):
            try container.encode(MessageType.permissionResolved, forKey: .type)
            try container.encode(PermissionResolved(sessionId: sessionId, toolUseId: toolUseId), forKey: .payload)
        case .ping:
            try container.encode(MessageType.ping, forKey: .type)
        }
    }
}

/// Messages sent from client (iOS) to server (macOS)
public enum ClientMessage: Codable, Sendable {
    /// Subscribe to session updates
    case subscribe

    /// Approve a permission request
    case approve(sessionId: String, toolUseId: String)

    /// Deny a permission request
    case deny(sessionId: String, toolUseId: String, reason: String?)

    /// Heartbeat/pong
    case pong

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case sessionId
        case toolUseId
        case reason
    }

    private enum MessageType: String, Codable {
        case subscribe
        case approve
        case deny
        case pong
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .subscribe:
            self = .subscribe
        case .approve:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            self = .approve(sessionId: sessionId, toolUseId: toolUseId)
        case .deny:
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self = .deny(sessionId: sessionId, toolUseId: toolUseId, reason: reason)
        case .pong:
            self = .pong
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .subscribe:
            try container.encode(MessageType.subscribe, forKey: .type)
        case .approve(let sessionId, let toolUseId):
            try container.encode(MessageType.approve, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(toolUseId, forKey: .toolUseId)
        case .deny(let sessionId, let toolUseId, let reason):
            try container.encode(MessageType.deny, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encodeIfPresent(reason, forKey: .reason)
        case .pong:
            try container.encode(MessageType.pong, forKey: .type)
        }
    }
}

// MARK: - Payload Types

/// Full state snapshot
public struct StateSnapshot: Codable, Sendable {
    public let sessions: [SessionStateLight]
    public let timestamp: Date

    public init(sessions: [SessionStateLight], timestamp: Date = Date()) {
        self.sessions = sessions
        self.timestamp = timestamp
    }
}

/// Lightweight session state for iOS (without full chat history)
public struct SessionStateLight: Identifiable, Codable, Sendable, Hashable {
    public let sessionId: String
    public let projectName: String
    public let phase: SessionPhase
    public let lastActivity: Date
    public let createdAt: Date
    public let displayTitle: String
    public let pendingToolName: String?
    public let pendingToolInput: String?

    public var id: String { sessionId }

    /// Whether this session needs user attention
    public var needsAttention: Bool {
        phase.needsAttention
    }

    public init(
        sessionId: String,
        projectName: String,
        phase: SessionPhase,
        lastActivity: Date,
        createdAt: Date,
        displayTitle: String,
        pendingToolName: String?,
        pendingToolInput: String?
    ) {
        self.sessionId = sessionId
        self.projectName = projectName
        self.phase = phase
        self.lastActivity = lastActivity
        self.createdAt = createdAt
        self.displayTitle = displayTitle
        self.pendingToolName = pendingToolName
        self.pendingToolInput = pendingToolInput
    }

    /// Create from full SessionState
    public init(from session: SessionState) {
        self.sessionId = session.sessionId
        self.projectName = session.projectName
        self.phase = session.phase
        self.lastActivity = session.lastActivity
        self.createdAt = session.createdAt
        self.displayTitle = session.displayTitle
        self.pendingToolName = session.pendingToolName
        self.pendingToolInput = session.pendingToolInput
    }
}

/// Session update (phase change, activity update)
public struct SessionUpdate: Codable, Sendable {
    public let session: SessionStateLight

    public init(session: SessionStateLight) {
        self.session = session
    }

    public init(from fullSession: SessionState) {
        self.session = SessionStateLight(from: fullSession)
    }
}

/// Permission request for iOS display
public struct PermissionRequest: Codable, Sendable, Identifiable {
    public var id: String { toolUseId }

    public let sessionId: String
    public let toolUseId: String
    public let toolName: String
    public let toolInput: String?
    public let projectName: String
    public let receivedAt: Date

    public init(
        sessionId: String,
        toolUseId: String,
        toolName: String,
        toolInput: String?,
        projectName: String,
        receivedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.toolUseId = toolUseId
        self.toolName = toolName
        self.toolInput = toolInput
        self.projectName = projectName
        self.receivedAt = receivedAt
    }

    /// Create from SessionState with pending permission
    public init?(from session: SessionState) {
        guard let permission = session.activePermission else { return nil }
        self.sessionId = session.sessionId
        self.toolUseId = permission.toolUseId
        self.toolName = permission.toolName
        self.toolInput = permission.formattedInput
        self.projectName = session.projectName
        self.receivedAt = permission.receivedAt
    }
}

/// Permission resolved notification
private struct PermissionResolved: Codable {
    let sessionId: String
    let toolUseId: String
}

// MARK: - Protocol Constants

public enum NookProtocolConstants {
    /// Default TCP port for Claude Nook server
    public static let defaultPort: UInt16 = 4851

    /// Bonjour service type for discovery
    public static let bonjourServiceType = "_claudenook._tcp."

    /// Authentication token length (64 hex chars = 32 bytes)
    public static let tokenLength = 64

    /// Heartbeat interval in seconds
    public static let heartbeatInterval: TimeInterval = 30

    /// Connection timeout in seconds
    public static let connectionTimeout: TimeInterval = 10

    /// Reconnection delay in seconds
    public static let reconnectionDelay: TimeInterval = 5
}
