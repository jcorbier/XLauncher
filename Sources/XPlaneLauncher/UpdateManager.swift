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

@MainActor
@Observable
class UpdateManager {
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    var automaticallyCheckSkunkCraftsUpdates: Bool {
        didSet {
            defaults.set(automaticallyCheckSkunkCraftsUpdates, forKey: .autoCheckSkunkCraftsUpdates)
        }
    }

    var automaticallyCheckXUpdaterUpdates: Bool {
        didSet {
            defaults.set(automaticallyCheckXUpdaterUpdates, forKey: .autoCheckXUpdaterUpdates)
        }
    }

    var launcherDataFolder: URL? {
        didSet {
            guard launcherDataFolder != oldValue else { return }
            scanUpdatableAddons()
            checkAutoUpdates()
        }
    }

    var updatableAddons: [UpdatableAddon] = []
    let logger = ConsoleLogger()

    var isCheckingUpdates: Bool {
        updatableAddons.contains { $0.isChecking }
    }

    var isUpdatingAddons: Bool {
        updatableAddons.contains { $0.isUpdating }
    }

    var isProcessing: Bool {
        updatableAddons.contains { $0.isChecking || $0.isUpdating }
    }

    func log(_ message: String) {
        logger.log(message)
    }

    func clearLogs() {
        logger.clear()
    }

    enum UpdaterType: String, Codable, Identifiable {
        case skunkcrafts = "SkunkCrafts"
        case xUpdater = "X-Updater"
        var id: String { rawValue }

        var updater: any AddonUpdater {
            switch self {
            case .skunkcrafts:
                return SkunkCraftsUpdaterService.shared
            case .xUpdater:
                return XUpdaterService.shared
            }
        }
    }

    enum AddonCategory: String, Codable, Identifiable {
        case aircraft = "Aircraft"
        case plugin = "Plugin"
        case scenery = "Scenery"
        case luaScript = "Lua Script"
        var id: String { rawValue }
    }

    struct UpdatableAddon: Identifiable, Equatable, Hashable {
        let id = UUID()
        let name: String
        let addonCategory: AddonCategory
        let folderName: String
        let folderURL: URL
        let updaterType: UpdaterType
        let configFileURL: URL
        var currentVersion: String?
        var latestVersion: String?
        var isUpdateAvailable: Bool = false
        var isChecking: Bool = false
        var isUpdating: Bool = false
        var statusMessage: String = "Unknown"
        var remoteManifestURL: String?
    }

    init(launcherDataFolder: URL? = nil) {
        if defaults.object(forKey: .autoCheckSkunkCraftsUpdates) == nil {
            self.automaticallyCheckSkunkCraftsUpdates = true
        } else {
            self.automaticallyCheckSkunkCraftsUpdates = defaults.bool(forKey: .autoCheckSkunkCraftsUpdates)
        }

        if defaults.object(forKey: .autoCheckXUpdaterUpdates) == nil {
            self.automaticallyCheckXUpdaterUpdates = true
        } else {
            self.automaticallyCheckXUpdaterUpdates = defaults.bool(forKey: .autoCheckXUpdaterUpdates)
        }

        self.launcherDataFolder = launcherDataFolder
        if launcherDataFolder != nil && updatableAddons.isEmpty {
            scanUpdatableAddons()
            checkAutoUpdates()
        }
    }

    // MARK: - Scanning & Parsing

    private func findUpdaterConfig(in folderURL: URL) -> (type: UpdaterType, fileURL: URL)? {
        if let url = SkunkCraftsUpdaterService.shared.findConfig(in: folderURL) {
            return (.skunkcrafts, url)
        }
        if let url = XUpdaterService.shared.findConfig(in: folderURL) {
            return (.xUpdater, url)
        }
        return nil
    }

    private func parseUpdaterConfig(url: URL, type: UpdaterType, defaultName: String) -> (name: String, version: String?, remoteURL: String?) {
        if type == .skunkcrafts {
            if let config = SkunkCraftsUpdaterService.shared.parseConfig(at: url, defaultName: defaultName) {
                return (config.name, config.version, config.remoteManifestURL)
            }
        } else if type == .xUpdater {
            if let config = XUpdaterService.shared.parseConfig(at: url, defaultName: defaultName) {
                return (config.name, config.version, config.remoteURL)
            }
        }
        return (defaultName, nil, nil)
    }

    private func scanDirectoryForAddons(subFolderURL: URL, category: AddonCategory, currentDepth: Int = 0, maxDepth: Int = 5) -> [UpdatableAddon] {
        var results: [UpdatableAddon] = []
        guard currentDepth <= maxDepth else { return results }

        if let contents = try? fileManager.contentsOfDirectory(at: subFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for itemURL in contents {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

                if let updaterInfo = findUpdaterConfig(in: itemURL) {
                    let folderName = itemURL.lastPathComponent
                    let (parsedName, version, remoteURL) = parseUpdaterConfig(url: updaterInfo.fileURL, type: updaterInfo.type, defaultName: folderName)

                    results.append(UpdatableAddon(
                        name: parsedName,
                        addonCategory: category,
                        folderName: folderName,
                        folderURL: itemURL,
                        updaterType: updaterInfo.type,
                        configFileURL: updaterInfo.fileURL,
                        currentVersion: version,
                        remoteManifestURL: remoteURL
                    ))
                } else {
                    let subResults = scanDirectoryForAddons(subFolderURL: itemURL, category: category, currentDepth: currentDepth + 1, maxDepth: maxDepth)
                    results.append(contentsOf: subResults)
                }
            }
        }

        return results
    }

    func scanUpdatableAddons() {
        guard let dataFolder = launcherDataFolder else {
            updatableAddons = []
            return
        }

        var allAddons: [UpdatableAddon] = []

        let categoryFolders: [(AddonCategory, String)] = [
            (.aircraft, "Aircraft"),
            (.plugin, "Plugins"),
            (.scenery, "Custom Scenery"),
            (.luaScript, "FlyWithLua/Scripts")
        ]

        for (category, subFolder) in categoryFolders {
            let folderURL = dataFolder.appendingPathComponent(subFolder)
            if fileManager.fileExists(atPath: folderURL.path) {
                let addons = scanDirectoryForAddons(subFolderURL: folderURL, category: category)
                allAddons.append(contentsOf: addons)
            }
        }

        self.updatableAddons = allAddons
    }

    // MARK: - Update Checking

    func checkAutoUpdates() {
        for addon in updatableAddons where !addon.isChecking && !addon.isUpdating {
            if addon.updaterType == .skunkcrafts && !automaticallyCheckSkunkCraftsUpdates {
                continue
            }
            if addon.updaterType == .xUpdater && !automaticallyCheckXUpdaterUpdates {
                continue
            }
            checkForUpdates(for: addon)
        }
    }

    func checkAllAddonUpdates() {
        for addon in updatableAddons where !addon.isChecking && !addon.isUpdating {
            checkForUpdates(for: addon)
        }
    }

    func checkForUpdates(for addon: UpdatableAddon) {
        guard let index = updatableAddons.firstIndex(where: { $0.id == addon.id }) else { return }
        guard !updatableAddons[index].isChecking && !updatableAddons[index].isUpdating else { return }
        updatableAddons[index].isChecking = true
        updatableAddons[index].statusMessage = "Checking..."

        let addonId = addon.id
        guard let remoteURLString = addon.remoteManifestURL, !remoteURLString.isEmpty else {
            if let i = self.updatableAddons.firstIndex(where: { $0.id == addonId }) {
                self.updatableAddons[i].isChecking = false
                self.updatableAddons[i].statusMessage = "Up to date"
            }
            return
        }

        let updater = addon.updaterType.updater

        Task { @MainActor in
            do {
                let result = try await updater.checkStatus(for: addon) { [weak self] msg in
                    self?.log(msg)
                }

                if let i = self.updatableAddons.firstIndex(where: { $0.id == addonId }) {
                    self.updatableAddons[i].isChecking = false
                    self.updatableAddons[i].latestVersion = result.latestVersion
                    self.updatableAddons[i].isUpdateAvailable = result.isUpdateAvailable
                    self.updatableAddons[i].statusMessage = result.statusMessage
                }
            } catch {
                self.log("[UpdateManager] Error checking \(addon.name): \(error.localizedDescription)")
                if let i = self.updatableAddons.firstIndex(where: { $0.id == addonId }) {
                    self.updatableAddons[i].isChecking = false
                    self.updatableAddons[i].isUpdateAvailable = false
                    self.updatableAddons[i].statusMessage = "Check failed"
                }
            }
        }
    }

    func updateAddon(_ addon: UpdatableAddon) {
        guard let index = updatableAddons.firstIndex(where: { $0.id == addon.id }) else { return }
        guard !updatableAddons[index].isUpdating else { return }
        updatableAddons[index].isUpdating = true
        updatableAddons[index].statusMessage = "Updating..."

        let addonId = addon.id
        let updater = addon.updaterType.updater

        Task { @MainActor in
            do {
                try await updater.applyUpdates(
                    for: addon,
                    logHandler: { [weak self] msg in
                        self?.log(msg)
                    },
                    progressHandler: { [weak self] message, progress in
                        if let i = self?.updatableAddons.firstIndex(where: { $0.id == addonId }) {
                            self?.updatableAddons[i].statusMessage = message
                        }
                    }
                )

                if let i = self.updatableAddons.firstIndex(where: { $0.id == addonId }) {
                    if let latest = self.updatableAddons[i].latestVersion {
                        self.updatableAddons[i].currentVersion = latest
                    }
                    self.updatableAddons[i].isUpdating = false
                    self.updatableAddons[i].isUpdateAvailable = false
                    self.updatableAddons[i].statusMessage = "Up to date"
                }
            } catch {
                self.log("[UpdateManager] Update failed for \(addon.name): \(error.localizedDescription)")
                if let i = self.updatableAddons.firstIndex(where: { $0.id == addonId }) {
                    self.updatableAddons[i].isUpdating = false
                    self.updatableAddons[i].statusMessage = "Update failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
