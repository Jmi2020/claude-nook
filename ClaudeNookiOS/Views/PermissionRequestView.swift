//
//  PermissionRequestView.swift
//  ClaudeNookiOS
//
//  UI for approving or denying tool permission requests.
//

import ClaudeNookShared
import SwiftUI

struct PermissionRequestView: View {
    let request: PermissionRequest

    @EnvironmentObject var sessionStore: iOSSessionStore
    @Environment(\.dismiss) var dismiss

    @State private var denyReason = ""
    @State private var showDenyReason = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tool Info
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Tool Header
                            HStack {
                                Image(systemName: toolIcon)
                                    .font(.title)
                                    .foregroundStyle(.nookAccent)

                                VStack(alignment: .leading) {
                                    Text(request.toolName)
                                        .font(.title2.bold())
                                        .foregroundStyle(.white)

                                    Text("Session: \(request.sessionId.prefix(8))...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.nookSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Tool Input
                            if let toolInput = request.toolInput, !toolInput.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Input")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(formatInput(toolInput))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.nookSurfaceSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding()
                    }

                    Divider()
                        .overlay(Color.nookSurface)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            approve()
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NookApprovalButtonStyle(isApprove: true))

                        Button {
                            showDenyReason = true
                        } label: {
                            Label("Deny", systemImage: "xmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NookApprovalButtonStyle(isApprove: false))
                    }
                    .padding()
                }
            }
            .navigationTitle("Permission Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Deny Request", isPresented: $showDenyReason) {
                TextField("Reason (optional)", text: $denyReason)

                Button("Deny", role: .destructive) {
                    deny()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Optionally provide a reason for denying this request.")
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    private var toolIcon: String {
        switch request.toolName.lowercased() {
        case "bash": return "terminal.fill"
        case "read": return "doc.text.fill"
        case "write": return "pencil.circle.fill"
        case "edit": return "pencil.line"
        case "glob": return "folder.badge.gearshape"
        case "grep": return "magnifyingglass"
        case "task": return "person.2.fill"
        case "webfetch": return "globe"
        case "websearch": return "magnifyingglass.circle.fill"
        default: return "wrench.and.screwdriver.fill"
        }
    }

    private func formatInput(_ input: String) -> String {
        // Try to pretty-print JSON
        if let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return input
    }

    private func approve() {
        Task {
            await sessionStore.approve(request: request)
            dismiss()
        }
    }

    private func deny() {
        Task {
            await sessionStore.deny(request: request, reason: denyReason.isEmpty ? nil : denyReason)
            dismiss()
        }
    }
}

#Preview {
    PermissionRequestView(request: PermissionRequest(
        sessionId: "test-123",
        toolUseId: "tool-456",
        toolName: "Bash",
        toolInput: "{\"command\": \"npm install\"}",
        projectName: "my-project",
        receivedAt: Date()
    ))
    .environmentObject(iOSSessionStore())
}
