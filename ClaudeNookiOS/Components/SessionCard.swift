//
//  SessionCard.swift
//  ClaudeNookiOS
//
//  Card view for displaying a session in the grid.
//

import ClaudeNookShared
import SwiftUI

struct SessionCard: View {
    let session: SessionStateLight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status row
            HStack {
                StatusIndicator(phase: session.phase)

                Spacer()

                if session.phase.isWaitingForApproval {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            // Project name
            Text(session.projectName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            // Display title (summary or first message)
            Text(session.displayTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            // Pending tool if waiting for approval
            if let toolName = session.pendingToolName {
                HStack {
                    Image(systemName: toolIcon(for: toolName))
                        .font(.caption)

                    Text(toolName)
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }

            // Last activity
            Text(formatTimestamp(session.lastActivity))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(height: 160)
        .background(Color.nookSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: session.phase.isWaitingForApproval ? 2 : 0)
        )
    }

    private var borderColor: Color {
        session.phase.isWaitingForApproval ? .orange : .clear
    }

    private func toolIcon(for tool: String) -> String {
        switch tool.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "pencil"
        case "edit": return "pencil.line"
        case "glob": return "folder.badge.gearshape"
        case "grep": return "magnifyingglass"
        case "task": return "person.2"
        default: return "wrench"
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ZStack {
        Color.nookBackground
            .ignoresSafeArea()

        SessionCard(session: SessionStateLight(
            sessionId: "test-123",
            projectName: "my-project",
            phase: .waitingForApproval(PermissionContext(
                toolUseId: "tool-456",
                toolName: "Bash",
                toolInput: nil,
                receivedAt: Date()
            )),
            lastActivity: Date(),
            createdAt: Date(),
            displayTitle: "Help me implement a new feature",
            pendingToolName: "Bash",
            pendingToolInput: "npm install"
        ))
        .frame(width: 180)
    }
}
