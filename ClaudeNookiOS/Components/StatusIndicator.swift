//
//  StatusIndicator.swift
//  ClaudeNookiOS
//
//  Visual indicator for session phase.
//

import ClaudeNookShared
import SwiftUI

struct StatusIndicator: View {
    let phase: SessionPhase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if phase == .processing {
                        Circle()
                            .stroke(phaseColor, lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.5)
                    }
                }

            if showLabel {
                Text(phase.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showLabel: Bool {
        switch phase {
        case .waitingForApproval(_), .waitingForInput:
            return true
        default:
            return false
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .processing:
            return .blue
        case .waitingForApproval(_):
            return .orange
        case .waitingForInput:
            return .green
        case .idle:
            return .gray
        case .compacting:
            return .purple
        case .ended:
            return .secondary
        }
    }
}

// MARK: - SessionPhase Display Extension

extension SessionPhase {
    var displayName: String {
        switch self {
        case .processing:
            return "Processing"
        case .waitingForApproval(_):
            return "Needs Approval"
        case .waitingForInput:
            return "Waiting"
        case .idle:
            return "Idle"
        case .compacting:
            return "Compacting"
        case .ended:
            return "Ended"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusIndicator(phase: .processing)
        StatusIndicator(phase: .waitingForApproval(PermissionContext(
            toolUseId: "test-123",
            toolName: "Bash",
            toolInput: nil,
            receivedAt: Date()
        )))
        StatusIndicator(phase: .waitingForInput)
        StatusIndicator(phase: .idle)
        StatusIndicator(phase: .compacting)
        StatusIndicator(phase: .ended)
    }
    .padding()
}
