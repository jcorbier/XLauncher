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

    var addonChannelPreferences: [String: String] {
        get {
            defaults.object(forKey: .addonChannelPreferences) as? [String: String] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: .addonChannelPreferences)
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
        var availableChannels: [String] = ["stable"]
        var activeChannel: String = "stable"

        var persistenceKey: String {
            "\(addonCategory.rawValue.lowercased()):\(folderName)"
        }

        init(
            name: String,
            addonCategory: AddonCategory,
            folderName: String,
            folderURL: URL,
            updaterType: UpdaterType,
            configFileURL: URL,
            currentVersion: String? = nil,
            latestVersion: String? = nil,
            isUpdateAvailable: Bool = false,
            isChecking: Bool = false,
            isUpdating: Bool = false,
            statusMessage: String = "Unknown",
            remoteManifestURL: String? = nil,
            hasBetaChannel: Bool = false,
            isBetaEnabled: Bool = false,
            availableChannels: [String] = ["stable"],
            activeChannel: String = "stable"
        ) {
            self.name = name
            self.addonCategory = addonCategory
            self.folderName = folderName
            self.folderURL = folderURL
            self.updaterType = updaterType
            self.configFileURL = configFileURL
            self.currentVersion = currentVersion
            self.latestVersion = latestVersion
            self.isUpdateAvailable = isUpdateAvailable
            self.isChecking = isChecking
            self.isUpdating = isUpdating
            self.statusMessage = statusMessage
            self.remoteManifestURL = remoteManifestURL
            self.hasBetaChannel = hasBetaChannel
            self.isBetaEnabled = isBetaEnabled
            self.availableChannels = availableChannels
            self.activeChannel = activeChannel
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

    private nonisolated static func parseUpdaterConfig(
        url: URL,
        type: UpdaterType,
        defaultName: String
    ) -> (
        name: String,
        version: String?,
        remoteURL: String?,
        availableChannels: [String],
        defaultChannel: String,
        activeChannel: String
    ) {
        if type == .skunkcrafts {
            if let config = SkunkCraftsUpdaterService.shared.parseConfig(at: url, defaultName: defaultName) {
                return (
                    config.name,
                    config.version,
                    config.remoteManifestURL,
                    config.availableChannels.isEmpty ? ["stable"] : config.availableChannels,
                    config.activeChannel,
                    config.activeChannel
                )
            }
        } else if type == .xUpdater {
            if let config = XUpdaterService.shared.parseConfig(at: url, defaultName: defaultName) {
                let active = config.betaEnabled ? "beta" : "stable"
                return (
                    config.name,
                    config.version,
                    config.remoteURL,
                    ["stable", "beta"],
                    "stable",
                    active
                )
            }
        }
        return (defaultName, nil, nil, ["stable"], "stable", "stable")
    }

    private nonisolated static func scanDirectoryForAddons(
        subFolderURL: URL,
        category: AddonCategory,
        channelPreferences: [String: String] = [:],
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

                    var activeConfigFileURL = updaterInfo.fileURL

                    var (parsedName, version, remoteURL, availableChannels, _, configActiveChannel) = parseUpdaterConfig(
                        url: activeConfigFileURL,
                        type: updaterInfo.type,
                        defaultName: folderName
                    )

                    var selectedChannel = configActiveChannel
                    if let pref = channelPreferences[persistenceKey] ?? channelPreferences[pathKey],
                       availableChannels.contains(where: { $0.lowercased() == pref.lowercased() }) {
                        selectedChannel = pref.lowercased()
                    } else if let legacyBeta = betaPreferences[persistenceKey] ?? betaPreferences[pathKey] {
                        if legacyBeta && availableChannels.contains("beta") {
                            selectedChannel = "beta"
                        } else if !legacyBeta {
                            selectedChannel = "stable"
                        }
                    } else {
                        selectedChannel = configActiveChannel
                    }

                    let isBeta = (selectedChannel.lowercased() == "beta")

                    if updaterInfo.type == .skunkcrafts {
                        if isBeta, let betaURL = SkunkCraftsUpdaterService.shared.findConfig(in: itemURL, preferBeta: true), betaURL != activeConfigFileURL {
                            activeConfigFileURL = betaURL
                            let betaParsed = parseUpdaterConfig(url: betaURL, type: .skunkcrafts, defaultName: folderName)
                            if let v = betaParsed.version { version = v }
                            if let u = betaParsed.remoteURL { remoteURL = u }
                        }
                    }

                    let hasBeta = availableChannels.count > 1 || availableChannels.contains(where: { $0.lowercased() != "stable" })

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
                        isBetaEnabled: isBeta,
                        availableChannels: availableChannels,
                        activeChannel: selectedChannel
                    ))
                } else {
                    let subResults = scanDirectoryForAddons(
                        subFolderURL: itemURL,
                        category: category,
                        channelPreferences: channelPreferences,
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
        let currentChannelPrefs = self.addonChannelPreferences
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
                                channelPreferences: currentChannelPrefs,
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

        Task { @MainActor [self] in
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

        Task { @MainActor [self] in
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
                    let parsed = Self.parseUpdaterConfig(url: updatedAddon.configFileURL, type: updatedAddon.updaterType, defaultName: updatedAddon.name)
                    let finalVersion = parsed.version ?? self.updatableAddons[i].latestVersion
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

    func setChannel(_ channel: String, for addon: UpdatableAddon) {
        guard let index = updatableAddons.firstIndex(where: { $0.id == addon.id }) else { return }
        guard !updatableAddons[index].isUpdating else { return }

        let normalized = channel.lowercased()
        let isBeta = (normalized == "beta")

        // Update stored preferences
        var channelPrefs = addonChannelPreferences
        channelPrefs[addon.persistenceKey] = normalized
        channelPrefs[addon.folderURL.path] = normalized
        addonChannelPreferences = channelPrefs

        var betaPrefs = addonBetaPreferences
        betaPrefs[addon.persistenceKey] = isBeta
        betaPrefs[addon.folderURL.path] = isBeta
        addonBetaPreferences = betaPrefs

        updatableAddons[index].activeChannel = normalized
        updatableAddons[index].isBetaEnabled = isBeta

        // If SkunkCrafts, swap active config file if legacy beta and update pointer
        if addon.updaterType == .skunkcrafts {
            SkunkCraftsUpdaterService.shared.setChannel(normalized, in: addon.folderURL)

            let activeConfigFileURL: URL
            if isBeta {
                let betaURL = addon.folderURL.appendingPathComponent("skunkcrafts_updater_beta.cfg")
                if FileManager.default.fileExists(atPath: betaURL.path) {
                    activeConfigFileURL = betaURL
                } else {
                    activeConfigFileURL = addon.folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
                }
            } else {
                activeConfigFileURL = addon.folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
            }

            if FileManager.default.fileExists(atPath: activeConfigFileURL.path) {
                updatableAddons[index].configFileURL = activeConfigFileURL
                let parsed = Self.parseUpdaterConfig(url: activeConfigFileURL, type: .skunkcrafts, defaultName: addon.name)
                if let version = parsed.version {
                    updatableAddons[index].currentVersion = version
                }
                if let remoteURL = parsed.remoteURL {
                    updatableAddons[index].remoteManifestURL = remoteURL
                }
            }
        } else if addon.updaterType == .xUpdater {
            // Update settings.ini / x-updater.json on disk asynchronously
            let folderURL = addon.folderURL
            Task {
                await XUpdaterService.shared.setBetaEnabled(isBeta, in: folderURL)
            }
            let parsed = Self.parseUpdaterConfig(url: addon.configFileURL, type: .xUpdater, defaultName: addon.name)
            if let version = parsed.version {
                updatableAddons[index].currentVersion = version
            }
            if let remoteURL = parsed.remoteURL {
                updatableAddons[index].remoteManifestURL = remoteURL
            }
        }

        updatableAddons[index].isChecking = false
        updatableAddons[index].latestVersion = nil
        updatableAddons[index].isUpdateAvailable = false
        updatableAddons[index].statusMessage = "Channel: \(normalized.capitalized)"

        log("[Updates] \(addon.name): Switched to \(normalized.capitalized) channel")

        // Trigger immediate check on the newly selected channel
        checkForUpdates(for: updatableAddons[index])
    }

    func setBetaUpdatesEnabled(_ enabled: Bool, for addon: UpdatableAddon) {
        setChannel(enabled ? "beta" : "stable", for: addon)
    }
}

