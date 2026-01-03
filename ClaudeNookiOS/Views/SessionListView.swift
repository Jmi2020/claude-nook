//
//  SessionListView.swift
//  ClaudeNookiOS
//
//  List view of active Claude sessions matching macOS Nook design.
//

import ClaudeNookShared
import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @EnvironmentObject var sessionStore: iOSSessionStore

    @State private var showSettings = false
    @State private var selectedSession: SessionStateLight?

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    private var sortedSessions: [SessionStateLight] {
        sessionStore.sessions.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last activity (more recent first)
            return a.lastActivity > b.lastActivity
        }
    }

    /// Lower number = higher priority
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                ScrollView {
                    if sessionStore.sessions.isEmpty {
                        EmptySessionsView()
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(sortedSessions) { session in
                                SessionRow(
                                    session: session,
                                    onChat: { selectedSession = session },
                                    onApprove: { approveSession(session) },
                                    onDeny: { denySession(session) }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SessionStateLight.self) { session in
                SessionDetailView(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusIndicator()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
            .refreshable {
                await sessionStore.refresh()
            }
        }
        .sheet(item: $sessionStore.pendingPermission) { request in
            PermissionRequestView(request: request)
        }
        .preferredColorScheme(.dark)
    }

    private func approveSession(_ session: SessionStateLight) {
        guard case .waitingForApproval(let context) = session.phase else { return }
        connectionVM.approve(sessionId: session.sessionId, toolUseId: context.toolUseId)
    }

    private func denySession(_ session: SessionStateLight) {
        guard case .waitingForApproval(let context) = session.phase else { return }
        connectionVM.deny(sessionId: session.sessionId, toolUseId: context.toolUseId, reason: nil)
    }
}

struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.2))

            Text("No sessions")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Run claude in terminal")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}

struct ConnectionStatusIndicator: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionVM.isConnected ? TerminalColors.green : TerminalColors.red)
                .frame(width: 8, height: 8)

            Text(connectionVM.isConnected ? "Connected" : "Disconnected")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // Connection info
                    if let host = connectionVM.connectedHost {
                        VStack(spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(TerminalColors.green)
                                    .frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            Text(host)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.nookSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Disconnect button
                    Button {
                        connectionVM.disconnect()
                        dismiss()
                    } label: {
                        Text("Disconnect")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(TerminalColors.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(TerminalColors.red.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Version
                    Text("Claude Nook iOS v1.0.0")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SessionListView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(iOSSessionStore())
}
