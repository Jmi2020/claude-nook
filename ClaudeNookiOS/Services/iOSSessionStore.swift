//
//  iOSSessionStore.swift
//  ClaudeNookiOS
//
//  Local session state cache for iOS app.
//

import ClaudeNookShared
import Foundation
import os.log

private let logger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "SessionStore")

/// Local cache of session state for the iOS app
@MainActor
class iOSSessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionStateLight] = []
    @Published var pendingPermission: PermissionRequest?

    private var nookClient: NookClient?

    /// Set the NookClient to receive updates from
    func setClient(_ client: NookClient) async {
        nookClient = client

        await client.setMessageHandler { [weak self] message in
            Task { @MainActor in
                self?.handleMessage(message)
            }
        }
    }

    /// Handle incoming server message
    private func handleMessage(_ message: ServerMessage) {
        switch message {
        case .state(let snapshot):
            logger.info("Received full state with \(snapshot.sessions.count) sessions")
            sessions = snapshot.sessions

        case .sessionUpdate(let update):
            logger.info("Received session update for \(update.session.sessionId)")
            // Replace or add the session
            if let index = sessions.firstIndex(where: { $0.sessionId == update.session.sessionId }) {
                sessions[index] = update.session
            } else {
                sessions.append(update.session)
            }

        case .permissionRequest(let request):
            logger.info("Received permission request for \(request.toolName)")
            pendingPermission = request

        case .permissionResolved(let sessionId, let toolUseId):
            logger.info("Permission resolved for \(toolUseId) in session \(sessionId)")
            if pendingPermission?.toolUseId == toolUseId {
                pendingPermission = nil
            }

        case .sessionRemoved(let sessionId):
            logger.info("Session removed: \(sessionId)")
            sessions.removeAll { $0.sessionId == sessionId }

        case .ping:
            // Respond with pong
            Task {
                try? await nookClient?.send(.pong)
            }
        }
    }

    /// Approve a permission request
    func approve(request: PermissionRequest) async {
        logger.info("Approving \(request.toolName)")
        do {
            try await nookClient?.send(.approve(sessionId: request.sessionId, toolUseId: request.toolUseId))
            pendingPermission = nil
        } catch {
            logger.error("Failed to send approval: \(error)")
        }
    }

    /// Deny a permission request
    func deny(request: PermissionRequest, reason: String?) async {
        logger.info("Denying \(request.toolName)")
        do {
            try await nookClient?.send(.deny(sessionId: request.sessionId, toolUseId: request.toolUseId, reason: reason))
            pendingPermission = nil
        } catch {
            logger.error("Failed to send denial: \(error)")
        }
    }

    /// Request a fresh state snapshot
    func refresh() async {
        // Currently the server sends state on subscribe
        // Could add a refresh command if needed
    }
}
