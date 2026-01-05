//
//  ConnectionStatusPill.swift
//  ClaudeNook
//
//  Compact status indicator for hook connection state
//

import SwiftUI

struct ConnectionStatusPill: View {
    @ObservedObject private var status = ConnectionStatusService.shared
    @ObservedObject private var networkSettings = NetworkSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            if networkSettings.isTCPEnabled, let endpoint = status.tcpEndpoint {
                Text(endpoint)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            } else {
                Text("Local only")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TerminalColors.background)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        if networkSettings.isTCPEnabled {
            switch status.tcpState {
            case .connected:
                return TerminalColors.green
            case .connecting:
                return TerminalColors.amber
            case .disconnected:
                return TerminalColors.dim
            }
        } else {
            switch status.unixState {
            case .connected:
                return TerminalColors.green
            case .connecting:
                return TerminalColors.amber
            case .disconnected:
                return TerminalColors.dim
            }
        }
    }
}
