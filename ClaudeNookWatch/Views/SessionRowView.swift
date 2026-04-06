//
//  SessionRowView.swift
//  ClaudeNookWatch
//
//  Compact session row with inline approve/deny for Watch.
//

import ClaudeNookShared
import SwiftUI

struct SessionRowView: View {
    let session: SessionStateLight
    let onApprove: () -> Void
    let onDeny: () -> Void

    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    if isWaitingForApproval, let tool = session.pendingToolName {
                        Text(tool)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(WatchColors.amber)
                            .lineLimit(1)
                    } else {
                        Text(session.projectName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            // Inline approve/deny buttons when waiting for approval
            if isWaitingForApproval {
                HStack(spacing: 8) {
                    Button {
                        onDeny()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchColors.red)

                    Button {
                        onApprove()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchColors.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.phase {
        case .waitingForApproval:
            return WatchColors.amber
        case .processing, .compacting:
            return WatchColors.orange
        case .waitingForInput:
            return WatchColors.green
        case .idle, .ended:
            return .gray
        }
    }
}
