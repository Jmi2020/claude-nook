//
//  ContentView.swift
//  ClaudeNookWatch
//
//  Root view: routes between setup and session list.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionStore: WatchSessionStore
    @Binding var isConnected: Bool
    @Binding var isConfigured: Bool

    // Setup fields
    @Binding var host: String
    @Binding var port: String
    @Binding var token: String
    let onConnect: () -> Void

    var body: some View {
        NavigationStack {
            if isConfigured {
                SessionListView(isConnected: $isConnected)
            } else {
                SetupView(
                    host: $host,
                    port: $port,
                    token: $token,
                    onConnect: onConnect
                )
            }
        }
    }
}
