//
//  BackgroundTaskManager.swift
//  ClaudeNookiOS
//
//  Manages BGAppRefreshTask for periodic reconnection when backgrounded.
//

import BackgroundTasks
import Foundation
import os.log

private let logger = Logger(subsystem: "com.jmi2020.claudenook-ios", category: "BackgroundTask")

class BackgroundTaskManager {
    static let reconnectTaskId = "com.jmi2020.claudenook-ios.reconnect"

    weak var connectionVM: ConnectionViewModel?

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.reconnectTaskId,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            self?.handleReconnectTask(task)
        }
        logger.info("Registered background tasks")
    }

    func scheduleReconnect() {
        let request = BGAppRefreshTaskRequest(identifier: Self.reconnectTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background reconnect")
        } catch {
            logger.error("Failed to schedule background task: \(error)")
        }
    }

    private func handleReconnectTask(_ task: BGAppRefreshTask) {
        logger.info("Background reconnect task started")

        // Schedule the next one immediately
        scheduleReconnect()

        task.expirationHandler = {
            logger.info("Background task expired")
            task.setTaskCompleted(success: false)
        }

        // Attempt reconnection on the main actor
        Task { @MainActor [weak self] in
            guard let vm = self?.connectionVM else {
                task.setTaskCompleted(success: false)
                return
            }

            if !vm.isConnected {
                logger.info("Background: attempting reconnect")
                vm.reconnectToLastHost()

                // Give it a few seconds to connect and receive any pending messages
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }

            task.setTaskCompleted(success: true)
        }
    }
}
