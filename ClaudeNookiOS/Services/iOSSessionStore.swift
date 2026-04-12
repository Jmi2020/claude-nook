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
            Task { @MainActor [weak self] in
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
            // Replace or add the session, preserving chat items and classification from incremental updates
            if let index = sessions.firstIndex(where: { $0.sessionId == update.session.sessionId }) {
                var updated = update.session
                let existing = sessions[index]
                // Incremental updates may not include chatItems or classification — preserve existing
                let chatItems = updated.chatItems.isEmpty ? existing.chatItems : updated.chatItems
                let classification = updated.classification ?? existing.classification
                if chatItems != updated.chatItems || classification != updated.classification {
                    updated = SessionStateLight(
                        sessionId: updated.sessionId,
                        projectName: updated.projectName,
                        phase: updated.phase,
                        lastActivity: updated.lastActivity,
                        createdAt: updated.createdAt,
                        displayTitle: updated.displayTitle,
                        pendingToolName: updated.pendingToolName,
                        pendingToolInput: updated.pendingToolInput,
                        chatItems: chatItems,
                        classification: classification
                    )
                }
                sessions[index] = updated
            } else {
                sessions.append(update.session)
            }

        case .permissionRequest(let request):
            logger.info("Received permission request for \(request.toolName)")
            pendingPermission = request
            NotificationManager.shared.schedulePermissionNotification(for: request)

        case .permissionResolved(let sessionId, let toolUseId):
            logger.info("Permission resolved for \(toolUseId) in session \(sessionId)")
            if pendingPermission?.toolUseId == toolUseId {
                pendingPermission = nil
            }
            NotificationManager.shared.removePermissionNotification(toolUseId: toolUseId)

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

    /// Update session phase locally for immediate feedback
    func updateSessionPhase(sessionId: String, to newPhase: SessionPhase) {
        guard let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else {
            return
        }

        let session = sessions[index]
        let updatedSession = SessionStateLight(
            sessionId: session.sessionId,
            projectName: session.projectName,
            phase: newPhase,
            lastActivity: Date(),
            createdAt: session.createdAt,
            displayTitle: session.displayTitle,
            pendingToolName: nil,  // Clear pending tool when phase changes
            pendingToolInput: nil,
            chatItems: session.chatItems,  // Preserve existing chat history
            classification: session.classification  // Preserve classification
        )
        sessions[index] = updatedSession
        logger.info("Updated session \(sessionId.prefix(8)) phase to \(newPhase)")
    }
}
