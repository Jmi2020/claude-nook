//
//  PairingCodeView.swift
//  ClaudeNookiOS
//
//  Enter a 6-digit pairing code shown on the Mac.
//

import SwiftUI

struct PairingCodeView: View {
    let host: DiscoveredHost

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var connectionVM: ConnectionViewModel

    @State private var code = ""
    @State private var isVerifying = false
    @State private var showError = false
    @State private var errorMessage = ""

    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                VStack(spacing: 32) {
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

                    // Instructions
                    Text("Enter the 6-digit code shown\non Claude Nook")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // Code entry
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            CodeDigitBox(
                                digit: digit(at: index),
                                isActive: code.count == index
                            )
                        }
                    }
                    .onTapGesture {
                        isCodeFieldFocused = true
                    }

                    // Hidden text field for keyboard input
                    TextField("", text: $code)
                        .keyboardType(.numberPad)
                        .focused($isCodeFieldFocused)
                        .opacity(0)
                        .frame(height: 1)
                        .onChange(of: code) { newValue in
                            // Limit to 6 digits
                            if newValue.count > 6 {
                                code = String(newValue.prefix(6))
                            }
                            // Filter non-digits
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                code = filtered
                            }

                            // Auto-submit when 6 digits entered
                            if code.count == 6 {
                                verifyCode()
                            }
                        }

                    Spacer()

                    // Manual submit button
                    Button {
                        verifyCode()
                    } label: {
                        if isVerifying {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(NookButtonStyle(isPrimary: true))
                    .disabled(code.count != 6 || isVerifying)
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Enter Code")
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
            .onAppear {
                isCodeFieldFocused = true
            }
            .alert("Connection Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    code = ""
                    isCodeFieldFocused = true
                }
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func digit(at index: Int) -> String? {
        guard index < code.count else { return nil }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }

    private func verifyCode() {
        guard code.count == 6, !isVerifying else { return }

        isVerifying = true
        isCodeFieldFocused = false

        // Connect to the host and send PAIR command
        Task {
            do {
                let token = try await requestTokenWithPairingCode(
                    host: host.address,
                    port: host.port,
                    code: code
                )

                // Successfully got token, now connect with it
                await MainActor.run {
                    connectionVM.connectManually(host: host.address, port: host.port, token: token)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    /// Request the full token using the 6-digit pairing code
    private func requestTokenWithPairingCode(host: String, port: Int, code: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "pairing")

            queue.async {
                do {
                    // Create socket connection
                    var hints = addrinfo()
                    hints.ai_family = AF_UNSPEC
                    hints.ai_socktype = SOCK_STREAM

                    var result: UnsafeMutablePointer<addrinfo>?
                    let status = getaddrinfo(host, String(port), &hints, &result)

                    guard status == 0, let addrInfo = result else {
                        throw PairingError.connectionFailed("Could not resolve host")
                    }

                    defer { freeaddrinfo(result) }

                    let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
                    guard sock >= 0 else {
                        throw PairingError.connectionFailed("Could not create socket")
                    }

                    defer { close(sock) }

                    // Set timeout
                    var timeout = timeval(tv_sec: 10, tv_usec: 0)
                    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                    // Connect
                    guard Darwin.connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen) == 0 else {
                        throw PairingError.connectionFailed("Could not connect to server")
                    }

                    // Send PAIR command
                    let pairCommand = "PAIR \(code)\n"
                    _ = pairCommand.withCString { ptr in
                        send(sock, ptr, strlen(ptr), 0)
                    }

                    // Read response
                    var buffer = [CChar](repeating: 0, count: 256)
                    let bytesRead = recv(sock, &buffer, buffer.count - 1, 0)

                    guard bytesRead > 0 else {
                        throw PairingError.connectionFailed("No response from server")
                    }

                    let response = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)

                    if response.hasPrefix("TOKEN ") {
                        let token = String(response.dropFirst(6))
                        continuation.resume(returning: token)
                    } else if response.hasPrefix("ERR:") {
                        let errorMsg = String(response.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                        throw PairingError.invalidCode(errorMsg)
                    } else {
                        throw PairingError.invalidResponse(response)
                    }

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum PairingError: LocalizedError {
    case connectionFailed(String)
    case invalidCode(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .invalidCode(let msg):
            return msg.isEmpty ? "Invalid pairing code" : msg
        case .invalidResponse(let response):
            return "Unexpected response: \(response)"
        }
    }
}

// MARK: - Code Digit Box

struct CodeDigitBox: View {
    let digit: String?
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.nookSurface)
                .frame(width: 48, height: 64)

            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.nookAccent : Color.clear, lineWidth: 2)
                .frame(width: 48, height: 64)

            if let digit = digit {
                Text(digit)
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    PairingCodeView(host: DiscoveredHost(
        id: "preview-host",
        name: "SilverLinings",
        address: "192.168.1.100",
        port: 4851
    ))
    .environmentObject(ConnectionViewModel())
}
