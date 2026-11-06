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
                if let idx = storagePools.firstIndex(where: { $0.isPrimary }) {
                    storagePools[idx].url = newURL
                } else if !storagePools.isEmpty {
                    storagePools[0].url = newURL
                    storagePools[0].isPrimary = true
                } else {
                    storagePools = [StoragePool(name: "Primary Storage", url: newURL, isPrimary: true)]
                }
            } else {
                storagePools.removeAll(where: { $0.isPrimary })
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

    var availableUpdatesCount: Int {
        Self.groupAddons(updatableAddons).filter { $0.isUpdateAvailable }.count
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
        var mainChannelName: String? = nil
        var packId: String? = nil
        var memberId: String? = nil
        var packName: String? = nil

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
            activeChannel: String = "stable",
            mainChannelName: String? = nil,
            packId: String? = nil,
            memberId: String? = nil,
            packName: String? = nil
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
            self.mainChannelName = mainChannelName
            self.packId = packId
            self.memberId = memberId
            self.packName = packName
        }
    }

    struct UpdatablePack: Identifiable, Equatable, Hashable, Sendable {
        var id: String { "\(category.rawValue):\(packId)" }
        let packId: String
        var packName: String
        let category: AddonCategory
        let updaterType: UpdaterType
        var members: [UpdatableAddon]

        /// The display name for the pack, using packName or falling back to packId (PUBLISHING.md §5.5).
        var displayName: String {
            let trimmed = packName.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? packId : trimmed
        }

        /// The version shown is the members' common version, or "mixed" when they differ (PUBLISHING.md §5.5).
        var displayVersion: String? {
            let nonNilVersions = members.compactMap { $0.currentVersion?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !nonNilVersions.isEmpty else { return nil }
            guard nonNilVersions.count == members.count else {
                return "mixed"
            }
            let unique = Set(nonNilVersions)
            return unique.count == 1 ? nonNilVersions.first : "mixed"
        }

        /// Latest version across members, or "mixed" if they differ.
        var displayLatestVersion: String? {
            let nonNilVersions = members.compactMap { $0.latestVersion?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !nonNilVersions.isEmpty else { return nil }
            guard nonNilVersions.count == members.count else {
                return "mixed"
            }
            let unique = Set(nonNilVersions)
            return unique.count == 1 ? nonNilVersions.first : "mixed"
        }

        var isUpdateAvailable: Bool {
            members.contains { $0.isUpdateAvailable }
        }

        var isChecking: Bool {
            members.contains { $0.isChecking }
        }

        var isUpdating: Bool {
            members.contains { $0.isUpdating }
        }

        /// The status is the worst of the members' (PUBLISHING.md §5.5).
        var statusMessage: String {
            guard !members.isEmpty else { return "Unknown" }

            // 1. Errors / Failures take highest precedence
            if let failedMember = members.first(where: {
                let msg = $0.statusMessage.lowercased()
                return msg.contains("fail") || msg.contains("error")
            }) {
                return failedMember.statusMessage
            }

            // 2. In-flight update operations
            let updatingMembers = members.filter { $0.isUpdating }
            if !updatingMembers.isEmpty {
                if updatingMembers.count == 1, let first = updatingMembers.first {
                    return first.statusMessage
                }
                return "Updating (\(updatingMembers.count)/\(members.count))..."
            }

            // 3. In-flight checking operations
            let checkingMembers = members.filter { $0.isChecking }
            if !checkingMembers.isEmpty {
                return "Checking..."
            }

            // 4. Update / Repair available
            let updatableMembers = members.filter { $0.isUpdateAvailable }
            if !updatableMembers.isEmpty {
                let hasActualUpdate = updatableMembers.contains { member in
                    let msg = member.statusMessage.lowercased()
                    if msg.contains("repair") { return false }
                    if let cur = member.currentVersion, let lat = member.latestVersion, cur == lat {
                        return false
                    }
                    return true
                }

                if hasActualUpdate {
                    if updatableMembers.count == members.count {
                        return "Update available"
                    } else {
                        return "Update available (\(updatableMembers.count) of \(members.count) folders)"
                    }
                } else {
                    if updatableMembers.count == members.count {
                        return "Repair available"
                    } else {
                        return "Repair available (\(updatableMembers.count) of \(members.count) folders)"
                    }
                }
            }

            // 5. If all members are "Up to date"
            let allUpToDate = members.allSatisfy { $0.statusMessage.lowercased() == "up to date" }
            if allUpToDate {
                return "Up to date"
            }

            // 6. If any member is "Unknown" or "Idle"
            if members.contains(where: {
                let msg = $0.statusMessage.lowercased()
                return msg == "unknown" || msg == "idle"
            }) {
                return "Unknown"
            }

            // 7. Otherwise, return the first non-trivial status message
            return members.first?.statusMessage ?? "Unknown"
        }

        var activeChannel: String {
            let channels = members.map { $0.activeChannel.lowercased() }
            let unique = Set(channels)
            return unique.count == 1 ? (unique.first ?? "stable") : "mixed"
        }

        var availableChannels: [String] {
            var allChannels: [String] = []
            for member in members {
                for ch in member.availableChannels {
                    if !allChannels.contains(where: { $0.lowercased() == ch.lowercased() }) {
                        allChannels.append(ch)
                    }
                }
            }
            return allChannels.isEmpty ? ["stable"] : allChannels
        }

        var mainChannelName: String? {
            members.compactMap(\.mainChannelName).first(where: { !$0.isEmpty })
        }
    }

    enum UpdatableItem: Identifiable, Equatable, Hashable, Sendable {
        case standalone(UpdatableAddon)
        case pack(UpdatablePack)

        var id: String {
            switch self {
            case .standalone(let addon):
                return "addon:\(addon.id.uuidString)"
            case .pack(let pack):
                return "pack:\(pack.id)"
            }
        }

        var category: AddonCategory {
            switch self {
            case .standalone(let addon): return addon.addonCategory
            case .pack(let pack): return pack.category
            }
        }

        var isUpdateAvailable: Bool {
            switch self {
            case .standalone(let addon): return addon.isUpdateAvailable
            case .pack(let pack): return pack.isUpdateAvailable
            }
        }

        var isChecking: Bool {
            switch self {
            case .standalone(let addon): return addon.isChecking
            case .pack(let pack): return pack.isChecking
            }
        }

        var isUpdating: Bool {
            switch self {
            case .standalone(let addon): return addon.isUpdating
            case .pack(let pack): return pack.isUpdating
            }
        }
    }

    /// Groups addons sharing the same pack identifier into composite pack entries (PUBLISHING.md §5.5).
    /// Standalone add-ons (without a pack identifier) remain individual items.
    static func groupAddons(_ addons: [UpdatableAddon]) -> [UpdatableItem] {
        var items: [UpdatableItem] = []
        var packIndices: [String: Int] = [:]

        for addon in addons {
            if let packId = addon.packId?.trimmingCharacters(in: .whitespaces), !packId.isEmpty {
                let key = "\(addon.addonCategory.rawValue):\(packId)"
                if let existingIndex = packIndices[key] {
                    if case .pack(var pack) = items[existingIndex] {
                        pack.members.append(addon)
                        if pack.packName.isEmpty, let pName = addon.packName?.trimmingCharacters(in: .whitespaces), !pName.isEmpty {
                            pack.packName = pName
                        }
                        items[existingIndex] = .pack(pack)
                    }
                } else {
                    let packName = addon.packName?.trimmingCharacters(in: .whitespaces) ?? ""
                    let newPack = UpdatablePack(
                        packId: packId,
                        packName: packName,
                        category: addon.addonCategory,
                        updaterType: addon.updaterType,
                        members: [addon]
                    )
                    packIndices[key] = items.count
                    items.append(.pack(newPack))
                }
            } else {
                items.append(.standalone(addon))
            }
        }

        return items
    }

    init(storagePools: [StoragePool]? = nil) {
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

        let pools = storagePools ?? StoragePoolService.shared.loadStoragePools()
        self.storagePools = pools
        if !pools.isEmpty && updatableAddons.isEmpty {
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
        defaultName: String,
        overrideChannel: String? = nil
    ) -> (
        name: String,
        version: String?,
        remoteURL: String?,
        availableChannels: [String],
        defaultChannel: String,
        activeChannel: String,
        mainChannelName: String?,
        packId: String?,
        memberId: String?,
        packName: String?
    ) {
        if type == .skunkcrafts {
            if let config = SkunkCraftsUpdaterService.shared.parseConfig(at: url, defaultName: defaultName, overrideChannel: overrideChannel) {
                return (
                    config.name,
                    config.version,
                    config.remoteManifestURL,
                    config.availableChannels.isEmpty ? ["stable"] : config.availableChannels,
                    config.activeChannel,
                    config.activeChannel,
                    config.mainName,
                    config.packId,
                    config.memberId,
                    config.packName
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
                    active,
                    nil,
                    nil,
                    nil,
                    nil
                )
            }
        }
        return (defaultName, nil, nil, ["stable"], "stable", "stable", nil, nil, nil, nil)
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
                    if updaterInfo.type == .skunkcrafts {
                        SkunkCraftsUpdaterService.shared.absorbBetaFiles(in: itemURL)
                        activeConfigFileURL = itemURL.appendingPathComponent("skunkcrafts_updater.cfg")
                    }

                    var (parsedName, version, remoteURL, availableChannels, _, configActiveChannel, mainChannelName, packId, memberId, packName) = parseUpdaterConfig(
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

                    if updaterInfo.type == .skunkcrafts && selectedChannel.lowercased() != configActiveChannel.lowercased() {
                        let reParsed = parseUpdaterConfig(
                            url: activeConfigFileURL,
                            type: updaterInfo.type,
                            defaultName: folderName,
                            overrideChannel: selectedChannel
                        )
                        if let v = reParsed.version { version = v }
                        if let u = reParsed.remoteURL { remoteURL = u }
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
                        activeChannel: selectedChannel,
                        mainChannelName: mainChannelName,
                        packId: packId,
                        memberId: memberId,
                        packName: packName
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
                        var scannedRoots: Set<String> = []

                        // 1. Standard subfolder: <pool>/Scenery (or Aircraft, Plugins, LuaScripts)
                        let subfolderURL = PathService.shared.dataFolder(category.dataSubfolder, in: pool.url)
                        if FileManager.default.fileExists(atPath: subfolderURL.path) {
                            scannedRoots.insert(subfolderURL.path)
                            let addons = Self.scanDirectoryForAddons(
                                subFolderURL: subfolderURL,
                                category: category,
                                channelPreferences: currentChannelPrefs,
                                betaPreferences: currentBetaPrefs
                            )
                            results.append(contentsOf: addons)
                        }

                        // 2. Direct pool root: if the pool is dedicated to this category or matches its name
                        let poolNameLower = pool.url.lastPathComponent.lowercased()
                        let isDedicatedToCategory = poolNameLower == category.rawValue.lowercased() ||
                                                    poolNameLower == category.dataSubfolder.rawValue.lowercased() ||
                                                    (pool.defaultCategories.count == 1 && pool.defaultCategories.first?.rawValue.lowercased().contains(category.rawValue.lowercased()) == true)
                        if isDedicatedToCategory && !scannedRoots.contains(pool.url.path) && FileManager.default.fileExists(atPath: pool.url.path) {
                            scannedRoots.insert(pool.url.path)
                            let addons = Self.scanDirectoryForAddons(
                                subFolderURL: pool.url,
                                category: category,
                                channelPreferences: currentChannelPrefs,
                                betaPreferences: currentBetaPrefs
                            )
                            for addon in addons {
                                if !results.contains(where: { $0.configFileURL == addon.configFileURL }) {
                                    results.append(addon)
                                }
                            }
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

        // If SkunkCrafts, set channel in skunkcrafts/channel.cfg and resolve remote manifest
        if addon.updaterType == .skunkcrafts {
            SkunkCraftsUpdaterService.shared.setChannel(normalized, in: addon.folderURL)

            let activeConfigFileURL = addon.folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
            if FileManager.default.fileExists(atPath: activeConfigFileURL.path) {
                updatableAddons[index].configFileURL = activeConfigFileURL
                let parsed = Self.parseUpdaterConfig(url: activeConfigFileURL, type: .skunkcrafts, defaultName: addon.name, overrideChannel: normalized)
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

    // MARK: - Pack Batch Operations (PUBLISHING.md §5.5)

    func checkForUpdates(forPack pack: UpdatablePack) {
        for member in pack.members {
            checkForUpdates(for: member)
        }
    }

    func updatePack(_ pack: UpdatablePack) {
        let toUpdate = pack.members.filter { $0.isUpdateAvailable }
        let targets = toUpdate.isEmpty ? pack.members : toUpdate
        for member in targets {
            updateAddon(member)
        }
    }

    func repairPack(_ pack: UpdatablePack) {
        for member in pack.members {
            updateAddon(member)
        }
    }

    func setChannel(_ channel: String, forPack pack: UpdatablePack) {
        for member in pack.members {
            setChannel(channel, for: member)
        }
    }
}

