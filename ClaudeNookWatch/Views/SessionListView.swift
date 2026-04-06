//
//  SessionListView.swift
//  ClaudeNookWatch
//
//  Session list with priority sorting and inline approval.
//

import ClaudeNookShared
import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var sessionStore: WatchSessionStore
    @Binding var isConnected: Bool

    private var sortedSessions: [SessionStateLight] {
        sessionStore.sessions.sorted { a, b in
            let pa = phasePriority(a.phase)
            let pb = phasePriority(b.phase)
            if pa != pb { return pa < pb }
            return a.lastActivity > b.lastActivity
        }
    }

    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    var body: some View {
        Group {
            if sessionStore.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No sessions")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    if !isConnected {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(WatchColors.amber)
                                .font(.caption2)
                            Text("Disconnected")
                                .font(.caption2)
                                .foregroundStyle(WatchColors.amber)
                        }
                    }

                    ForEach(sortedSessions) { session in
                        SessionRowView(
                            session: session,
                            onApprove: { approveSession(session) },
                            onDeny: { denySession(session) }
                        )
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .sheet(item: $sessionStore.pendingPermission) { request in
            PermissionDetailView(request: request)
        }
    }

    private func approveSession(_ session: SessionStateLight) {
        guard case .waitingForApproval(let ctx) = session.phase else { return }
        let request = PermissionRequest(
            sessionId: session.sessionId,
            toolUseId: ctx.toolUseId,
            toolName: ctx.toolName,
            toolInput: nil,
            projectName: session.projectName
        )
        Task { await sessionStore.approve(request: request) }
    }

    private func denySession(_ session: SessionStateLight) {
        guard case .waitingForApproval(let ctx) = session.phase else { return }
        let request = PermissionRequest(
            sessionId: session.sessionId,
            toolUseId: ctx.toolUseId,
            toolName: ctx.toolName,
            toolInput: nil,
            projectName: session.projectName
        )
        Task { await sessionStore.deny(request: request) }
    }
}
