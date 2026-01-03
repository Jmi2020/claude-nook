//
//  BluetoothPairingView.swift
//  ClaudeNookiOS
//
//  Bluetooth LE pairing view for discovering and connecting to Mac.
//

import ClaudeNookShared
import SwiftUI

struct BluetoothPairingView: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @Environment(\.dismiss) var dismiss

    @StateObject private var bluetoothManager = BluetoothPairingManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Bluetooth icon
                    bluetoothIcon

                    // Status text
                    statusText

                    // Content based on state
                    contentView

                    Spacer()

                    // Action buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Bluetooth Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        bluetoothManager.cleanup()
                        dismiss()
                    }
                    .foregroundStyle(.nookAccent)
                }
            }
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                bluetoothManager.startScanning()
                bluetoothManager.onPairingComplete = { host, port, token in
                    // Connect using the received token
                    connectionVM.connectManually(host: host, port: port, token: token)
                    dismiss()
                }
            }
            .onDisappear {
                bluetoothManager.onPairingComplete = nil
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Bluetooth Icon

    @ViewBuilder
    private var bluetoothIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 100, height: 100)

            if case .scanning = bluetoothManager.state {
                // Animated scanning indicator
                Circle()
                    .stroke(Color.nookAccent.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(animationScale)
                    .opacity(animationOpacity)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: animationScale)
            }

            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(iconColor)
        }
        .padding(.top, 40)
        .onAppear {
            animationScale = 1.5
            animationOpacity = 0
        }
    }

    @State private var animationScale: CGFloat = 1.0
    @State private var animationOpacity: Double = 1.0

    private var iconName: String {
        switch bluetoothManager.state {
        case .idle, .scanning:
            return "antenna.radiowaves.left.and.right"
        case .poweredOff:
            return "antenna.radiowaves.left.and.right.slash"
        case .unauthorized:
            return "exclamationmark.triangle"
        case .connecting, .connected, .receivingToken:
            return "laptopcomputer"
        case .success:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch bluetoothManager.state {
        case .idle, .scanning, .connecting, .connected, .receivingToken:
            return .nookAccent
        case .poweredOff, .unauthorized, .error:
            return .orange
        case .success:
            return .green
        }
    }

    private var iconBackgroundColor: Color {
        iconColor.opacity(0.2)
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusText: some View {
        VStack(spacing: 8) {
            Text(statusTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var statusTitle: String {
        switch bluetoothManager.state {
        case .idle:
            return "Ready to Scan"
        case .poweredOff:
            return "Bluetooth Off"
        case .unauthorized:
            return "Permission Required"
        case .scanning:
            return "Searching..."
        case .connecting(let macName):
            return "Connecting to \(macName)"
        case .connected(let macName):
            return "Connected to \(macName)"
        case .receivingToken:
            return "Receiving Token..."
        case .success:
            return "Paired Successfully!"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }

    private var statusSubtitle: String {
        switch bluetoothManager.state {
        case .idle:
            return "Tap Start Scanning to find nearby Macs"
        case .poweredOff:
            return "Please enable Bluetooth in Settings"
        case .unauthorized:
            return "Please allow Bluetooth access in Settings"
        case .scanning:
            return "Make sure Bluetooth Pairing is enabled on your Mac"
        case .connecting:
            return "Establishing secure connection..."
        case .connected:
            return "Reading authentication data..."
        case .receivingToken:
            return "Receiving connection credentials..."
        case .success:
            return "You're all set! Connecting now..."
        case .error:
            return "Tap Try Again to retry"
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch bluetoothManager.state {
        case .scanning:
            if bluetoothManager.discoveredMacs.isEmpty {
                // No Macs found yet
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.nookAccent)

                    Text("Looking for Claude Nook on nearby Macs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
            } else {
                // Show discovered Macs
                discoveredMacsList
            }

        case .idle, .poweredOff, .unauthorized, .error:
            // Show instructions or error message
            instructionsView

        case .connecting, .connected, .receivingToken:
            // Show progress indicator
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.nookAccent)

                Text("Please wait...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

        case .success:
            // Show success animation
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)

                Text("Connection will start automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Discovered Macs List

    @ViewBuilder
    private var discoveredMacsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby Macs")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(bluetoothManager.discoveredMacs) { mac in
                        DiscoveredMacRow(mac: mac) {
                            bluetoothManager.connect(to: mac)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Instructions View

    @ViewBuilder
    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to pair via Bluetooth:")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(number: 1, text: "Open Claude Nook on your Mac")
                InstructionRow(number: 2, text: "Go to Settings → Remote Access")
                InstructionRow(number: 3, text: "Click \"Bluetooth Pairing\"")
                InstructionRow(number: 4, text: "Your Mac will appear here")
            }
        }
        .padding()
        .background(Color.nookSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            switch bluetoothManager.state {
            case .idle, .error:
                Button {
                    bluetoothManager.startScanning()
                } label: {
                    Label("Start Scanning", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NookButtonStyle(isPrimary: true))

            case .scanning:
                Button {
                    bluetoothManager.stopScanning()
                } label: {
                    Label("Stop Scanning", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NookButtonStyle(isPrimary: false))

            case .poweredOff, .unauthorized:
                Button {
                    // Open Settings
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NookButtonStyle(isPrimary: true))

            case .connecting, .connected, .receivingToken, .success:
                // No action button needed while connecting
                EmptyView()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 40)
    }
}

// MARK: - Discovered Mac Row

struct DiscoveredMacRow: View {
    let mac: DiscoveredBluetoothMac
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(.nookAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mac.name)
                        .font(.headline)
                        .foregroundStyle(.white)

                    HStack(spacing: 4) {
                        // Signal strength indicator
                        Image(systemName: signalIcon(for: mac.rssi))
                            .font(.caption2)
                        Text(signalText(for: mac.rssi))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.nookSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func signalIcon(for rssi: Int) -> String {
        if rssi > -50 {
            return "wifi"
        } else if rssi > -70 {
            return "wifi"
        } else {
            return "wifi"
        }
    }

    private func signalText(for rssi: Int) -> String {
        if rssi > -50 {
            return "Excellent signal"
        } else if rssi > -70 {
            return "Good signal"
        } else {
            return "Weak signal"
        }
    }
}

// MARK: - Instruction Row

struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.nookAccent)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
    }
}

#Preview {
    BluetoothPairingView()
        .environmentObject(ConnectionViewModel())
}
