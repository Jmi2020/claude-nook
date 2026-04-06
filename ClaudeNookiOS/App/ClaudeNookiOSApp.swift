//
//  ClaudeNookiOSApp.swift
//  ClaudeNookiOS
//
//  iOS companion app for Claude Nook.
//  View and approve Claude Code session permissions remotely.
//

import ClaudeNookShared
import SwiftUI
import UserNotifications

@main
struct ClaudeNookiOSApp: App {
    @StateObject private var connectionVM = ConnectionViewModel()
    @StateObject private var sessionStore = iOSSessionStore()
    @Environment(\.scenePhase) private var scenePhase

    private let backgroundTaskManager = BackgroundTaskManager()

    init() {
        // Must set delegate before any notifications can be received
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        NotificationManager.shared.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionVM)
                .environmentObject(sessionStore)
                .task {
                    // Connect the session store to the view model
                    connectionVM.setSessionStore(sessionStore)

                    // Wire up notification manager
                    NotificationManager.shared.sessionStore = sessionStore
                    NotificationManager.shared.connectionVM = connectionVM

                    // Wire up background task manager
                    backgroundTaskManager.connectionVM = connectionVM
                    backgroundTaskManager.registerTasks()
                    backgroundTaskManager.scheduleReconnect()

                    // Request notification permission
                    await NotificationManager.shared.requestAuthorization()

                    // Try to reconnect to last saved host
                    connectionVM.reconnectToLastHost()
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        NotificationManager.shared.isInForeground = true
                        // Reconnect if needed when returning to foreground
                        if !connectionVM.isConnected {
                            connectionVM.reconnectToLastHost()
                        }
                        // Clear delivered notifications
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    case .background:
                        NotificationManager.shared.isInForeground = false
                        backgroundTaskManager.scheduleReconnect()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
