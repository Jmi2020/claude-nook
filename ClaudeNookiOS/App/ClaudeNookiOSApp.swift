//
//  ClaudeNookiOSApp.swift
//  ClaudeNookiOS
//
//  iOS companion app for Claude Nook.
//  View and approve Claude Code session permissions remotely.
//

import ClaudeNookShared
import SwiftUI

@main
struct ClaudeNookiOSApp: App {
    @StateObject private var connectionVM = ConnectionViewModel()
    @StateObject private var sessionStore = iOSSessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionVM)
                .environmentObject(sessionStore)
                .task {
                    // Connect the session store to the view model
                    connectionVM.setSessionStore(sessionStore)
                }
        }
    }
}
