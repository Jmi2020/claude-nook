//
//  SessionRow.swift
//  ClaudeNookiOS
//
//  Row view for displaying a session matching macOS Nook design.
//

import ClaudeNookShared
import SwiftUI

struct SessionRow: View {
    let session: SessionStateLight
    let onChat: () -> Void
    let onApprove: () -> Void
    let onDeny: () -> Void

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // State indicator on left
            StatusIndicator(phase: session.phase)

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Show tool call when waiting for approval, otherwise last activity
                secondaryText
            }

            Spacer(minLength: 0)

            // Action buttons or approval buttons
            if isWaitingForApproval {
                InlineApprovalButtons(
                    onChat: onChat,
                    onApprove: onApprove,
                    onDeny: onDeny
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                HStack(spacing: 10) {
                    // Chat icon
                    IconButton(icon: "bubble.left", action: onChat)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.nookSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
    }

    @ViewBuilder
    private var secondaryText: some View {
        if isWaitingForApproval, let toolName = session.pendingToolName {
            // Show tool name in amber + input on same line
            HStack(spacing: 6) {
                Text(toolName)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber.opacity(0.9))

                if let input = session.pendingToolInput {
                    Text(input)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        } else {
            // Show project name / last message
            Text(session.projectName)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
    }
}

// MARK: - Inline Approval Buttons

struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onDeny: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 8) {
            // Chat button
            IconButton(icon: "bubble.left", action: onChat)
                .opacity(showChatButton ? 1 : 0)
                .scaleEffect(showChatButton ? 1 : 0.8)

            Button(action: onDeny) {
                Text("Deny")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button(action: onApprove) {
                Text("Allow")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.nookBackground
            .ignoresSafeArea()

        VStack(spacing: 8) {
            // Processing session
            SessionRow(
                session: SessionStateLight(
                    sessionId: "test-1",
                    projectName: "Dusk",
                    phase: .processing,
                    lastActivity: Date(),
                    createdAt: Date(),
                    displayTitle: "Search tool enhanced across all sections",
                    pendingToolName: nil,
                    pendingToolInput: nil
                ),
                onChat: {},
                onApprove: {},
                onDeny: {}
            )

            // Waiting for approval
            SessionRow(
                session: SessionStateLight(
                    sessionId: "test-2",
                    projectName: "my-project",
                    phase: .waitingForApproval(PermissionContext(
                        toolUseId: "tool-456",
                        toolName: "Bash",
                        toolInput: nil,
                        receivedAt: Date()
                    )),
                    lastActivity: Date(),
                    createdAt: Date(),
                    displayTitle: "im having trouble with the feature that loads f...",
                    pendingToolName: "Bash",
                    pendingToolInput: "cd /Users/silverlinings/Desktop/Coding/SuperPhoto/..."
                ),
                onChat: {},
                onApprove: {},
                onDeny: {}
            )

            // Waiting for input (green dot)
            SessionRow(
                session: SessionStateLight(
                    sessionId: "test-3",
                    projectName: "Python",
                    phase: .waitingForInput,
                    lastActivity: Date(),
                    createdAt: Date(),
                    displayTitle: "Python",
                    pendingToolName: nil,
                    pendingToolInput: nil
                ),
                onChat: {},
                onApprove: {},
                onDeny: {}
            )
        }
        .padding()
    }
}
