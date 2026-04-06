//
//  SetupView.swift
//  ClaudeNookWatch
//
//  Manual host/port/token entry for Watch.
//

import SwiftUI

struct SetupView: View {
    @Binding var host: String
    @Binding var port: String
    @Binding var token: String
    let onConnect: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(WatchColors.orange)

                Text("Claude Nook")
                    .font(.headline)

                TextField("Host IP", text: $host)
                    .textContentType(.URL)

                TextField("Port", text: $port)

                SecureField("Token", text: $token)

                Button("Connect") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchColors.orange)
                .disabled(host.isEmpty)

                Text("Enter your Mac's Tailscale IP and port 4851")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Setup")
    }
}
