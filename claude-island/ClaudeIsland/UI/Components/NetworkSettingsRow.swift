//
//  NetworkSettingsRow.swift
//  ClaudeIsland
//
//  TCP network settings picker for settings menu
//

import SwiftUI
import AppKit

struct NetworkSettingsRow: View {
    @ObservedObject var networkSettings: NetworkSettings
    @State private var isHovered = false
    @State private var showTokenCopied = false
    @State private var portText: String = ""

    private var isExpanded: Bool {
        networkSettings.isPickerExpanded
    }

    private func setExpanded(_ value: Bool) {
        networkSettings.isPickerExpanded = value
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row - shows current mode
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    setExpanded(!isExpanded)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)

                    Text("Remote Access")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    Spacer()

                    statusIndicator

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Expanded configuration
            if isExpanded {
                VStack(spacing: 8) {
                    // Mode selection
                    ForEach(TCPBindMode.allCases, id: \.self) { mode in
                        NetworkModeOption(
                            mode: mode,
                            isSelected: networkSettings.configuration.bindMode == mode
                        ) {
                            networkSettings.updateBindMode(mode)
                        }
                    }

                    // Token and port sections (only if TCP enabled)
                    if networkSettings.isTCPEnabled {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.vertical, 4)

                        // Token section
                        tokenSection

                        // Port section
                        portSection

                        // Copy setup info button
                        copySetupButton
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture { } // Consume taps to prevent menu from closing
            }
        }
        .onAppear {
            portText = String(networkSettings.configuration.port)
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private var statusColor: Color {
        switch networkSettings.configuration.bindMode {
        case .disabled:
            return .white.opacity(0.3)
        case .localhost:
            return TerminalColors.amber
        case .anyInterface:
            return TerminalColors.green
        }
    }

    private var statusText: String {
        switch networkSettings.configuration.bindMode {
        case .disabled:
            return "Off"
        case .localhost:
            return "Local"
        case .anyInterface:
            return "Remote"
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    // MARK: - Token Section

    @ViewBuilder
    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Auth Token")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Button {
                    copyToken()
                } label: {
                    Text(showTokenCopied ? "Copied!" : "Copy")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(showTokenCopied ? TerminalColors.green : TerminalColors.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    _ = networkSettings.regenerateToken()
                } label: {
                    Text("Regenerate")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TerminalColors.amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            if networkSettings.hasValidToken {
                Text(networkSettings.maskedToken)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("No token - click Regenerate")
                    .font(.system(size: 10))
                    .foregroundColor(TerminalColors.amber)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Port Section

    @ViewBuilder
    private var portSection: some View {
        HStack {
            Text("Port")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            TextField("", text: $portText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 60)
                .padding(4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
                .onSubmit {
                    if let port = UInt16(portText), port > 1024 {
                        networkSettings.updatePort(port)
                    } else {
                        portText = String(networkSettings.configuration.port)
                    }
                }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Copy Setup Button

    @ViewBuilder
    private var copySetupButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                copySetupInfo()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showTokenCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(showTokenCopied ? "Copied!" : "Copy Remote Setup Info")
                        .font(.system(size: 11))
                }
                .foregroundColor(showTokenCopied ? TerminalColors.green : TerminalColors.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(networkSettings.currentToken, forType: .string)
        withAnimation {
            showTokenCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showTokenCopied = false
            }
        }
    }

    private func copySetupInfo() {
        let info = networkSettings.getConnectionInfo()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        withAnimation {
            showTokenCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showTokenCopied = false
            }
        }
    }
}

// MARK: - Network Mode Option

private struct NetworkModeOption: View {
    let mode: TCPBindMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? TerminalColors.green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                    Text(mode.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(TerminalColors.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
