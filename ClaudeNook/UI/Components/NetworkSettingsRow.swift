//
//  NetworkSettingsRow.swift
//  ClaudeNook
//
//  TCP network settings picker for settings menu
//

import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

struct NetworkSettingsRow: View {
    @ObservedObject var networkSettings: NetworkSettings
    @ObservedObject var pairingManager = PairingCodeManager.shared
    @ObservedObject var bluetoothService = BluetoothPairingService.shared
    @State private var isHovered = false
    @State private var showTokenCopied = false
    @State private var portText: String = ""
    @State private var showQRCode = false
    @State private var showPairingCode = false

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

                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.vertical, 4)

                        // iOS Pairing section
                        iOSPairingSection
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
        .sheet(isPresented: $showQRCode) {
            QRCodeSheet(networkSettings: networkSettings)
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

    // MARK: - iOS Pairing Section

    @ViewBuilder
    private var iOSPairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iOS App Pairing")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            // First row: QR Code and Pairing Code
            HStack(spacing: 8) {
                // QR Code button
                Button {
                    showQRCode = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 10))
                        Text("QR Code")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(TerminalColors.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)

                // Pairing Code button
                Button {
                    if pairingManager.isCodeActive {
                        pairingManager.expireCode()
                    } else {
                        _ = pairingManager.generateCode()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: pairingManager.isCodeActive ? "xmark" : "number")
                            .font(.system(size: 10))
                        Text(pairingManager.isCodeActive ? "Cancel" : "Code")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(pairingManager.isCodeActive ? TerminalColors.amber : TerminalColors.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }

            // Bluetooth button (full width)
            Button {
                if bluetoothService.isAdvertising {
                    bluetoothService.stopAdvertising()
                } else {
                    bluetoothService.startAdvertising()
                }
            } label: {
                HStack(spacing: 6) {
                    if case .advertising = bluetoothService.state {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: bluetoothIcon)
                            .font(.system(size: 10))
                    }
                    Text(bluetoothButtonText)
                        .font(.system(size: 11))
                }
                .foregroundColor(bluetoothButtonColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)

            // Bluetooth status
            if bluetoothService.state != .idle {
                BluetoothStatusView(state: bluetoothService.state)
            }

            // Show pairing code if active
            if pairingManager.isCodeActive, let code = pairingManager.currentCode {
                PairingCodeDisplay(code: code, remainingSeconds: pairingManager.remainingSeconds)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Bluetooth Helpers

    private var bluetoothIcon: String {
        switch bluetoothService.state {
        case .idle:
            return "antenna.radiowaves.left.and.right"
        case .poweredOff:
            return "antenna.radiowaves.left.and.right.slash"
        case .unauthorized:
            return "exclamationmark.triangle"
        case .advertising:
            return "antenna.radiowaves.left.and.right"
        case .connected:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var bluetoothButtonText: String {
        switch bluetoothService.state {
        case .idle:
            return "Bluetooth Pairing"
        case .poweredOff:
            return "Bluetooth Off"
        case .unauthorized:
            return "Bluetooth Unauthorized"
        case .advertising:
            return "Stop Bluetooth"
        case .connected:
            return "Connected via Bluetooth"
        case .error:
            return "Bluetooth Error"
        }
    }

    private var bluetoothButtonColor: Color {
        switch bluetoothService.state {
        case .idle:
            return TerminalColors.blue
        case .poweredOff, .unauthorized, .error:
            return TerminalColors.amber
        case .advertising:
            return TerminalColors.amber
        case .connected:
            return TerminalColors.green
        }
    }
}

// MARK: - Bluetooth Status View

private struct BluetoothStatusView: View {
    let state: BluetoothPairingState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(state.description)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch state {
        case .idle:
            return .white.opacity(0.3)
        case .poweredOff, .unauthorized, .error:
            return TerminalColors.amber
        case .advertising:
            return TerminalColors.blue
        case .connected:
            return TerminalColors.green
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

// MARK: - Pairing Code Display

private struct PairingCodeDisplay: View {
    let code: String
    let remainingSeconds: Int

    @State private var timeRemaining: Int

    init(code: String, remainingSeconds: Int) {
        self.code = code
        self.remainingSeconds = remainingSeconds
        self._timeRemaining = State(initialValue: remainingSeconds)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Large code display
            HStack(spacing: 8) {
                ForEach(Array(code), id: \.self) { digit in
                    Text(String(digit))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 40)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
            }

            // Countdown timer
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text("Expires in \(timeRemaining)s")
                    .font(.system(size: 11))
            }
            .foregroundColor(timeRemaining <= 30 ? TerminalColors.amber : .white.opacity(0.5))
        }
        .padding(.vertical, 8)
        .onAppear {
            startCountdown()
        }
    }

    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - QR Code Sheet

struct QRCodeSheet: View {
    @ObservedObject var networkSettings: NetworkSettings
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Scan with Claude Nook iOS")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            // QR Code
            if let qrImage = generateQRCode() {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(TerminalColors.amber)
                    Text("Could not generate QR code")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(width: 200, height: 200)
            }

            // Instructions
            VStack(spacing: 4) {
                Text("Open Claude Nook on your iPhone")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Text("Tap \"Scan QR Code\" to connect")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            // Connection info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Host:")
                        .foregroundColor(.white.opacity(0.5))
                    Text(getLocalIP() ?? "Unknown")
                        .foregroundColor(.white)
                }
                HStack {
                    Text("Port:")
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(networkSettings.configuration.port)")
                        .foregroundColor(.white)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(24)
        .frame(width: 300)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    private func generateQRCode() -> NSImage? {
        guard let host = getLocalIP() else { return nil }

        // Create connection URL
        let urlString = "claudenook://connect?host=\(host)&port=\(networkSettings.configuration.port)&token=\(networkSettings.currentToken)"

        guard let data = urlString.data(using: .utf8) else { return nil }

        // Generate QR code
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up the QR code
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scale)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }

            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            // Look for en0 (WiFi) or en1 (Ethernet)
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            address = String(cString: hostname)
            break
        }

        return address
    }
}
