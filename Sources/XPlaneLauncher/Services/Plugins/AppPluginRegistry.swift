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

import Foundation
import Observation
import SwiftUI
import XLauncherPluginKit

@Observable
@MainActor
public final class AppPluginRegistry {
    public static let shared = AppPluginRegistry()

    public private(set) var loadedPlugins: [any XLauncherPlugin] = []
    public private(set) var sidebarItems: [PluginSidebarItem] = []
    public private(set) var settingsPanes: [PluginSettingsPane] = []
    public private(set) var launchActionOverride: LaunchActionOverride? = nil

    public init() {
        NotificationCenter.default.addObserver(
            forName: .pluginContributionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshContributions()
            }
        }
    }

    // MARK: - Plugin Registration & Lifecycle

    /// Manually registers and activates an initialized plugin (useful for testing or built-ins).
    public func registerPlugin(_ plugin: any XLauncherPlugin, context: PluginContext? = nil) async throws {
        let descriptor = type(of: plugin).descriptor
        if let existingIndex = loadedPlugins.firstIndex(where: { type(of: $0).descriptor.id == descriptor.id }) {
            let existing = loadedPlugins[existingIndex]
            let ctx = context ?? makeDefaultContext(for: descriptor)
            try await existing.initialize(context: ctx)
            refreshContributions()
            return
        }

        let ctx = context ?? makeDefaultContext(for: descriptor)
        try await plugin.initialize(context: ctx)
        try await plugin.start()

        loadedPlugins.append(plugin)
        refreshContributions()

        ConsoleLogger.shared.log("Registered plugin \(descriptor.name) (\(descriptor.version))", category: .system)
    }

    /// Unloads all active plugins.
    public func stopAll() async {
        for plugin in loadedPlugins {
            await plugin.stop()
        }
        loadedPlugins.removeAll()
        sidebarItems.removeAll()
        settingsPanes.removeAll()
        launchActionOverride = nil
    }

    /// Re-evaluates all contributed UI elements and overrides.
    public func refreshContributions() {
        var items: [PluginSidebarItem] = []
        var panes: [PluginSettingsPane] = []
        var override: LaunchActionOverride? = nil

        for plugin in loadedPlugins {
            items.append(contentsOf: plugin.sidebarItems)
            panes.append(contentsOf: plugin.settingsPanes)
            if override == nil, let actionOverride = plugin.launchActionOverride {
                override = actionOverride
            }
        }

        var seenItemIDs: Set<String> = []
        var uniqueItems: [PluginSidebarItem] = []
        for item in items {
            if !seenItemIDs.contains(item.id) {
                seenItemIDs.insert(item.id)
                uniqueItems.append(item)
            }
        }

        var seenPaneIDs: Set<String> = []
        var uniquePanes: [PluginSettingsPane] = []
        for pane in panes {
            if !seenPaneIDs.contains(pane.id) {
                seenPaneIDs.insert(pane.id)
                uniquePanes.append(pane)
            }
        }

        self.sidebarItems = uniqueItems.sorted { $0.priority < $1.priority }
        self.settingsPanes = uniquePanes.sorted { $0.priority < $1.priority }
        self.launchActionOverride = override
    }

    /// Re-evaluates licensing across all loaded plugins and refreshes UI contributions.
    public func reloadLicenses() async {
        for plugin in loadedPlugins {
            await plugin.reloadLicenseState()
        }
        refreshContributions()
    }

    // MARK: - Dynamic Discovery & Loading

    /// Discovers and loads plugin bundles from standard locations or custom URLs.
    public func discoverAndLoadPlugins(customURLs: [URL]? = nil, xPlaneURL: URL? = nil, activatedAircraftNames: [String]? = nil) async {
        let candidateURLs = customURLs ?? resolveCandidateURLs()
        var loadedBundleIDs: Set<String> = []

        for bundleURL in candidateURLs {
            let standardizedURL = bundleURL.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardizedURL.path) else { continue }

            guard let bundle = Bundle(url: standardizedURL) else {
                ConsoleLogger.shared.log("Failed to initialize bundle at \(standardizedURL.path)", category: .system, level: .warn)
                continue
            }

            let bundleID = bundle.bundleIdentifier ?? standardizedURL.lastPathComponent
            if loadedBundleIDs.contains(bundleID) {
                continue
            }

            if !bundle.isLoaded {
                do {
                    try bundle.loadAndReturnError()
                } catch {
                    ConsoleLogger.shared.log("Failed to load plugin bundle at \(standardizedURL.path): \(error.localizedDescription)", category: .system, level: .warn)
                    continue
                }
            }

            guard let principal = bundle.principalClass as? (any XLauncherPlugin.Type) else {
                ConsoleLogger.shared.log("Principal class in \(standardizedURL.lastPathComponent) does not conform to XLauncherPlugin", category: .system, level: .warn)
                continue
            }

            let descriptor = principal.descriptor
            let ctx = makeDefaultContext(for: descriptor, xPlaneURL: xPlaneURL, activatedAircraftNames: activatedAircraftNames)

            if let existingIndex = self.loadedPlugins.firstIndex(where: { type(of: $0).descriptor.id == descriptor.id }) {
                // Plugin already loaded: update context and don't create duplicate instance!
                let existing = self.loadedPlugins[existingIndex]
                try? await existing.initialize(context: ctx)
                loadedBundleIDs.insert(bundleID)
                continue
            }

            let plugin = principal.init()

            do {
                try await plugin.initialize(context: ctx)
                try await plugin.start()
                self.loadedPlugins.append(plugin)
                loadedBundleIDs.insert(bundleID)
                ConsoleLogger.shared.log("Successfully loaded dynamic plugin \(type(of: plugin).descriptor.name) v\(type(of: plugin).descriptor.version)", category: .system)
            } catch {
                ConsoleLogger.shared.log("Plugin initialization failed for \(type(of: plugin).descriptor.name): \(error.localizedDescription)", category: .system, level: .error)
            }
        }

        refreshContributions()
    }

    // MARK: - Capability Interrogation

    /// Queries the first loaded plugin that provides the specified capability.
    public func firstCapability<T>(_ capabilityType: T.Type) -> T? {
        for plugin in loadedPlugins {
            if let cap = plugin.capability(capabilityType) {
                return cap
            }
        }
        return nil
    }

    // MARK: - Helpers

    public func makeDefaultContext(for descriptor: PluginDescriptor, xPlaneURL: URL? = nil, activatedAircraftNames: [String]? = nil) -> PluginContext {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let pluginDataDir = appSupport.appendingPathComponent("XLauncher/PlugInsData/\(descriptor.id)")
        try? FileManager.default.createDirectory(at: pluginDataDir, withIntermediateDirectories: true)

        return PluginContext(
            hostVersion: AppInfo.version,
            xPlaneURL: xPlaneURL,
            xPlaneVersion: nil,
            activeProfile: nil,
            storageDirectory: pluginDataDir,
            logger: HostPluginLogger(pluginId: descriptor.id),
            licenseVerifier: HostPluginLicenseVerifier(),
            activatedAircraftNames: activatedAircraftNames
        )
    }

    public func resolveCandidateURLs() -> [URL] {
        var urls: [URL] = []
        var seenPaths: Set<String> = []

        func addCandidate(_ url: URL) {
            let std = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: std.path) else { return }
            if !seenPaths.contains(std.path) {
                seenPaths.insert(std.path)
                urls.append(std)
            }
        }

        // 1. Environment variable override
        if let envPath = ProcessInfo.processInfo.environment["XLAUNCHER_PLUGIN_PATH"], !envPath.isEmpty {
            addCandidate(URL(fileURLWithPath: envPath))
        }

        // 2. Production app bundle PlugIns directory
        if let plugInsURL = Bundle.main.builtInPlugInsURL {
            if let enumerator = FileManager.default.enumerator(at: plugInsURL, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "bundle" {
                        addCandidate(fileURL)
                    }
                }
            }
        }

        // 3. Application Support directory
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let userPluginsDir = appSupport.appendingPathComponent("XLauncher/PlugIns")
            if let enumerator = FileManager.default.enumerator(at: userPluginsDir, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "bundle" {
                        addCandidate(fileURL)
                    }
                }
            }
        }

        // 4. Sibling development paths (prefer build/ before .build/)
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        addCandidate(cwdURL.appendingPathComponent("../XLauncherPro/build/XLauncherPro.bundle"))
        addCandidate(cwdURL.appendingPathComponent("../XLauncherPro/.build/release/XLauncherPro.bundle"))

        return urls
    }
}
