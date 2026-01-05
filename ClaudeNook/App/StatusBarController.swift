//
//  StatusBarController.swift
//  ClaudeNook
//
//  Menu bar icon providing fallback access to key features.
//

import AppKit
import Combine

@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem?
    private var pairingCodeItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupStatusItem()
        observePairingCode()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Use SF Symbol for the menu bar icon
            if let image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "Claude Nook") {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "Claude Nook"
        }

        statusItem?.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        // Pairing code section
        let pairingHeader = NSMenuItem(title: "iOS Pairing", action: nil, keyEquivalent: "")
        pairingHeader.isEnabled = false
        menu.addItem(pairingHeader)

        pairingCodeItem = NSMenuItem(title: "Show Pairing Code", action: #selector(showPairingCode), keyEquivalent: "p")
        pairingCodeItem?.target = self
        menu.addItem(pairingCodeItem!)

        menu.addItem(NSMenuItem.separator())

        // Open notch
        let openNotchItem = NSMenuItem(title: "Open Notch Panel", action: #selector(openNotchPanel), keyEquivalent: "o")
        openNotchItem.target = self
        menu.addItem(openNotchItem)

        menu.addItem(NSMenuItem.separator())

        // Copy token
        let copyTokenItem = NSMenuItem(title: "Copy Auth Token", action: #selector(copyAuthToken), keyEquivalent: "c")
        copyTokenItem.target = self
        menu.addItem(copyTokenItem)

        menu.addItem(NSMenuItem.separator())

        // Check for updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Claude Nook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    private func observePairingCode() {
        PairingCodeManager.shared.$currentCode
            .combineLatest(PairingCodeManager.shared.$expiresAt)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] code, expiresAt in
                self?.updatePairingMenuItem(code: code, expiresAt: expiresAt)
            }
            .store(in: &cancellables)
    }

    private func updatePairingMenuItem(code: String?, expiresAt: Date?) {
        guard let item = pairingCodeItem else { return }

        if let code = code, let expires = expiresAt, Date() < expires {
            // Show the code with remaining time
            let remaining = Int(expires.timeIntervalSinceNow)
            item.title = "Code: \(code) (\(remaining)s)"
        } else {
            item.title = "Show Pairing Code"
        }
    }

    @objc private func showPairingCode() {
        _ = PairingCodeManager.shared.generateCode()

        // Open the notch panel to show the code in the menu view
        openNotchPanel()
    }

    @objc private func openNotchPanel() {
        if let viewModel = AppDelegate.shared?.windowController?.viewModel {
            viewModel.notchOpen(reason: .click)
            // Switch to menu view to show pairing options
            viewModel.contentType = .menu
        }
    }

    @objc private func copyAuthToken() {
        let token = NetworkSettings.shared.currentToken
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)

        // Show brief feedback
        if let button = statusItem?.button {
            let originalImage = button.image
            if let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied") {
                checkImage.isTemplate = true
                button.image = checkImage

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    button.image = originalImage
                }
            }
        }
    }

    @objc private func checkForUpdates() {
        if let url = URL(string: "https://github.com/Jmi2020/claude-nook/releases") {
            NSWorkspace.shared.open(url)
        }
    }
}
