//
//  ConnectionView.swift
//  ClaudeNookiOS
//
//  Setup and connection UI for pairing with Mac.
//

import ClaudeNookShared
import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @State private var showManualEntry = false
    @State private var showQRScanner = false
    @State private var showBluetoothPairing = false
    @State private var selectedHost: DiscoveredHost?

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                Color.nookBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // App Icon/Logo
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 60))
                        .foregroundStyle(.nookAccent)
                        .padding(.top, 40)

                    Text("Claude Nook")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("Connect to your Mac to view and approve Claude Code permissions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer()

                    // Discovered Macs
                    if !connectionVM.discoveredHosts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Available Macs")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal)

                            ForEach(connectionVM.discoveredHosts) { host in
                                DiscoveredHostRow(host: host) {
                                    selectedHost = host
                                }
                            }
                        }
                    } else if connectionVM.isScanning {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.nookAccent)
                            Text("Searching for Macs...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No Macs found on this network")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Actions
                    VStack(spacing: 12) {
                        // Primary actions row
                        HStack(spacing: 12) {
                            // QR Code scan button
                            Button {
                                showQRScanner = true
                            } label: {
                                Label("QR Code", systemImage: "qrcode.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NookButtonStyle(isPrimary: true))

                            // Bluetooth pairing button
                            Button {
                                showBluetoothPairing = true
                            } label: {
                                Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NookButtonStyle(isPrimary: true))
                        }

                        // Secondary actions row
                        HStack(spacing: 12) {
                            Button {
                                connectionVM.startDiscovery()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NookButtonStyle(isPrimary: false))
                            .disabled(connectionVM.isScanning)

                            Button {
                                showManualEntry = true
                            } label: {
                                Label("Manual", systemImage: "keyboard")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NookButtonStyle(isPrimary: false))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedHost) { host in
                PairingMethodSheet(host: host)
            }
            .sheet(isPresented: $showManualEntry) {
                ManualConnectionSheet()
            }
            .sheet(isPresented: $showBluetoothPairing) {
                BluetoothPairingView()
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                QRScannerView()
            }
            .alert("Connection Error", isPresented: $connectionVM.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(connectionVM.errorMessage)
            }
            .onAppear {
                connectionVM.startDiscovery()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct DiscoveredHostRow: View {
    let host: DiscoveredHost
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(.nookAccent)

                VStack(alignment: .leading) {
                    Text(host.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(host.address)
                        .font(.caption)
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
        .padding(.horizontal)
    }
}

/// Sheet showing pairing method options when a host is selected
struct PairingMethodSheet: View {
    let host: DiscoveredHost

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var connectionVM: ConnectionViewModel

    @State private var selectedMethod: PairingMethod?

    enum PairingMethod: Identifiable {
        case code
        case token
        case bluetooth

        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Host info
                    VStack(spacing: 8) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 50))
                            .foregroundStyle(.nookAccent)

                        Text(host.name)
                            .font(.title2.bold())
                            .foregroundStyle(.white)

                        Text(host.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 30)

                    Text("How would you like to connect?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Pairing method options
                    VStack(spacing: 16) {
                        PairingMethodButton(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "Bluetooth Pairing",
                            subtitle: "Automatically pair when nearby (easiest)"
                        ) {
                            selectedMethod = .bluetooth
                        }

                        PairingMethodButton(
                            icon: "number.circle.fill",
                            title: "Enter Pairing Code",
                            subtitle: "Type the 6-digit code shown on your Mac"
                        ) {
                            selectedMethod = .code
                        }

                        PairingMethodButton(
                            icon: "key.fill",
                            title: "Enter Token Manually",
                            subtitle: "Paste the 64-character authentication token"
                        ) {
                            selectedMethod = .token
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Connect to Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.nookAccent)
                }
            }
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $selectedMethod) { method in
                switch method {
                case .code:
                    PairingCodeView(host: host)
                case .token:
                    TokenEntrySheet(host: host)
                case .bluetooth:
                    BluetoothPairingView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct PairingMethodButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(.nookAccent)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
}

/// Sheet for entering token when connecting to a discovered host
struct TokenEntrySheet: View {
    let host: DiscoveredHost
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @Environment(\.dismiss) var dismiss

    @State private var token = ""
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Host info
                    VStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.nookAccent)

                        Text("Enter Token")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 30)

                    // Token entry
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Authentication Token")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        SecureField("Paste 64-character token", text: $token)
                            .textFieldStyle(NookTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Text("Copy the token from Claude Nook on your Mac:\nSettings → Remote Access → Copy Token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Connect button
                    Button {
                        isConnecting = true
                        connectionVM.connectManually(
                            host: host.address,
                            port: host.port,
                            token: token.isEmpty ? nil : token
                        )
                        dismiss()
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(NookButtonStyle(isPrimary: true))
                    .disabled(token.isEmpty || isConnecting)
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Manual Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.nookAccent)
                }
            }
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

struct ManualConnectionSheet: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @Environment(\.dismiss) var dismiss

    @State private var host = ""
    @State private var port = "4851"
    @State private var token = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                Form {
                    Section {
                        TextField("IP Address or Hostname", text: $host)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Connection")
                    }

                    Section {
                        SecureField("Authentication Token", text: $token)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Authentication")
                    } footer: {
                        Text("64-character token from Claude Nook on your Mac")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Manual Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.nookAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        connectionVM.connectManually(
                            host: host,
                            port: Int(port) ?? 4851,
                            token: token.isEmpty ? nil : token
                        )
                        dismiss()
                    }
                    .disabled(host.isEmpty || token.isEmpty)
                    .foregroundColor(host.isEmpty || token.isEmpty ? .secondary : Color.nookAccent)
                }
            }
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ConnectionView()
        .environmentObject(ConnectionViewModel())
}
