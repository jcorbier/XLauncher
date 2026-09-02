//
//  Copyright (c) 2026 Jeremie Corbier
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class MenuBarCompanionManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarCompanionManager()

    private var statusItem: NSStatusItem?
    private let simSessionManager = SimSessionManager.shared
    private var isCompanionActive = false

    /// Reference to the X-Plane folder URL for quick file shortcuts
    var xPlanePath: URL?

    override init() {
        super.init()
    }

    // MARK: - Companion Lifecycle

    /// Activates the Menu Bar item and optionally hides the main application window.
    func enterCompanionMode(hideWindow: Bool = true) {
        isCompanionActive = true
        setupStatusItemIfNeeded()

        if hideWindow {
            hideMainWindow()
        }
    }

    /// Exits companion mode and restores the main application window.
    func exitCompanionMode(restoreWindow: Bool = true) {
        isCompanionActive = false
        removeStatusItem()

        if restoreWindow {
            restoreMainWindow()
        }
    }

    // MARK: - Window Visibility Controls

    private func isEligibleMainWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return false }
        let className = String(describing: type(of: window))
        if className.contains("StatusBar") || className.contains("ItemWindow") || className.contains("Menu") {
            return false
        }
        return true
    }

    /// Hides the main launcher window and lowers app activation policy.
    func hideMainWindow() {
        for window in NSApp.windows where isEligibleMainWindow(window) {
            window.orderOut(nil)
        }
        // Switch to accessory app to hide from Dock
        NSApp.setActivationPolicy(.accessory)
    }

    /// Restores the main launcher window and brings app to foreground.
    func restoreMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where isEligibleMainWindow(window) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }

        // Post notification for SwiftUI scene to unhide / open window if needed
        NotificationCenter.default.post(name: .restoreMainWindowRequested, object: nil)
    }

    // MARK: - Status Item Setup

    private func setupStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "airplane.circle.fill", accessibilityDescription: "X-Plane Launcher")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "X-Plane Flight Companion"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - NSMenuDelegate (Dynamic Menu Construction)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Session Status Header
        let statusTitle = simSessionManager.isSimRunning
            ? "✈️ X-Plane 12: Running (\(simSessionManager.formattedFlightDuration))"
            : "✈️ X-Plane 12: Inactive"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // 2. Active Profile
        if let profile = simSessionManager.activeProfileName, !profile.isEmpty {
            let profileItem = NSMenuItem(title: "   Profile: \(profile)", action: nil, keyEquivalent: "")
            profileItem.isEnabled = false
            menu.addItem(profileItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 3. Show Window Action
        let showWindowItem = NSMenuItem(
            title: "Show X-Plane Launcher",
            action: #selector(handleShowWindow),
            keyEquivalent: "o"
        )
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Quick Shortcuts
        let logItem = NSMenuItem(
            title: "Open Log.txt",
            action: #selector(handleOpenLogFile),
            keyEquivalent: ""
        )
        logItem.target = self
        logItem.isEnabled = (xPlanePath != nil)
        menu.addItem(logItem)

        let outputFolderItem = NSMenuItem(
            title: "Open Output Folder...",
            action: #selector(handleOpenOutputFolder),
            keyEquivalent: ""
        )
        outputFolderItem.target = self
        outputFolderItem.isEnabled = (xPlanePath != nil)
        menu.addItem(outputFolderItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Force Quit / Simulator Process Management
        if simSessionManager.isSimRunning {
            let forceQuitItem = NSMenuItem(
                title: "Force Quit X-Plane",
                action: #selector(handleForceQuitSim),
                keyEquivalent: ""
            )
            forceQuitItem.target = self
            menu.addItem(forceQuitItem)

            menu.addItem(NSMenuItem.separator())
        }

        // 6. Application Termination Actions
        let quitLauncherItem = NSMenuItem(
            title: "Quit XLauncher",
            action: #selector(handleQuitLauncher),
            keyEquivalent: "q"
        )
        quitLauncherItem.target = self
        menu.addItem(quitLauncherItem)

        if simSessionManager.isSimRunning {
            let quitAllItem = NSMenuItem(
                title: "Quit All (Kill X-Plane & Launcher)",
                action: #selector(handleQuitAll),
                keyEquivalent: ""
            )
            quitAllItem.target = self
            menu.addItem(quitAllItem)
        }
    }

    // MARK: - Action Handlers

    @objc private func handleShowWindow() {
        restoreMainWindow()
    }

    @objc private func handleOpenLogFile() {
        guard let path = xPlanePath else { return }
        let logURL = path.appendingPathComponent("Log.txt")
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
        } else {
            ConsoleLogger.shared.log("Log.txt not found at \(logURL.path)", category: .launch, level: .warn)
        }
    }

    @objc private func handleOpenOutputFolder() {
        guard let path = xPlanePath else { return }
        let outputURL = path.appendingPathComponent("Output")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            NSWorkspace.shared.open(outputURL)
        } else {
            NSWorkspace.shared.open(path)
        }
    }

    @objc private func handleForceQuitSim() {
        simSessionManager.forceQuitSimulator()
    }

    @objc private func handleQuitLauncher() {
        exitCompanionMode(restoreWindow: false)
        NSApp.terminate(nil)
    }

    @objc private func handleQuitAll() {
        simSessionManager.forceQuitSimulator()
        exitCompanionMode(restoreWindow: false)
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let restoreMainWindowRequested = Notification.Name("restoreMainWindowRequested")
}
