//
//  NotificationManager.swift
//  ClaudeNookiOS
//
//  Manages local notifications for permission requests.
//  Fires actionable notifications when the app is backgrounded.
//

import ClaudeNookShared
import Foundation
import os.log
import UserNotifications

private let logger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "Notifications")

@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // MARK: - Category & Action Identifiers

    static let permissionCategory = "PERMISSION_REQUEST"
    static let approveAction = "APPROVE_ACTION"
    static let denyAction = "DENY_ACTION"

    // MARK: - State

    @Published private(set) var isAuthorized = false
    var isInForeground = true

    /// Weak references for dispatching approve/deny from notification actions
    weak var sessionStore: iOSSessionStore?
    weak var connectionVM: ConnectionViewModel?

    // MARK: - Setup

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isAuthorized = granted
            logger.info("Notification authorization: \(granted)")
        } catch {
            logger.error("Failed to request notification authorization: \(error)")
        }
    }

    func registerCategories() {
        let approveAction = UNNotificationAction(
            identifier: Self.approveAction,
            title: "Approve",
            options: [.authenticationRequired]
        )

        let denyAction = UNNotificationAction(
            identifier: Self.denyAction,
            title: "Deny",
            options: [.destructive, .authenticationRequired]
        )

        let permissionCategory = UNNotificationCategory(
            identifier: Self.permissionCategory,
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([permissionCategory])
        logger.info("Registered notification categories")
    }

    // MARK: - Post Notifications

    func schedulePermissionNotification(for request: PermissionRequest) {
        guard isAuthorized else {
            logger.debug("Notifications not authorized, skipping")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Permission Needed"
        content.subtitle = request.projectName
        content.body = "\(request.toolName) wants to run"
        if let input = request.toolInput, !input.isEmpty {
            content.body += ": \(String(input.prefix(100)))"
        }
        content.sound = .default
        content.categoryIdentifier = Self.permissionCategory
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "sessionId": request.sessionId,
            "toolUseId": request.toolUseId,
            "toolName": request.toolName,
            "projectName": request.projectName
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: "permission-\(request.toolUseId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(notificationRequest) { error in
            if let error = error {
                logger.error("Failed to schedule notification: \(error)")
            } else {
                logger.info("Scheduled permission notification for \(request.toolName)")
            }
        }
    }

    func removePermissionNotification(toolUseId: String) {
        let identifier = "permission-\(toolUseId)"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when notification arrives while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + sound even in foreground (permission requests are important)
        completionHandler([.banner, .sound])
    }

    /// Called when user interacts with a notification (tap or action button)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let sessionId = userInfo["sessionId"] as? String,
              let toolUseId = userInfo["toolUseId"] as? String else {
            completionHandler()
            return
        }

        Task { @MainActor in
            switch response.actionIdentifier {
            case Self.approveAction:
                logger.info("Approved via notification: \(toolUseId.prefix(12))")
                connectionVM?.approve(sessionId: sessionId, toolUseId: toolUseId)

            case Self.denyAction:
                logger.info("Denied via notification: \(toolUseId.prefix(12))")
                connectionVM?.deny(sessionId: sessionId, toolUseId: toolUseId, reason: nil)

            case UNNotificationDefaultActionIdentifier:
                // User tapped the notification body — the pending permission in
                // sessionStore will trigger the PermissionRequestView sheet
                logger.info("Notification tapped for \(toolUseId.prefix(12))")

            default:
                break
            }
        }

        completionHandler()
    }
}
