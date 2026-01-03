//
//  StatusIndicator.swift
//  ClaudeNookiOS
//
//  Visual indicator for session phase matching macOS Nook style.
//

import ClaudeNookShared
import SwiftUI

struct StatusIndicator: View {
    let phase: SessionPhase

    @State private var spinnerPhase = 0
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        switch phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(TerminalColors.prompt)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
                .frame(width: 16)

        case .waitingForApproval:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(TerminalColors.amber)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
                .frame(width: 16)

        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 8, height: 8)
                .frame(width: 16)

        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 8, height: 8)
                .frame(width: 16)
        }
    }
}

// MARK: - SessionPhase Display Extension

extension SessionPhase {
    var displayName: String {
        switch self {
        case .processing:
            return "Processing"
        case .waitingForApproval:
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
    ZStack {
        Color.nookBackground
            .ignoresSafeArea()

        VStack(spacing: 20) {
            HStack {
                StatusIndicator(phase: .processing)
                Text("Processing")
                    .foregroundStyle(.white)
            }
            HStack {
                StatusIndicator(phase: .waitingForApproval(PermissionContext(
                    toolUseId: "test-123",
                    toolName: "Bash",
                    toolInput: nil,
                    receivedAt: Date()
                )))
                Text("Waiting for Approval")
                    .foregroundStyle(.white)
            }
            HStack {
                StatusIndicator(phase: .waitingForInput)
                Text("Waiting for Input")
                    .foregroundStyle(.white)
            }
            HStack {
                StatusIndicator(phase: .idle)
                Text("Idle")
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }
}
