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

import SwiftUI

@main
struct XPlaneLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var pluginManager = PluginManager()
    @State private var updateManager = UpdateManager()
    @State private var cslManager = CSLManager()
    @State private var appUpdateManager = AppUpdateManager()
    @State private var licenseManager = LicenseManager.shared
    @State private var appPluginRegistry = AppPluginRegistry.shared
    @State private var authManager: NavigraphAuthManager
    @State private var navdataManager: NavdataManager
    @State private var simSessionManager = SimSessionManager.shared
    @State private var showWelcomeScreen = false
    init() {
        let auth = NavigraphAuthManager()
        self._authManager = State(initialValue: auth)
        self._navdataManager = State(initialValue: NavdataManager(authManager: auth))
    }

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView(showWelcomeScreen: $showWelcomeScreen)
                .environment(pluginManager)
                .environment(updateManager)
                .environment(cslManager)
                .environment(appUpdateManager)
                .environment(authManager)
                .environment(navdataManager)
                .environment(simSessionManager)
                .environment(licenseManager)
                .environment(appPluginRegistry)
                .frame(minWidth: 600, minHeight: 500)
                .background(WindowAccessor { window in
                    window.delegate = NSApp.delegate as? NSWindowDelegate
                })
                .onReceive(NotificationCenter.default.publisher(for: .restoreMainWindowRequested)) { _ in
                    NSApp.setActivationPolicy(.regular)
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    var restored = false
                    for window in NSApp.windows where !(window is NSPanel) && !String(describing: type(of: window)).contains("StatusBar") {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                        restored = true
                    }
                    if !restored {
                        openWindow(id: "main-window")
                    }
                }
                .onAppear {
                    MenuBarCompanionManager.shared.xPlanePath = pluginManager.xPlanePath
                    licenseManager.initialize()
                    updateManager.launcherDataFolder = pluginManager.launcherDataFolder
                    cslManager.cslFolderURL = pluginManager.cslPath
                    cslManager.xPlaneFolderURL = pluginManager.xPlanePath
                    cslManager.launcherDataFolder = pluginManager.launcherDataFolder
                    if pluginManager.enableNavdataSupport {
                        navdataManager.xPlaneURL = pluginManager.xPlanePath
                        navdataManager.launcherDataFolder = pluginManager.launcherDataFolder
                        Task {
                            await authManager.restoreSessionOnLaunch()
                            if case .authenticated = authManager.authState, navdataManager.automaticallyCheckNavdataUpdates {
                                await navdataManager.checkOnlinePackages()
                            }
                        }
                    }
                    if pluginManager.enableCSLSupport && cslManager.automaticallyCheckCSLUpdates {
                        cslManager.scanAndCheck()
                    }
                    if !pluginManager.hasCompletedWelcome && !pluginManager.isConfigured {
                        showWelcomeScreen = true
                    }
                    if appUpdateManager.automaticallyCheckOnLaunch {
                        appUpdateManager.checkForUpdates(manual: false)
                    }
                    Task {
                        let activeAircraft = pluginManager.aircraft.filter { $0.isEnabled }.map { $0.folderName }
                        await appPluginRegistry.discoverAndLoadPlugins(xPlaneURL: pluginManager.xPlanePath, activatedAircraftNames: activeAircraft)
                        await appPluginRegistry.reloadLicenses()
                    }
                }
                .onChange(of: pluginManager.storagePools) { _, newPools in
                    updateManager.storagePools = newPools
                }
                .onChange(of: pluginManager.launcherDataFolder) { _, newValue in
                    cslManager.launcherDataFolder = newValue
                    if pluginManager.enableNavdataSupport {
                        navdataManager.launcherDataFolder = newValue
                    }
                }
                .onChange(of: pluginManager.xPlanePath) { _, newValue in
                    cslManager.xPlaneFolderURL = newValue
                    MenuBarCompanionManager.shared.xPlanePath = newValue
                    if pluginManager.enableNavdataSupport {
                        navdataManager.xPlaneURL = newValue
                    }
                    Task {
                        let activeAircraft = pluginManager.aircraft.filter { $0.isEnabled }.map { $0.folderName }
                        await appPluginRegistry.discoverAndLoadPlugins(xPlaneURL: newValue, activatedAircraftNames: activeAircraft)
                        await appPluginRegistry.reloadLicenses()
                    }
                }
                .onChange(of: pluginManager.cslPath) { _, newValue in
                    cslManager.cslFolderURL = newValue
                    cslManager.xPlaneFolderURL = pluginManager.xPlanePath
                    if pluginManager.enableCSLSupport && cslManager.automaticallyCheckCSLUpdates {
                        cslManager.scanAndCheck()
                    }
                }
                .onChange(of: pluginManager.enableCSLSupport) { _, enabled in
                    if enabled {
                        cslManager.cslFolderURL = pluginManager.cslPath
                        cslManager.xPlaneFolderURL = pluginManager.xPlanePath
                        if cslManager.automaticallyCheckCSLUpdates {
                            cslManager.scanAndCheck()
                        }
                    }
                }
                .onChange(of: pluginManager.enableCSLXP12Lights) { _, enabled in
                    if enabled {
                        cslManager.applyXP12LightsToAll()
                    } else {
                        cslManager.revertXP12LightsFromAll()
                    }
                }
                .onChange(of: pluginManager.enableNavdataSupport) { _, enabled in
                    if enabled {
                        navdataManager.xPlaneURL = pluginManager.xPlanePath
                        Task {
                            await authManager.restoreSessionOnLaunch()
                            if case .authenticated = authManager.authState, navdataManager.automaticallyCheckNavdataUpdates {
                                await navdataManager.checkOnlinePackages()
                            }
                        }
                    }
                }
                .onChange(of: pluginManager.aircraft) { _, _ in
                    Task {
                        let activeAircraft = pluginManager.aircraft.filter { $0.isEnabled }.map { $0.folderName }
                        await appPluginRegistry.discoverAndLoadPlugins(xPlaneURL: pluginManager.xPlanePath, activatedAircraftNames: activeAircraft)
                    }
                }
                .onChange(of: licenseManager.isPro) { _, _ in
                    Task {
                        await appPluginRegistry.reloadLicenses()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .proLicenseStateChanged)) { _ in
                    Task {
                        await appPluginRegistry.reloadLicenses()
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar) // Modern look
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install Add-on...") {
                    NotificationCenter.default.post(name: .installAddonRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Manage Profiles...") {
                    openWindow(id: "profiles-window")
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("X-Plane Logs...") {
                    openWindow(id: "xplane-logs-window")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .printItem) { }
            CommandGroup(replacing: .importExport) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appUpdateManager.checkForUpdates(manual: true)
                }
                Divider()
                Button("Welcome to X-Plane Launcher...") {
                    showWelcomeScreen = true
                }
            }
            CommandGroup(replacing: .help) {
                Button("Show Welcome Screen...") {
                    showWelcomeScreen = true
                }
                Divider()
                Button("X-Plane Launcher Documentation") {
                    NSWorkspace.shared.open(AppInfo.documentationURL)
                }
            }
        }

        Window("Profile Manager", id: "profiles-window") {
            ProfileManagerView()
                .environment(pluginManager)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)

        Window("Logs", id: "logs-window") {
            LogsDialogView()
        }
        .keyboardShortcut("l", modifiers: [.command, .option])
        .defaultSize(width: 800, height: 500)
        .windowResizability(.contentMinSize)

        Window("X-Plane Logs", id: "xplane-logs-window") {
            XPlaneLogsView()
                .environment(pluginManager)
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Window Accessor
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if SimSessionManager.shared.isSimRunning {
            MenuBarCompanionManager.shared.hideMainWindow()
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if SimSessionManager.shared.isSimRunning {
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MenuBarCompanionManager.shared.restoreMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
}
