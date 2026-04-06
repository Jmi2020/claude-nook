//
//  WatchSessionStore.swift
//  ClaudeNookWatch
//
//  Session state cache with haptic feedback for permission requests.
//

import ClaudeNookShared
import Foundation
import os.log
import WatchKit

private let logger = Logger(subsystem: "com.jmi2020.claudenook-watch", category: "SessionStore")

@MainActor
class WatchSessionStore: ObservableObject {
    @Published private(set) var sessions: [SessionStateLight] = []
    @Published var pendingPermission: PermissionRequest?

    private var nookClient: WatchNookClient?

    func setClient(_ client: WatchNookClient) async {
        nookClient = client
        await client.setMessageHandler { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleMessage(message)
            }
        }
    }

    private func handleMessage(_ message: ServerMessage) {
        switch message {
        case .state(let snapshot):
            logger.info("Full state: \(snapshot.sessions.count) sessions")
            sessions = snapshot.sessions

        case .sessionUpdate(let update):
            if let index = sessions.firstIndex(where: { $0.sessionId == update.session.sessionId }) {
                var updated = update.session
                if updated.chatItems.isEmpty && !sessions[index].chatItems.isEmpty {
                    updated = SessionStateLight(
                        sessionId: updated.sessionId, projectName: updated.projectName,
                        phase: updated.phase, lastActivity: updated.lastActivity,
                        createdAt: updated.createdAt, displayTitle: updated.displayTitle,
                        pendingToolName: updated.pendingToolName, pendingToolInput: updated.pendingToolInput,
                        chatItems: sessions[index].chatItems
                    )
                }
                sessions[index] = updated
            } else {
                sessions.append(update.session)
            }

        case .permissionRequest(let request):
            logger.info("Permission request: \(request.toolName)")
            pendingPermission = request
            WKInterfaceDevice.current().play(.notification)

        case .permissionResolved(_, let toolUseId):
            if pendingPermission?.toolUseId == toolUseId {
                pendingPermission = nil
            }

        case .sessionRemoved(let sessionId):
            sessions.removeAll { $0.sessionId == sessionId }

        case .ping:
            Task { try? await nookClient?.send(.pong) }
        }
    }

    func approve(request: PermissionRequest) async {
        do {
            try await nookClient?.send(.approve(sessionId: request.sessionId, toolUseId: request.toolUseId))
            pendingPermission = nil
            WKInterfaceDevice.current().play(.success)
        } catch {
            logger.error("Approve failed: \(error)")
        }
    }

    func deny(request: PermissionRequest) async {
        do {
            try await nookClient?.send(.deny(sessionId: request.sessionId, toolUseId: request.toolUseId, reason: nil))
            pendingPermission = nil
            WKInterfaceDevice.current().play(.failure)
        } catch {
            logger.error("Deny failed: \(error)")
        }
    }
}
