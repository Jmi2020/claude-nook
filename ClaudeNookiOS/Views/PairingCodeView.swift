//
//  PairingCodeView.swift
//  ClaudeNookiOS
//
//  Enter a 6-digit pairing code shown on the Mac.
//

import SwiftUI
import os.log

private let pairingLogger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "Pairing")

struct PairingCodeView: View {
    let host: DiscoveredHost

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var connectionVM: ConnectionViewModel

    @State private var code = ""
    @State private var previousCodeLength = 0
    @State private var isVerifying = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTokenHint = false

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

                    // Hint when user pastes a token instead of a code
                    if showTokenHint {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("That looks like a token. Go back and select \"Enter Token Manually\" instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .transition(.opacity)
                    }

                    // Hidden text field for keyboard input
                    TextField("", text: $code)
                        .keyboardType(.numberPad)
                        .focused($isCodeFieldFocused)
                        .opacity(0)
                        .frame(height: 1)
                        .onChange(of: code) { newValue in
                            // Detect if user pasted a token (long string or contains letters)
                            // This is likely a paste operation if the input jumps by more than 1 character
                            let pastedLongString = newValue.count > previousCodeLength + 1 && newValue.count > 6
                            let containsLetters = newValue.contains(where: { $0.isLetter })

                            if pastedLongString || (containsLetters && newValue.count > 6) {
                                withAnimation {
                                    showTokenHint = true
                                }
                            }

                            // Clear hint when user clears the field
                            if newValue.isEmpty {
                                withAnimation {
                                    showTokenHint = false
                                }
                            }

                            // Filter non-digits
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                code = filtered
                                previousCodeLength = filtered.count
                                return
                            }

                            // Limit to 6 digits
                            if newValue.count > 6 {
                                code = String(newValue.prefix(6))
                                previousCodeLength = 6
                                return
                            }

                            previousCodeLength = code.count

                            // Auto-submit when 6 digits entered (but not if hint is shown)
                            if code.count == 6 && !showTokenHint {
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
                // For pairing, always use localhost since we're in simulator
                // The bridge network (192.168.64.x) has connectivity issues
                let pairHost = host.address.hasPrefix("192.168.64") ? "127.0.0.1" : host.address

                pairingLogger.info("Using host \(pairHost) for pairing (original: \(host.address))")

                let token = try await requestTokenWithPairingCode(
                    host: pairHost,
                    port: host.port,
                    code: code
                )

                pairingLogger.info("Got token (len=\(token.count)), connecting with AUTH to \(pairHost):\(host.port)")

                // Successfully got token, now connect with it using the SAME host
                await MainActor.run {
                    pairingLogger.info("Calling connectManually with host=\(pairHost)")
                    connectionVM.connectManually(host: pairHost, port: host.port, token: token)
                    pairingLogger.info("connectManually called, dismissing")
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
        // Strip interface suffix if present (e.g., "192.168.64.1%bridge100" -> "192.168.64.1")
        let cleanHost = host.components(separatedBy: "%").first ?? host
        print("[Pairing] Connecting to \(cleanHost):\(port) (original: \(host))")

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "pairing")

            queue.async {
                do {
                    // Create socket connection
                    var hints = addrinfo()
                    hints.ai_family = AF_UNSPEC
                    hints.ai_socktype = SOCK_STREAM

                    var result: UnsafeMutablePointer<addrinfo>?
                    print("[Pairing] Resolving host: \(cleanHost)")
                    let status = getaddrinfo(cleanHost, String(port), &hints, &result)

                    guard status == 0, let addrInfo = result else {
                        let errorMsg = status != 0 ? String(cString: gai_strerror(status)) : "No result"
                        print("[Pairing] Failed to resolve host: \(errorMsg)")
                        throw PairingError.connectionFailed("Could not resolve host: \(errorMsg)")
                    }
                    print("[Pairing] Host resolved successfully")

                    defer { freeaddrinfo(result) }

                    let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
                    guard sock >= 0 else {
                        let err = errno
                        print("[Pairing] Failed to create socket: \(err)")
                        throw PairingError.connectionFailed("Could not create socket: errno \(err)")
                    }
                    print("[Pairing] Socket created: \(sock)")

                    defer { close(sock) }

                    // Set timeout
                    var timeout = timeval(tv_sec: 10, tv_usec: 0)
                    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                    // Connect
                    print("[Pairing] Connecting...")
                    guard Darwin.connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen) == 0 else {
                        let err = errno
                        let errStr = String(cString: strerror(err))
                        print("[Pairing] Connect failed: \(errStr) (errno \(err))")
                        throw PairingError.connectionFailed("Could not connect: \(errStr)")
                    }
                    print("[Pairing] Connected successfully")

                    // Send PAIR command
                    let pairCommand = "PAIR \(code)\n"
                    print("[Pairing] Sending: PAIR ******")
                    _ = pairCommand.withCString { ptr in
                        send(sock, ptr, strlen(ptr), 0)
                    }

                    // Read response
                    var buffer = [CChar](repeating: 0, count: 256)
                    print("[Pairing] Waiting for response...")
                    let bytesRead = recv(sock, &buffer, buffer.count - 1, 0)

                    guard bytesRead > 0 else {
                        let err = errno
                        print("[Pairing] No response, bytesRead=\(bytesRead), errno=\(err)")
                        throw PairingError.connectionFailed("No response from server")
                    }

                    let response = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[Pairing] Response: \(response.prefix(20))...")

                    if response.hasPrefix("TOKEN ") {
                        let token = String(response.dropFirst(6))
                        print("[Pairing] Got token successfully")
                        continuation.resume(returning: token)
                    } else if response.hasPrefix("ERR:") {
                        let errorMsg = String(response.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                        print("[Pairing] Server error: \(errorMsg)")
                        throw PairingError.invalidCode(errorMsg)
                    } else {
                        print("[Pairing] Unexpected response: \(response)")
                        throw PairingError.invalidResponse(response)
                    }

                } catch {
                    print("[Pairing] Error: \(error)")
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
