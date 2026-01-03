//
//  SessionListView.swift
//  ClaudeNookiOS
//
//  Grid view of active Claude sessions.
//

import ClaudeNookShared
import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @EnvironmentObject var sessionStore: iOSSessionStore

    @State private var showSettings = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nookBackground
                    .ignoresSafeArea()

                ScrollView {
                    if sessionStore.sessions.isEmpty {
                        EmptySessionsView()
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(sessionStore.sessions) { session in
                                NavigationLink(value: session) {
                                    SessionCard(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Sessions")
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
                            .foregroundStyle(.nookAccent)
                    }
                }
            }
            .toolbarBackground(Color.nookBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
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
}

struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.nookAccent.opacity(0.5))

            Text("No Active Sessions")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Start a Claude Code session on your Mac to see it here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}

struct ConnectionStatusIndicator: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionVM.isConnected ? .green : .red)
                .frame(width: 8, height: 8)

            Text(connectionVM.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(.secondary)
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

                Form {
                    Section {
                        if let host = connectionVM.connectedHost {
                            LabeledContent("Connected To", value: host)
                        }

                        Button(role: .destructive) {
                            connectionVM.disconnect()
                            dismiss()
                        } label: {
                            Text("Disconnect")
                        }
                    } header: {
                        Text("Connection")
                    }

                    Section {
                        LabeledContent("Version", value: "1.0.0")
                    } header: {
                        Text("About")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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

#Preview {
    SessionListView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(iOSSessionStore())
}
