//
//  MIT License
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
    @State private var pluginManager = PluginManager()
    @State private var updateManager = UpdateManager()
    @State private var cslManager = CSLManager()
    @State private var showWelcomeScreen = false
    
    var body: some Scene {
        WindowGroup {
            ContentView(showWelcomeScreen: $showWelcomeScreen)
                .environment(pluginManager)
                .environment(updateManager)
                .environment(cslManager)
                .frame(minWidth: 600, minHeight: 500)
                .onAppear {
                    updateManager.launcherDataFolder = pluginManager.launcherDataFolder
                    cslManager.cslFolderURL = pluginManager.cslPath
                    if !pluginManager.hasCompletedWelcome && !pluginManager.isConfigured {
                        showWelcomeScreen = true
                    }
                }
                .onChange(of: pluginManager.launcherDataFolder) { _, newValue in
                    updateManager.launcherDataFolder = newValue
                }
                .onChange(of: pluginManager.cslPath) { _, newValue in
                    cslManager.cslFolderURL = newValue
                }
                .onChange(of: pluginManager.enableCSLSupport) { _, enabled in
                    if enabled {
                        cslManager.cslFolderURL = pluginManager.cslPath
                        cslManager.scanAndCheck()
                    }
                }
                .onChange(of: pluginManager.enableCSLXP12Lights) { _, enabled in
                    if enabled {
                        cslManager.applyXP12LightsToAll()
                    } else {
                        cslManager.revertXP12LightsFromAll()
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar) // Modern look
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .printItem) { }
            CommandGroup(replacing: .importExport) { }
            CommandGroup(after: .appInfo) {
                Button("Welcome to X-Plane Launcher...") {
                    showWelcomeScreen = true
                }
            }
            CommandGroup(replacing: .help) {
                Button("Show Welcome Screen...") {
                    showWelcomeScreen = true
                }
                Divider()
                Button("X-Plane Launcher Help") {
                    if let url = URL(string: "https://github.com/jcorbier/x-plane-launcher") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
