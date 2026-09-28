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
    private let pathService = PathService.shared
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

    var addonBetaPreferences: [String: Bool] {
        get {
            defaults.object(forKey: .addonBetaPreferences) as? [String: Bool] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: .addonBetaPreferences)
        }
    }

    var storagePools: [StoragePool] = [] {
        didSet {
            guard storagePools != oldValue else { return }
            scanUpdatableAddons { [weak self] in
                self?.checkAutoUpdates()
            }
        }
    }

    var launcherDataFolder: URL? {
        get { storagePools.first(where: { $0.isPrimary })?.url ?? storagePools.first?.url }
        set {
            if let newURL = newValue {
                storagePools = [StoragePool(name: "Primary Storage", url: newURL, isPrimary: true)]
            } else {
                storagePools = []
            }
        }
    }

    var updatableAddons: [UpdatableAddon] = []
    var isScanning: Bool = false
    var logger: ConsoleLogger { ConsoleLogger.shared }

    var isCheckingUpdates: Bool {
        isScanning || updatableAddons.contains { $0.isChecking }
    }

    var isUpdatingAddons: Bool {
        updatableAddons.contains { $0.isUpdating }
    }

    var isProcessing: Bool {
        isScanning || updatableAddons.contains { $0.isChecking || $0.isUpdating }
    }

    func log(_ message: String, level: LogLevel = .info) {
        ConsoleLogger.shared.log(message, category: .updates, level: level)
    }

    func clearLogs() {
        ConsoleLogger.shared.clear(category: .updates)
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

    enum AddonCategory: String, Codable, Identifiable, CaseIterable {
        case aircraft = "Aircraft"
        case plugin = "Plugin"
        case scenery = "Scenery"
        case luaScript = "Lua Script"
        var id: String { rawValue }

        /// Where this category's source add-ons live inside the central data folder.
        var dataSubfolder: DataSubfolder {
            switch self {
            case .aircraft: return .aircraft
            case .plugin: return .plugins
            case .scenery: return .scenery
            case .luaScript: return .luaScripts
            }
        }
    }

    struct UpdatableAddon: Identifiable, Equatable, Hashable, Sendable {
        let id = UUID()
        let name: String
        let addonCategory: AddonCategory
        let folderName: String
        let folderURL: URL
        let updaterType: UpdaterType
        var configFileURL: URL
        var currentVersion: String?
        var latestVersion: String?
        var isUpdateAvailable: Bool = false
        var isChecking: Bool = false
        var isUpdating: Bool = false
        var statusMessage: String = "Unknown"
        var remoteManifestURL: String?
        var hasBetaChannel: Bool = false
        var isBetaEnabled: Bool = false

        var persistenceKey: String {
            "\(addonCategory.rawValue.lowercased()):\(folderName)"
        }
    }

    init(storagePools: [StoragePool] = []) {
        URLCache.shared.removeAllCachedResponses()

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

        self.storagePools = storagePools
        if !storagePools.isEmpty && updatableAddons.isEmpty {
            scanUpdatableAddons { [weak self] in
                self?.checkAutoUpdates()
            }
        }
    }

    convenience init(launcherDataFolder: URL) {
        let pool = StoragePool(name: "Primary Storage", url: launcherDataFolder, isPrimary: true)
        self.init(storagePools: [pool])
    }

    // MARK: - Scanning & Parsing

    private nonisolated static func findUpdaterConfig(in folderURL: URL) -> (type: UpdaterType, fileURL: URL)? {
        if let url = SkunkCraftsUpdaterService.shared.findConfig(in: folderURL) {
            return (.skunkcrafts, url)
        }
        if let url = XUpdaterService.shared.findConfig(in: folderURL) {
            return (.xUpdater, url)
        }
        return nil
    }

    private nonisolated static func parseUpdaterConfig(url: URL, type: UpdaterType, defaultName: String) -> (name: String, version: String?, remoteURL: String?) {
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

    private nonisolated static func scanDirectoryForAddons(
        subFolderURL: URL,
        category: AddonCategory,
        betaPreferences: [String: Bool] = [:],
        currentDepth: Int = 0,
        maxDepth: Int = 5
    ) -> [UpdatableAddon] {
        var results: [UpdatableAddon] = []
        guard currentDepth <= maxDepth else { return results }

        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: subFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for itemURL in contents {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

                if let updaterInfo = findUpdaterConfig(in: itemURL) {
                    let folderName = itemURL.lastPathComponent
                    let persistenceKey = "\(category.rawValue.lowercased()):\(folderName)"
                    let pathKey = itemURL.path

                    let hasBeta: Bool
                    var isBeta: Bool = betaPreferences[persistenceKey] ?? betaPreferences[pathKey] ?? false
                    var activeConfigFileURL = updaterInfo.fileURL

                    if updaterInfo.type == .skunkcrafts {
                        hasBeta = SkunkCraftsUpdaterService.shared.hasBetaChannel(in: itemURL)
                        if !hasBeta {
                            isBeta = false
                        }
                        if isBeta, let betaURL = SkunkCraftsUpdaterService.shared.findConfig(in: itemURL, preferBeta: true) {
                            activeConfigFileURL = betaURL
                        }
                    } else if updaterInfo.type == .xUpdater {
                        hasBeta = true
                    } else {
                        hasBeta = false
                    }

                    let (parsedName, version, remoteURL) = parseUpdaterConfig(url: activeConfigFileURL, type: updaterInfo.type, defaultName: folderName)

                    results.append(UpdatableAddon(
                        name: parsedName,
                        addonCategory: category,
                        folderName: folderName,
                        folderURL: itemURL,
                        updaterType: updaterInfo.type,
                        configFileURL: activeConfigFileURL,
                        currentVersion: version,
                        remoteManifestURL: remoteURL,
                        hasBetaChannel: hasBeta,
                        isBetaEnabled: isBeta
                    ))
                } else {
                    let subResults = scanDirectoryForAddons(
                        subFolderURL: itemURL,
                        category: category,
                        betaPreferences: betaPreferences,
                        currentDepth: currentDepth + 1,
                        maxDepth: maxDepth
                    )
                    results.append(contentsOf: subResults)
                }
            }
        }

        return results
    }

    func scanUpdatableAddons(completion: (@Sendable @MainActor () -> Void)? = nil) {
        let activePools = storagePools.filter { $0.isOnline }
        guard !activePools.isEmpty else {
            updatableAddons = []
            completion?()
            return
        }

        isScanning = true
        let currentBetaPrefs = self.addonBetaPreferences

        Task {
            let allAddons = await Task.detached(priority: .userInitiated) {
                var results: [UpdatableAddon] = []
                for pool in activePools {
                    for category in AddonCategory.allCases {
                        let folderURL = PathService.shared.dataFolder(category.dataSubfolder, in: pool.url)
                        if FileManager.default.fileExists(atPath: folderURL.path) {
                            let addons = Self.scanDirectoryForAddons(
                                subFolderURL: folderURL,
                                category: category,
                                betaPreferences: currentBetaPrefs
                            )
                            results.append(contentsOf: addons)
                        }
                    }
                }
                return results
            }.value

            self.isScanning = false
            self.updatableAddons = allAddons
            completion?()
        }
    }

    func scanAndCheckAllAddonUpdates() {
        guard !isProcessing else { return }
        scanUpdatableAddons { [weak self] in
            self?.checkAllAddonUpdates()
        }
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
                self.log("Error checking \(addon.name): \(error.localizedDescription)", level: .error)
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
                    let updatedAddon = self.updatableAddons[i]
                    let (_, newVersion, _) = Self.parseUpdaterConfig(url: updatedAddon.configFileURL, type: updatedAddon.updaterType, defaultName: updatedAddon.name)
                    let finalVersion = newVersion ?? self.updatableAddons[i].latestVersion
                    if let finalVersion {
                        self.updatableAddons[i].currentVersion = finalVersion
                        self.updatableAddons[i].latestVersion = finalVersion
                    }
                    self.updatableAddons[i].isUpdating = false
                    self.updatableAddons[i].isUpdateAvailable = false
                    self.updatableAddons[i].statusMessage = "Up to date"
                }
            } catch {
                self.log("Update failed for \(addon.name): \(error.localizedDescription)", level: .error)
                if let i = self.updatableAddons.firstIndex(where: { $0.id == addonId }) {
                    self.updatableAddons[i].isUpdating = false
                    self.updatableAddons[i].statusMessage = "Update failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func fetchReleaseNotes(for addon: UpdatableAddon) async -> String? {
        let updater = addon.updaterType.updater
        do {
            return try await updater.fetchReleaseNotes(for: addon) { [weak self] msg in
                self?.log(msg)
            }
        } catch {
            log("Error fetching release notes for \(addon.name): \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    func setBetaUpdatesEnabled(_ enabled: Bool, for addon: UpdatableAddon) {
        guard let index = updatableAddons.firstIndex(where: { $0.id == addon.id }) else { return }
        guard !updatableAddons[index].isUpdating else { return }

        // Update stored preferences
        var prefs = addonBetaPreferences
        prefs[addon.persistenceKey] = enabled
        prefs[addon.folderURL.path] = enabled
        addonBetaPreferences = prefs

        updatableAddons[index].isBetaEnabled = enabled

        // If SkunkCrafts, swap active config file
        if addon.updaterType == .skunkcrafts {
            let activeConfigFileURL: URL
            if enabled {
                activeConfigFileURL = addon.folderURL.appendingPathComponent("skunkcrafts_updater_beta.cfg")
            } else {
                activeConfigFileURL = addon.folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
            }
            if FileManager.default.fileExists(atPath: activeConfigFileURL.path) {
                updatableAddons[index].configFileURL = activeConfigFileURL
                let (_, version, remoteURL) = Self.parseUpdaterConfig(url: activeConfigFileURL, type: .skunkcrafts, defaultName: addon.name)
                if let version {
                    updatableAddons[index].currentVersion = version
                }
                if let remoteURL {
                    updatableAddons[index].remoteManifestURL = remoteURL
                }
            }
        } else if addon.updaterType == .xUpdater {
            // Update settings.ini / x-updater.json on disk asynchronously
            let folderURL = addon.folderURL
            Task {
                await XUpdaterService.shared.setBetaEnabled(enabled, in: folderURL)
            }
        }

        updatableAddons[index].isChecking = false
        updatableAddons[index].latestVersion = nil
        updatableAddons[index].isUpdateAvailable = false
        updatableAddons[index].statusMessage = "Channel: \(enabled ? "Beta" : "Release")"

        log("[Updates] \(addon.name): Switched to \(enabled ? "Beta" : "Release") channel")

        // Trigger immediate check on the newly selected channel
        checkForUpdates(for: updatableAddons[index])
    }
}

