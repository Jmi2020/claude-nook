//
//  ContentView.swift
//  ClaudeNookiOS
//
//  Root navigation view for the iOS app.
//

import ClaudeNookShared
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectionVM: ConnectionViewModel
    @EnvironmentObject var sessionStore: iOSSessionStore

    var body: some View {
        Group {
            if connectionVM.isConnected {
                SessionListView()
            } else {
                ConnectionView()
            }
        }
        .animation(.easeInOut, value: connectionVM.isConnected)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(iOSSessionStore())
}
