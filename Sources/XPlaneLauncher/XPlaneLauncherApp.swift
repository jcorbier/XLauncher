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
    @State private var authManager: NavigraphAuthManager
    @State private var navdataManager: NavdataManager
    @State private var showWelcomeScreen = false
    init() {
        let auth = NavigraphAuthManager()
        self._authManager = State(initialValue: auth)
        self._navdataManager = State(initialValue: NavdataManager(authManager: auth))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showWelcomeScreen: $showWelcomeScreen)
                .environment(pluginManager)
                .environment(updateManager)
                .environment(cslManager)
                .environment(appUpdateManager)
                .environment(authManager)
                .environment(navdataManager)
                .frame(minWidth: 600, minHeight: 500)
                .onAppear {
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
                }
                .onChange(of: pluginManager.launcherDataFolder) { _, newValue in
                    updateManager.launcherDataFolder = newValue
                    cslManager.launcherDataFolder = newValue
                    if pluginManager.enableNavdataSupport {
                        navdataManager.launcherDataFolder = newValue
                    }
                }
                .onChange(of: pluginManager.xPlanePath) { _, newValue in
                    cslManager.xPlaneFolderURL = newValue
                    if pluginManager.enableNavdataSupport {
                        navdataManager.xPlaneURL = newValue
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
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar) // Modern look
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Install Add-on...") {
                    NotificationCenter.default.post(name: .installAddonRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
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

        Window("Logs", id: "logs-window") {
            LogsDialogView()
        }
        .keyboardShortcut("l", modifiers: [.command, .option])
        .defaultSize(width: 800, height: 500)
        .windowResizability(.contentMinSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
}
