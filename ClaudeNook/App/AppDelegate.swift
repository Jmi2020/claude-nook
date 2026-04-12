import AppKit
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: WindowManager?
    private var screenObserver: ScreenObserver?
    private var updateCheckTimer: Timer?
    private var statusBarController: StatusBarController?
    private var aiSettingsObserver: NSObjectProtocol?

    static var shared: AppDelegate?
    let updater: SPUUpdater
    private let userDriver: NotchUserDriver

    var windowController: NotchWindowController? {
        windowManager?.windowController
    }

    override init() {
        userDriver = NotchUserDriver()
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: nil
        )
        super.init()
        AppDelegate.shared = self

        do {
            try updater.start()
        } catch {
            print("Failed to start Sparkle updater: \(error)")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ensureSingleInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        HookInstaller.installIfNeeded()
        NSApplication.shared.setActivationPolicy(.accessory)

        windowManager = WindowManager()
        _ = windowManager?.setupNotchWindow()

        statusBarController = StatusBarController()

        screenObserver = ScreenObserver { [weak self] in
            self?.handleScreenChange()
        }

        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        }

        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let updater = self?.updater, updater.canCheckForUpdates else { return }
            updater.checkForUpdates()
        }

        // Start AI classification if enabled
        startClassifierIfNeeded()

        // Listen for AI settings changes
        aiSettingsObserver = NotificationCenter.default.addObserver(
            forName: .aiSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startClassifierIfNeeded()
        }
    }

    private func handleScreenChange() {
        _ = windowManager?.setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateCheckTimer?.invalidate()
        screenObserver = nil
        if let observer = aiSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        Task { await SessionClassifier.shared.stop() }
    }

    private func startClassifierIfNeeded() {
        Task {
            if AppSettings.aiClassificationEnabled {
                let backendType = AIBackendType(rawValue: AppSettings.aiBackendType) ?? .ollama
                let model = AppSettings.aiModelName
                let backend: any LLMBackend = switch backendType {
                case .ollama:
                    OllamaBackend(model: model)
                case .lmstudio:
                    LMStudioBackend(model: model)
                }
                await SessionClassifier.shared.start(
                    backend: backend,
                    intervalSeconds: UInt64(AppSettings.aiClassificationInterval)
                )
            } else {
                await SessionClassifier.shared.stop()
            }
        }
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jmi2020.claudenook"
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }

        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != getpid() }) {
                existingApp.activate()
            }
            return false
        }

        return true
    }
}
