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

@MainActor
@Observable
class PluginManager {
    // Model typealiases for view compatibility
    typealias Plugin = XPlaneLauncher.Plugin
    typealias Aircraft = XPlaneLauncher.Aircraft
    typealias LuaScript = XPlaneLauncher.LuaScript
    typealias Scenery = XPlaneLauncher.Scenery
    typealias SceneryGroup = XPlaneLauncher.SceneryGroup
    typealias PluginProfile = XPlaneLauncher.PluginProfile
    typealias ProfileScript = XPlaneLauncher.ProfileScript
    typealias ScriptEnvVar = XPlaneLauncher.ScriptEnvVar

    // Injected / shared domain services
    private let pathService = PathService.shared
    private let symlinkService = SymlinkService.shared
    private let sceneryService = SceneryService.shared
    private let profileService = ProfileService.shared
    private let launchService = LaunchService.shared
    private let storagePoolService = StoragePoolService.shared

    private let defaults = UserDefaults.standard
    private var isLoading = true
    private var isRestoringState = false

    // MARK: - Storage Pools & Paths

    var storagePools: [StoragePool] = [] {
        didSet {
            guard !isLoading else { return }
            saveStoragePools()
            ensureLauncherDataDirectories()
            repairStaleLinks()
            scanPlugins()
            scanScenery()
            scanAircraft()
            scanLuaScripts()
            refreshStoragePoolStats()
        }
    }

    var storagePoolStats: [UUID: StoragePoolStats] = [:]

    var primaryStoragePool: StoragePool? {
        storagePools.first(where: { $0.isPrimary }) ?? storagePools.first
    }

    var launcherDataFolder: URL? {
        get {
            primaryStoragePool?.url
        }
        set {
            guard let newURL = newValue else { return }
            if let primaryIdx = storagePools.firstIndex(where: { $0.isPrimary }) {
                storagePools[primaryIdx].url = newURL
            } else if !storagePools.isEmpty {
                storagePools[0].url = newURL
                storagePools[0].isPrimary = true
            } else {
                storagePools = [StoragePool(name: "Primary Storage", url: newURL, isPrimary: true, defaultCategories: AddonCategory.allCases)]
            }
        }
    }

    var pluginsDataFolder: URL? {
        launcherDataFolder.map { pathService.dataFolder(.plugins, in: $0) }
    }

    var sceneryDataFolder: URL? {
        launcherDataFolder.map { pathService.dataFolder(.scenery, in: $0) }
    }

    var aircraftDataFolder: URL? {
        launcherDataFolder.map { pathService.dataFolder(.aircraft, in: $0) }
    }

    var luaScriptsDataFolder: URL? {
        launcherDataFolder.map { pathService.dataFolder(.luaScripts, in: $0) }
    }

    var xPlanePath: URL? {
        didSet {
            guard !isLoading else { return }
            savePath()
            scanPlugins()
            scanScenery()
            scanAircraft()
            scanLuaScripts()
        }
    }

    var flyWithLuaScriptsFolder: URL? {
        guard let xPlanePath = xPlanePath else { return nil }
        return pathService.flyWithLuaScriptsFolder(for: xPlanePath)
    }

    var flyWithLuaModulesFolder: URL? {
        guard let xPlanePath = xPlanePath else { return nil }
        return pathService.flyWithLuaModulesFolder(for: xPlanePath)
    }

    var cslPath: URL? {
        guard let xPlanePath = xPlanePath else { return nil }
        return pathService.cslFolder(for: xPlanePath)
    }

    // MARK: - App Preferences

    var enableCSLSupport: Bool = false {
        didSet {
            guard !isLoading else { return }
            defaults.set(enableCSLSupport, forKey: .enableCSLSupport)
        }
    }

    var enableCSLXP12Lights: Bool = false {
        didSet {
            guard !isLoading else { return }
            defaults.set(enableCSLXP12Lights, forKey: .enableCSLXP12Lights)
        }
    }

    var enableNavdataSupport: Bool = false {
        didSet {
            guard !isLoading else { return }
            defaults.set(enableNavdataSupport, forKey: .enableNavdataSupport)
        }
    }

    var hasCompletedWelcome: Bool = false {
        didSet {
            guard !isLoading else { return }
            defaults.set(hasCompletedWelcome, forKey: .hasCompletedWelcome)
        }
    }

    var isConfigured: Bool {
        xPlanePath != nil
    }

    // MARK: - Addon State

    var plugins: [Plugin] = []
    var scenery: [Scenery] = []
    var aircraft: [Aircraft] = []
    var luaScripts: [LuaScript] = []

    var scriptEnvironment: [ScriptEnvVar] = [] {
        didSet {
            saveScriptEnvironment()
        }
    }
    var sceneryGroups: [SceneryGroup] = [] {
        didSet {
            saveSceneryGroups()
        }
    }

    var profiles: [PluginProfile] = []
    var activeScripts: [ProfileScript] = []
    var activeEnvironmentVariables: [ScriptEnvVar] = []
    var lastErrorMessage: String? = nil

    var selectedProfileId: UUID? {
        didSet {
            if let id = selectedProfileId {
                defaults.set(id.uuidString, forKey: .selectedProfileId)
                if let profile = profiles.first(where: { $0.id == id }) {
                    if !isRestoringState {
                        applyProfile(profile)
                    }
                }
            } else {
                defaults.removeObject(forKey: .selectedProfileId)
            }
        }
    }

    var selectedProfile: PluginProfile? {
        guard let id = selectedProfileId else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    func isPluginModified(_ plugin: Plugin) -> Bool {
        guard let profile = selectedProfile else { return false }
        let profileEnabled = profile.pluginFolderNames.contains(plugin.folderName)
        return plugin.isEnabled != profileEnabled
    }

    func isSceneryModified(_ item: Scenery) -> Bool {
        guard let profile = selectedProfile else { return false }
        let profileEnabled = profile.sceneryFolderNames.contains(item.folderName)
        return item.isEnabled != profileEnabled
    }

    func isAircraftModified(_ item: Aircraft) -> Bool {
        guard let profile = selectedProfile else { return false }
        let profileEnabled = profile.aircraftFolderNames.contains(item.folderName)
        return item.isEnabled != profileEnabled
    }

    func isLuaScriptModified(_ item: LuaScript) -> Bool {
        guard let profile = selectedProfile else { return false }
        let profileEnabled = profile.luaScriptFolderNames.contains(item.folderName)
        return item.isEnabled != profileEnabled
    }

    func isProfileScriptModified(_ item: ProfileScript) -> Bool {
        guard let profile = selectedProfile else { return false }
        guard let saved = profile.scripts.first(where: { $0.id == item.id || $0.path == item.path }) else {
            return true
        }
        return item.isEnabled != saved.isEnabled
    }

    func isEnvVarModified(_ item: ScriptEnvVar) -> Bool {
        guard let profile = selectedProfile else { return false }
        guard let saved = profile.environmentVariables.first(where: { $0.id == item.id }) else {
            return true
        }
        return item.key != saved.key || item.value != saved.value
    }

    var isCurrentProfileModified: Bool {
        guard let selectedProfileId = selectedProfileId,
              let profile = profiles.first(where: { $0.id == selectedProfileId }) else {
            return false
        }

        let currentEnabledPlugins = Set(plugins.filter { $0.isEnabled }.map { $0.folderName })
        let profileEnabledPlugins = Set(profile.pluginFolderNames)

        let currentEnabledScenery = Set(scenery.filter { $0.isEnabled }.map { $0.folderName })
        let profileEnabledScenery = Set(profile.sceneryFolderNames)

        let currentEnabledAircraft = Set(aircraft.filter { $0.isEnabled }.map { $0.folderName })
        let profileEnabledAircraft = Set(profile.aircraftFolderNames)

        let currentEnabledLua = Set(luaScripts.filter { $0.isEnabled }.map { $0.folderName })
        let profileEnabledLua = Set(profile.luaScriptFolderNames)

        let currentScripts = Set(activeScripts)
        let profileScripts = Set(profile.scripts)

        let currentEnvVars = Set(activeEnvironmentVariables)
        let profileEnvVars = Set(profile.environmentVariables)

        return currentEnabledPlugins != profileEnabledPlugins
            || currentEnabledScenery != profileEnabledScenery
            || currentEnabledAircraft != profileEnabledAircraft
            || currentEnabledLua != profileEnabledLua
            || currentScripts != profileScripts
            || currentEnvVars != profileEnvVars
    }

    func logProfileStartupState() {
        guard let profile = selectedProfile else { return }

        if isCurrentProfileModified {
            ConsoleLogger.shared.log("Profile '\(profile.name)' has unsaved modifications on startup:", category: .profiles)
            for p in plugins where isPluginModified(p) {
                ConsoleLogger.shared.log("  - Plugin '\(p.name)': \(p.isEnabled ? "enabled" : "disabled") (saved: \(p.isEnabled ? "disabled" : "enabled"))", category: .profiles)
            }
            for s in scenery where isSceneryModified(s) {
                ConsoleLogger.shared.log("  - Scenery '\(s.name)': \(s.isEnabled ? "enabled" : "disabled") (saved: \(s.isEnabled ? "disabled" : "enabled"))", category: .profiles)
            }
            for a in aircraft where isAircraftModified(a) {
                ConsoleLogger.shared.log("  - Aircraft '\(a.name)': \(a.isEnabled ? "enabled" : "disabled") (saved: \(a.isEnabled ? "disabled" : "enabled"))", category: .profiles)
            }
            for l in luaScripts where isLuaScriptModified(l) {
                ConsoleLogger.shared.log("  - Lua Script '\(l.name)': \(l.isEnabled ? "enabled" : "disabled") (saved: \(l.isEnabled ? "disabled" : "enabled"))", category: .profiles)
            }
            for sc in activeScripts where isProfileScriptModified(sc) {
                let scriptName = URL(fileURLWithPath: sc.path).lastPathComponent
                ConsoleLogger.shared.log("  - Script '\(scriptName)': modified", category: .profiles)
            }
            for ev in activeEnvironmentVariables where isEnvVarModified(ev) {
                ConsoleLogger.shared.log("  - Env Var '\(ev.key)': modified", category: .profiles)
            }
        } else {
            ConsoleLogger.shared.log("Profile '\(profile.name)' active (clean)", category: .profiles)
        }
    }

    // MARK: - Initialization

    init() {
        self.storagePools = storagePoolService.loadStoragePools()
        ensureLauncherDataDirectories()

        // Load profiles & migrate legacy shellScriptPath if present
        var loadedProfiles = profileService.loadProfiles()
        for i in 0..<loadedProfiles.count {
            if loadedProfiles[i].scripts.isEmpty,
               let oldScript = loadedProfiles[i].shellScriptPath, !oldScript.isEmpty {
                let newScript = ProfileScript(path: oldScript, isEnabled: true)
                loadedProfiles[i].scripts.append(newScript)
            }
        }
        self.profiles = loadedProfiles

        if let savedPath = defaults.string(forKey: .xPlanePath) {
            let url = URL(fileURLWithPath: savedPath)
            if pathService.isDirectory(at: url) {
                self.xPlanePath = url

                if let savedIdString = defaults.string(forKey: .selectedProfileId),
                   let savedId = UUID(uuidString: savedIdString) {
                    isRestoringState = true
                    self.selectedProfileId = savedId
                    if let profile = profiles.first(where: { $0.id == savedId }) {
                        self.activeScripts = profile.scripts
                        self.activeEnvironmentVariables = profile.environmentVariables
                    }
                    isRestoringState = false
                }
            }
        }

        scanPlugins()
        scanScenery()
        scanAircraft()
        scanLuaScripts()
        refreshStoragePoolStats()

        self.scriptEnvironment = profileService.loadScriptEnvironment()
        self.sceneryGroups = profileService.loadSceneryGroups()
        self.enableCSLSupport = defaults.bool(forKey: .enableCSLSupport)
        self.enableCSLXP12Lights = defaults.bool(forKey: .enableCSLXP12Lights)
        self.enableNavdataSupport = defaults.bool(forKey: .enableNavdataSupport)
        self.hasCompletedWelcome = defaults.bool(forKey: .hasCompletedWelcome)

        logProfileStartupState()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVolumeChange()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVolumeChange()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVolumeChange()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didRenameVolumeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVolumeChange()
            }
        }

        isLoading = false
    }

    // MARK: - Directory & Persistence Helpers

    func ensureLauncherDataDirectories() {
        pathService.ensureDirectories(for: storagePools)
    }

    func savePath() {
        if let path = xPlanePath {
            defaults.set(path.path, forKey: .xPlanePath)
        }
    }

    func saveStoragePools() {
        storagePoolService.saveStoragePools(storagePools)
    }

    func addStoragePool(url: URL, name: String, isPrimary: Bool = false, defaultCategories: [AddonCategory] = []) {
        var newPools = storagePools
        if isPrimary {
            for i in 0..<newPools.count { newPools[i].isPrimary = false }
        }
        let pool = StoragePool(
            name: name,
            url: url,
            isPrimary: isPrimary || newPools.isEmpty,
            defaultCategories: defaultCategories
        )
        newPools.append(pool)
        self.storagePools = newPools
        pathService.ensureDirectories(for: pool.url)
        repairStaleLinks()
        rescanAll()
        refreshStoragePoolStats()
        ConsoleLogger.shared.log("Added storage pool '\(pool.name)' at \(pool.url.path)", category: .general)
    }

    func removeStoragePool(id: UUID) {
        guard let pool = storagePools.first(where: { $0.id == id }) else { return }
        storagePools.removeAll { $0.id == id }
        if !storagePools.isEmpty && !storagePools.contains(where: { $0.isPrimary }) {
            storagePools[0].isPrimary = true
        }
        saveStoragePools()
        repairStaleLinks()
        rescanAll()
        refreshStoragePoolStats()
        ConsoleLogger.shared.log("Removed storage pool '\(pool.name)'", category: .general)
    }

    func setPrimaryStoragePool(id: UUID) {
        for i in 0..<storagePools.count {
            storagePools[i].isPrimary = (storagePools[i].id == id)
        }
        saveStoragePools()
        refreshStoragePoolStats()
        if let primary = primaryStoragePool {
            ConsoleLogger.shared.log("Set '\(primary.name)' as primary storage pool", category: .general)
        }
    }

    func updateStoragePool(id: UUID, name: String, defaultCategories: [AddonCategory]) {
        if let index = storagePools.firstIndex(where: { $0.id == id }) {
            storagePools[index].name = name
            storagePools[index].defaultCategories = defaultCategories
            saveStoragePools()
            refreshStoragePoolStats()
        }
    }

    func refreshStoragePoolStats() {
        var stats: [UUID: StoragePoolStats] = [:]
        for pool in storagePools {
            stats[pool.id] = storagePoolService.calculateStats(for: pool)
        }
        self.storagePoolStats = stats
    }

    func rescanAll() {
        scanPlugins()
        scanScenery()
        scanAircraft()
        scanLuaScripts()
    }

    @MainActor
    func handleVolumeChange() {
        guard !isLoading else { return }
        refreshStoragePoolStats()
        repairStaleLinks()
        rescanAll()
    }

    func isPluginOffline(_ plugin: Plugin) -> Bool {
        if plugin.isOffline { return true }
        if let poolId = plugin.storagePoolId, let pool = storagePools.first(where: { $0.id == poolId }), !pool.isOnline {
            return true
        }
        if let sourceURL = plugin.sourceURL, !FileManager.default.fileExists(atPath: sourceURL.path) {
            return true
        }
        return false
    }

    func isSceneryOffline(_ item: Scenery) -> Bool {
        if item.isOffline { return true }
        if let poolId = item.storagePoolId, let pool = storagePools.first(where: { $0.id == poolId }), !pool.isOnline {
            return true
        }
        if let sourceURL = item.sourceURL, !FileManager.default.fileExists(atPath: sourceURL.path) {
            return true
        }
        return false
    }

    func isAircraftOffline(_ item: Aircraft) -> Bool {
        if item.isOffline { return true }
        if let poolId = item.storagePoolId, let pool = storagePools.first(where: { $0.id == poolId }), !pool.isOnline {
            return true
        }
        if let sourceURL = item.sourceURL, !FileManager.default.fileExists(atPath: sourceURL.path) {
            return true
        }
        return false
    }

    func isLuaScriptOffline(_ item: LuaScript) -> Bool {
        if item.isOffline { return true }
        if let poolId = item.storagePoolId, let pool = storagePools.first(where: { $0.id == poolId }), !pool.isOnline {
            return true
        }
        if let sourceURL = item.sourceURL, !FileManager.default.fileExists(atPath: sourceURL.path) {
            return true
        }
        return false
    }

    func saveScriptEnvironment() {
        profileService.saveScriptEnvironment(scriptEnvironment)
    }

    func saveSceneryGroups() {
        profileService.saveSceneryGroups(sceneryGroups)
    }

    // MARK: - Link Repair

    /// Repoints add-on links that broke because their source folder moved, so a
    /// changed central data folder keeps the current selection working instead of
    /// leaving every enabled add-on dangling.
    func repairStaleLinks() {
        guard let xPlanePath = xPlanePath else { return }

        symlinkService.repairStaleLinks(
            in: pathService.pluginsTargetFolder(for: xPlanePath),
            using: symlinkService.linkSources(in: storagePools, subfolder: .plugins)
        )

        symlinkService.repairStaleLinks(
            in: pathService.aircraftTargetFolder(for: xPlanePath),
            using: symlinkService.linkSources(in: storagePools, subfolder: .aircraft)
        )

        symlinkService.repairStaleLinks(
            in: pathService.customSceneryFolder(for: xPlanePath),
            using: symlinkService.linkSources(in: storagePools, subfolder: .scenery)
        )

        if let targetFolder = flyWithLuaScriptsFolder {
            symlinkService.repairStaleLinks(
                in: targetFolder,
                using: symlinkService.luaScriptLinkSources(in: storagePools)
            )
        }
        if let modulesFolder = flyWithLuaModulesFolder {
            symlinkService.repairStaleLinks(
                in: modulesFolder,
                using: symlinkService.luaModuleLinkSources(in: storagePools)
            )
        }
    }

    // MARK: - Scanning

    func scanPlugins() {
        guard let xPlanePath = xPlanePath else {
            plugins = []
            return
        }

        let targetFolder = pathService.pluginsTargetFolder(for: xPlanePath)
        do {
            self.plugins = try symlinkService.scanPlugins(
                storagePools: storagePools,
                targetFolder: targetFolder,
                knownPlugins: plugins
            )
            ConsoleLogger.shared.log("Scanned \(self.plugins.count) plugins (\(self.plugins.filter { $0.isEnabled }.count) enabled, \(self.plugins.filter { $0.isOffline }.count) offline)", category: .plugins)
        } catch {
            self.lastErrorMessage = "Error scanning plugins: \(error.localizedDescription)"
            ConsoleLogger.shared.log("Error scanning plugins: \(error.localizedDescription)", category: .plugins, level: .error)
        }
    }

    func scanAircraft() {
        guard let xPlanePath = xPlanePath else {
            aircraft = []
            return
        }

        let targetFolder = pathService.aircraftTargetFolder(for: xPlanePath)
        do {
            self.aircraft = try symlinkService.scanAircraft(
                storagePools: storagePools,
                targetFolder: targetFolder,
                knownAircraft: aircraft
            )
            ConsoleLogger.shared.log("Scanned \(self.aircraft.count) aircraft (\(self.aircraft.filter { $0.isEnabled }.count) enabled, \(self.aircraft.filter { $0.isOffline }.count) offline)", category: .aircraft)
        } catch {
            self.lastErrorMessage = "Error scanning aircraft: \(error.localizedDescription)"
            ConsoleLogger.shared.log("Error scanning aircraft: \(error.localizedDescription)", category: .aircraft, level: .error)
        }
    }

    func scanLuaScripts() {
        let targetFolder = flyWithLuaScriptsFolder
        let modulesFolder = flyWithLuaModulesFolder
        do {
            self.luaScripts = try symlinkService.scanLuaScripts(
                storagePools: storagePools,
                targetFolder: targetFolder,
                modulesTargetFolder: modulesFolder,
                knownScripts: luaScripts
            )
            ConsoleLogger.shared.log("Scanned \(self.luaScripts.count) Lua scripts (\(self.luaScripts.filter { $0.isEnabled }.count) enabled, \(self.luaScripts.filter { $0.isOffline }.count) offline)", category: .lua)
        } catch {
            self.lastErrorMessage = "Error scanning Lua scripts: \(error.localizedDescription)"
            ConsoleLogger.shared.log("Error scanning Lua scripts: \(error.localizedDescription)", category: .lua, level: .error)
        }
    }

    func scanScenery() {
        guard let xPlanePath = xPlanePath else {
            scenery = []
            return
        }

        let customSceneryURL = pathService.customSceneryFolder(for: xPlanePath)
        let iniURL = pathService.sceneryPacksIniURL(for: xPlanePath)
        do {
            self.scenery = try sceneryService.scanScenery(
                customSceneryFolder: customSceneryURL,
                storagePools: storagePools,
                iniURL: iniURL,
                knownScenery: scenery
            )
            ConsoleLogger.shared.log("Scanned \(self.scenery.count) scenery packs (\(self.scenery.filter { $0.isEnabled }.count) enabled, \(self.scenery.filter { $0.isOffline }.count) offline)", category: .scenery)
        } catch {
            self.lastErrorMessage = "Error scanning Custom Scenery: \(error.localizedDescription)"
            ConsoleLogger.shared.log("Error scanning Custom Scenery: \(error.localizedDescription)", category: .scenery, level: .error)
        }
    }

    func saveSceneryOrder() {
        guard let xPlanePath = xPlanePath else { return }
        let customSceneryURL = pathService.customSceneryFolder(for: xPlanePath)
        let iniURL = pathService.sceneryPacksIniURL(for: xPlanePath)

        do {
            try sceneryService.saveSceneryOrder(scenery: scenery, customSceneryFolder: customSceneryURL, iniURL: iniURL)
            ConsoleLogger.shared.log("Saved scenery_packs.ini order with \(scenery.count) packs", category: .scenery)
        } catch {
            self.lastErrorMessage = "Failed to save scenery_packs.ini: \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to save scenery_packs.ini: \(error.localizedDescription)", category: .scenery, level: .error)
        }
    }

    // MARK: - Toggles

    private func findSourceURL(folderName: String, subfolder: DataSubfolder) -> URL? {
        for pool in storagePools where pool.isOnline {
            let sub = PathService.shared.dataFolder(subfolder, in: pool.url).appendingPathComponent(folderName)
            if FileManager.default.fileExists(atPath: sub.path) {
                return sub
            }
        }
        return nil
    }

    func togglePlugin(_ plugin: Plugin) {
        guard !isPluginOffline(plugin) else {
            self.lastErrorMessage = "Cannot toggle offline plugin '\(plugin.name)'. The storage volume is not mounted."
            return
        }
        guard let xPlanePath = xPlanePath else { return }
        guard let sourceURL = plugin.sourceURL ?? findSourceURL(folderName: plugin.folderName, subfolder: .plugins) else {
            self.lastErrorMessage = "Cannot find source files for plugin '\(plugin.name)'."
            return
        }

        let targetFolder = pathService.pluginsTargetFolder(for: xPlanePath)
        let newEnabled = !plugin.isEnabled
        do {
            try symlinkService.setPluginEnabled(folderName: plugin.folderName, enabled: newEnabled, sourceURL: sourceURL, targetFolder: targetFolder)
            if let index = plugins.firstIndex(where: { $0.id == plugin.id }) {
                plugins[index].isEnabled = newEnabled
                ConsoleLogger.shared.log("\(newEnabled ? "Enabled" : "Disabled") plugin '\(plugin.name)'", category: .plugins)

                if let profile = selectedProfile {
                    if isPluginModified(plugins[index]) {
                        ConsoleLogger.shared.log("Profile '\(profile.name)': plugin '\(plugin.name)' is now \(newEnabled ? "enabled" : "disabled") (differs from saved profile)", category: .profiles)
                    } else {
                        ConsoleLogger.shared.log("Profile '\(profile.name)': plugin '\(plugin.name)' restored to saved profile state", category: .profiles)
                    }
                }
            }
        } catch {
            self.lastErrorMessage = "Failed to \(plugin.isEnabled ? "disable" : "enable") plugin '\(plugin.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to \(plugin.isEnabled ? "disable" : "enable") plugin '\(plugin.name)': \(error.localizedDescription)", category: .plugins, level: .error)
        }
    }

    func toggleAircraft(_ item: Aircraft) {
        guard !isAircraftOffline(item) else {
            self.lastErrorMessage = "Cannot toggle offline aircraft '\(item.name)'. The storage volume is not mounted."
            return
        }
        guard let xPlanePath = xPlanePath else { return }
        guard let sourceURL = item.sourceURL ?? findSourceURL(folderName: item.folderName, subfolder: .aircraft) else {
            self.lastErrorMessage = "Cannot find source files for aircraft '\(item.name)'."
            return
        }

        let targetFolder = pathService.aircraftTargetFolder(for: xPlanePath)
        let newEnabled = !item.isEnabled

        do {
            try symlinkService.setAircraftEnabled(folderName: item.folderName, enabled: newEnabled, sourceURL: sourceURL, targetFolder: targetFolder)
            if let index = aircraft.firstIndex(where: { $0.id == item.id }) {
                aircraft[index].isEnabled = newEnabled
                ConsoleLogger.shared.log("\(newEnabled ? "Enabled" : "Disabled") aircraft '\(item.name)'", category: .aircraft)

                if let profile = selectedProfile {
                    if isAircraftModified(aircraft[index]) {
                        ConsoleLogger.shared.log("Profile '\(profile.name)': aircraft '\(item.name)' is now \(newEnabled ? "enabled" : "disabled") (differs from saved profile)", category: .profiles)
                    } else {
                        ConsoleLogger.shared.log("Profile '\(profile.name)': aircraft '\(item.name)' restored to saved profile state", category: .profiles)
                    }
                }
            }
        } catch {
            self.lastErrorMessage = "Failed to \(item.isEnabled ? "disable" : "enable") aircraft '\(item.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to \(item.isEnabled ? "disable" : "enable") aircraft '\(item.name)': \(error.localizedDescription)", category: .aircraft, level: .error)
        }
    }

    func toggleLuaScript(_ item: LuaScript) {
        guard !isLuaScriptOffline(item) else {
            self.lastErrorMessage = "Cannot toggle offline Lua script '\(item.name)'. The storage volume is not mounted."
            return
        }
        guard let targetFolder = flyWithLuaScriptsFolder else { return }
        guard let sourceURL = item.sourceURL ?? findSourceURL(folderName: item.folderName, subfolder: .luaScripts) else {
            self.lastErrorMessage = "Cannot find source files for Lua script '\(item.name)'."
            return
        }

        let modulesFolder = flyWithLuaModulesFolder
        let newEnabled = !item.isEnabled

        do {
            try symlinkService.setLuaScriptEnabled(item: item, enabled: newEnabled, sourceURL: sourceURL, targetFolder: targetFolder, modulesTargetFolder: modulesFolder)
            if let index = luaScripts.firstIndex(where: { $0.id == item.id }) {
                luaScripts[index].isEnabled = newEnabled
                ConsoleLogger.shared.log("\(newEnabled ? "Enabled" : "Disabled") Lua script '\(item.name)'", category: .lua)

                if let profile = selectedProfile {
                    if isLuaScriptModified(luaScripts[index]) {
                        ConsoleLogger.shared.log("Profile '\(profile.name)': Lua script '\(item.name)' is now \(newEnabled ? "enabled" : "disabled") (differs from saved profile)", category: .profiles)
                    } else {
                        ConsoleLogger.shared.log("Profile '\(profile.name)': Lua script '\(item.name)' restored to saved profile state", category: .profiles)
                    }
                }
            }
        } catch {
            self.lastErrorMessage = "Failed to \(item.isEnabled ? "disable" : "enable") Lua script '\(item.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to \(item.isEnabled ? "disable" : "enable") Lua script '\(item.name)': \(error.localizedDescription)", category: .lua, level: .error)
        }
    }

    func toggleScenery(_ item: Scenery) {
        guard !isSceneryOffline(item) else {
            self.lastErrorMessage = "Cannot toggle offline scenery '\(item.name)'. The storage volume is not mounted."
            return
        }
        guard let index = scenery.firstIndex(where: { $0.id == item.id }) else { return }
        guard item.isToggleable else { return }

        var newItem = scenery[index]
        let wasEnabled = newItem.isEnabled

        if !wasEnabled {
            if let xPlanePath = xPlanePath {
                let customScenery = pathService.customSceneryFolder(for: xPlanePath)
                if let sourceURL = newItem.sourceURL ?? findSourceURL(folderName: newItem.folderName, subfolder: .scenery) {
                    do {
                        try sceneryService.linkScenery(folderName: newItem.folderName, sourceURL: sourceURL, customSceneryFolder: customScenery)
                        newItem.isManaged = true
                    } catch {
                        self.lastErrorMessage = "Failed to enable scenery '\(newItem.name)': \(error.localizedDescription)"
                        ConsoleLogger.shared.log("Failed to enable scenery '\(newItem.name)': \(error.localizedDescription)", category: .scenery, level: .error)
                        return
                    }
                }
            }
            newItem.isEnabled = true
            ConsoleLogger.shared.log("Enabled scenery '\(newItem.name)'", category: .scenery)
        } else {
            newItem.isEnabled = false
            ConsoleLogger.shared.log("Disabled scenery '\(newItem.name)'", category: .scenery)
        }

        scenery[index] = newItem
        saveSceneryOrder()

        if let profile = selectedProfile {
            if isSceneryModified(newItem) {
                ConsoleLogger.shared.log("Profile '\(profile.name)': scenery '\(newItem.name)' is now \(newItem.isEnabled ? "enabled" : "disabled") (differs from saved profile)", category: .profiles)
            } else {
                ConsoleLogger.shared.log("Profile '\(profile.name)': scenery '\(newItem.name)' restored to saved profile state", category: .profiles)
            }
        }
    }

    // MARK: - Scenery Grouping & Reordering

    func createGroup(name: String, with items: [Scenery]) {
        let result = sceneryService.createGroup(name: name, items: items, existingGroups: sceneryGroups, existingScenery: scenery)
        self.sceneryGroups = result.groups
        self.scenery = result.scenery
        saveSceneryOrder()
    }

    func deleteGroup(_ group: SceneryGroup) {
        self.sceneryGroups = sceneryService.deleteGroup(group: group, existingGroups: sceneryGroups)
    }

    func toggleGroup(_ group: SceneryGroup, isEnabled: Bool) {
        for folderName in group.childFolderNames {
            if let index = scenery.firstIndex(where: { $0.folderName == folderName }) {
                let item = scenery[index]
                if item.isEnabled != isEnabled {
                    toggleScenery(item)
                }
            }
        }
    }

    func renameGroup(_ group: SceneryGroup, newName: String) {
        if let index = sceneryGroups.firstIndex(where: { $0.id == group.id }) {
            sceneryGroups[index].name = newName
        }
    }

    func removeFromGroup(_ item: Scenery) {
        self.sceneryGroups = sceneryService.removeFromGroup(sceneryItem: item, existingGroups: sceneryGroups)
    }

    func moveScenery(from source: IndexSet, to destination: Int) {
        scenery.move(fromOffsets: source, toOffset: destination)
        saveSceneryOrder()
        ConsoleLogger.shared.log("Reordered scenery packs", category: .scenery)
    }

    func moveSceneryToGroup(items: [Scenery], group: SceneryGroup) {
        guard !items.isEmpty else { return }
        let currentMembers = scenery.filter { group.childFolderNames.contains($0.folderName) }
        let itemFolders = Set(items.map { $0.folderName })

        for (idx, _) in sceneryGroups.enumerated() {
            sceneryGroups[idx].childFolderNames.removeAll(where: { itemFolders.contains($0) })
        }

        if let index = sceneryGroups.firstIndex(where: { $0.id == group.id }) {
            sceneryGroups[index].childFolderNames.append(contentsOf: itemFolders)

            var newScenery = scenery
            newScenery.removeAll(where: { itemFolders.contains($0.folderName) })

            var insertAt = newScenery.count
            if let lastMember = currentMembers.last,
               let targetIndex = newScenery.firstIndex(where: { $0.id == lastMember.id }) {
                insertAt = targetIndex + 1
            } else if let firstItem = items.first,
                      let originalIndex = scenery.firstIndex(where: { $0.id == firstItem.id }) {
                insertAt = min(originalIndex, newScenery.count)
            }

            newScenery.insert(contentsOf: items, at: insertAt)
            self.scenery = newScenery
            saveSceneryOrder()
        }
    }

    func moveSceneryToGroup(_ sceneryItem: Scenery, group: SceneryGroup) {
        let currentMembers = scenery.filter { group.childFolderNames.contains($0.folderName) }
        removeFromGroup(sceneryItem)

        if let index = sceneryGroups.firstIndex(where: { $0.id == group.id }) {
            sceneryGroups[index].childFolderNames.append(sceneryItem.folderName)

            if let lastMember = currentMembers.last,
               let targetIndex = scenery.firstIndex(where: { $0.id == lastMember.id }),
               let currentIndex = scenery.firstIndex(where: { $0.id == sceneryItem.id }) {

                var newScenery = scenery
                let item = newScenery.remove(at: currentIndex)

                var insertAt = targetIndex
                if currentIndex < targetIndex {
                    if let reFoundIndex = newScenery.firstIndex(where: { $0.id == lastMember.id }) {
                        insertAt = reFoundIndex + 1
                    }
                } else {
                    if let reFoundIndex = newScenery.firstIndex(where: { $0.id == lastMember.id }) {
                        insertAt = reFoundIndex + 1
                    }
                }

                insertAt = min(insertAt, newScenery.count)
                newScenery.insert(item, at: insertAt)
                self.scenery = newScenery
                saveSceneryOrder()
            } else {
                saveSceneryOrder()
            }
        }
    }

    func moveScenery(items: [Scenery], relativeTo target: Scenery) {
        guard !items.isEmpty else { return }
        let validItems = items.filter { $0.id != target.id }
        guard !validItems.isEmpty else { return }

        let itemFolders = Set(validItems.map { $0.folderName })
        for (idx, _) in sceneryGroups.enumerated() {
            sceneryGroups[idx].childFolderNames.removeAll(where: { itemFolders.contains($0) })
        }

        if let targetGroup = sceneryGroups.first(where: { $0.childFolderNames.contains(target.folderName) }),
           let idx = sceneryGroups.firstIndex(where: { $0.id == targetGroup.id }) {
            sceneryGroups[idx].childFolderNames.append(contentsOf: itemFolders)
        }

        var newScenery = scenery
        newScenery.removeAll(where: { itemFolders.contains($0.folderName) })

        if let newTargetIndex = newScenery.firstIndex(where: { $0.id == target.id }) {
            let insertIndex = min(newTargetIndex + 1, newScenery.count)
            newScenery.insert(contentsOf: validItems, at: insertIndex)
            self.scenery = newScenery
            saveSceneryOrder()
        }
    }

    func moveScenery(_ item: Scenery, relativeTo target: Scenery) {
        guard item.id != target.id else { return }
        removeFromGroup(item)

        if let targetGroup = sceneryGroups.first(where: { $0.childFolderNames.contains(target.folderName) }),
           let idx = sceneryGroups.firstIndex(where: { $0.id == targetGroup.id }) {
            sceneryGroups[idx].childFolderNames.append(item.folderName)
        }

        if let _ = scenery.firstIndex(where: { $0.id == target.id }),
           let currentIndex = scenery.firstIndex(where: { $0.id == item.id }) {
            var newScenery = scenery
            let movingItem = newScenery.remove(at: currentIndex)

            if let newTargetIndex = newScenery.firstIndex(where: { $0.id == target.id }) {
                let insertIndex = min(newTargetIndex + 1, newScenery.count)
                newScenery.insert(movingItem, at: insertIndex)
                self.scenery = newScenery
                saveSceneryOrder()
            }
        }
    }

    // MARK: - Profile Management

    func createProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newProfile = PluginProfile(
            name: trimmed,
            pluginFolderNames: plugins.filter { $0.isEnabled }.map { $0.folderName },
            sceneryFolderNames: scenery.filter { $0.isEnabled }.map { $0.folderName },
            aircraftFolderNames: aircraft.filter { $0.isEnabled }.map { $0.folderName },
            luaScriptFolderNames: luaScripts.filter { $0.isEnabled }.map { $0.folderName },
            scripts: activeScripts,
            environmentVariables: activeEnvironmentVariables
        )

        profiles.append(newProfile)
        profileService.saveProfiles(profiles)
        selectedProfileId = newProfile.id
        ConsoleLogger.shared.log("Created profile '\(trimmed)'", category: .profiles)
    }

    func saveProfile(name: String) {
        createProfile(name: name)
    }

    func saveCurrentStateToProfile(_ profile: PluginProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }

        var updatedProfile = profiles[index]
        updatedProfile.pluginFolderNames = plugins.filter { $0.isEnabled }.map { $0.folderName }
        updatedProfile.sceneryFolderNames = scenery.filter { $0.isEnabled }.map { $0.folderName }
        updatedProfile.aircraftFolderNames = aircraft.filter { $0.isEnabled }.map { $0.folderName }
        updatedProfile.luaScriptFolderNames = luaScripts.filter { $0.isEnabled }.map { $0.folderName }
        updatedProfile.scripts = activeScripts
        updatedProfile.environmentVariables = activeEnvironmentVariables

        profiles[index] = updatedProfile
        profileService.saveProfiles(profiles)
        ConsoleLogger.shared.log("Saved state to profile '\(updatedProfile.name)'", category: .profiles)
    }

    func revertProfile(_ profile: PluginProfile) {
        applyProfile(profile)
        self.activeScripts = profile.scripts
        self.activeEnvironmentVariables = profile.environmentVariables
        ConsoleLogger.shared.log("Reverted profile '\(profile.name)' to saved state", category: .profiles)
    }

    func updateProfile(_ profile: PluginProfile) {
        let enabledPlugins = plugins.filter { $0.isEnabled }.map { $0.folderName }
        let enabledScenery = scenery.filter { $0.isEnabled }.map { $0.folderName }
        let enabledAircraft = aircraft.filter { $0.isEnabled }.map { $0.folderName }
        let enabledLua = luaScripts.filter { $0.isEnabled }.map { $0.folderName }

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = PluginProfile(
                id: profile.id,
                name: profile.name,
                pluginFolderNames: enabledPlugins,
                sceneryFolderNames: enabledScenery,
                aircraftFolderNames: enabledAircraft,
                luaScriptFolderNames: enabledLua,
                scripts: activeScripts,
                environmentVariables: activeEnvironmentVariables
            )
            profileService.saveProfiles(profiles)
            ConsoleLogger.shared.log("Updated profile '\(profile.name)'", category: .profiles)
        }
    }

    func deleteProfile(_ profile: PluginProfile) {
        profiles.removeAll { $0.id == profile.id }
        if selectedProfileId == profile.id {
            selectedProfileId = profiles.first?.id
            if let first = profiles.first {
                applyProfile(first)
            }
        }
        profileService.saveProfiles(profiles)
        ConsoleLogger.shared.log("Deleted profile '\(profile.name)'", category: .profiles)
    }

    func duplicateProfile(_ profile: PluginProfile) {
        let copy = profileService.duplicateProfile(profile)
        profiles.append(copy)
        profileService.saveProfiles(profiles)
        selectedProfileId = copy.id
        applyProfile(copy)
        ConsoleLogger.shared.log("Duplicated profile '\(profile.name)' as '\(copy.name)'", category: .profiles)
    }

    func renameProfile(_ profile: PluginProfile, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let oldName = profiles[index].name
        profiles[index].name = trimmed
        profileService.saveProfiles(profiles)
        ConsoleLogger.shared.log("Renamed profile '\(oldName)' to '\(trimmed)'", category: .profiles)
    }

    func reorderProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        profileService.saveProfiles(profiles)
        ConsoleLogger.shared.log("Reordered profiles", category: .profiles)
    }

    func sortProfiles(by option: ProfileSortOption) {
        profiles = profileService.sortProfiles(profiles, by: option)
        profileService.saveProfiles(profiles)
        ConsoleLogger.shared.log("Sorted profiles by \(option.rawValue)", category: .profiles)
    }

    func exportProfile(_ profile: PluginProfile, to destinationURL: URL) throws {
        let data = try profileService.exportProfile(profile)
        try data.write(to: destinationURL, options: .atomic)
        ConsoleLogger.shared.log("Exported profile '\(profile.name)' to \(destinationURL.lastPathComponent)", category: .profiles)
    }

    func exportAllProfiles(to destinationURL: URL) throws {
        let data = try profileService.exportAllProfiles(profiles)
        try data.write(to: destinationURL, options: .atomic)
        ConsoleLogger.shared.log("Exported all profiles to \(destinationURL.lastPathComponent)", category: .profiles)
    }

    @discardableResult
    func importProfiles(from sourceURL: URL) throws -> [PluginProfile] {
        let data = try Data(contentsOf: sourceURL)
        let imported = try profileService.importProfiles(from: data, existingProfiles: profiles)
        profiles.append(contentsOf: imported)
        profileService.saveProfiles(profiles)
        if let first = imported.first {
            selectedProfileId = first.id
        }
        ConsoleLogger.shared.log("Imported \(imported.count) profile(s) from \(sourceURL.lastPathComponent)", category: .profiles)
        return imported
    }

    // MARK: - Missing & Offline Add-ons Detection

    func offlineAddons(for profile: PluginProfile) -> [AddonCategory: [String]] {
        var offline: [AddonCategory: [String]] = [:]

        let offlinePlugins = plugins.filter { isPluginOffline($0) && profile.pluginFolderNames.contains($0.folderName) }.map { $0.folderName }
        if !offlinePlugins.isEmpty { offline[.plugins] = offlinePlugins }

        let offlineScenery = scenery.filter { isSceneryOffline($0) && profile.sceneryFolderNames.contains($0.folderName) }.map { $0.folderName }
        if !offlineScenery.isEmpty { offline[.scenery] = offlineScenery }

        let offlineAircraft = aircraft.filter { isAircraftOffline($0) && profile.aircraftFolderNames.contains($0.folderName) }.map { $0.folderName }
        if !offlineAircraft.isEmpty { offline[.aircraft] = offlineAircraft }

        let offlineLua = luaScripts.filter { isLuaScriptOffline($0) && profile.luaScriptFolderNames.contains($0.folderName) }.map { $0.folderName }
        if !offlineLua.isEmpty { offline[.luaScripts] = offlineLua }

        return offline
    }

    func missingAddons(for profile: PluginProfile) -> [AddonCategory: [String]] {
        var missing: [AddonCategory: [String]] = [:]

        let installedPlugins = Set(plugins.map { $0.folderName })
        let missingPlugins = profile.pluginFolderNames.filter { !installedPlugins.contains($0) }
        if !missingPlugins.isEmpty {
            missing[.plugins] = missingPlugins
        }

        let installedScenery = Set(scenery.map { $0.folderName })
        let missingScenery = profile.sceneryFolderNames.filter { !installedScenery.contains($0) }
        if !missingScenery.isEmpty {
            missing[.scenery] = missingScenery
        }

        let installedAircraft = Set(aircraft.map { $0.folderName })
        let missingAircraft = profile.aircraftFolderNames.filter { !installedAircraft.contains($0) }
        if !missingAircraft.isEmpty {
            missing[.aircraft] = missingAircraft
        }

        let installedLua = Set(luaScripts.map { $0.folderName })
        let missingLua = profile.luaScriptFolderNames.filter { !installedLua.contains($0) }
        if !missingLua.isEmpty {
            missing[.luaScripts] = missingLua
        }

        return missing
    }

    func hasMissingAddons(for profile: PluginProfile) -> Bool {
        !missingAddons(for: profile).isEmpty
    }

    func activateProfile(_ profile: PluginProfile) {
        selectedProfileId = profile.id
        applyProfile(profile)
    }

    func applyProfile(_ profile: PluginProfile) {
        ConsoleLogger.shared.log("Applying profile '\(profile.name)'", category: .profiles)
        for index in plugins.indices {
            let shouldBeEnabled = profile.pluginFolderNames.contains(plugins[index].folderName)
            if plugins[index].isEnabled != shouldBeEnabled && !plugins[index].isOffline {
                togglePlugin(plugins[index])
            }
        }

        for index in scenery.indices {
            let shouldBeEnabled = profile.sceneryFolderNames.contains(scenery[index].folderName)
            if scenery[index].isEnabled != shouldBeEnabled && !scenery[index].isOffline {
                toggleScenery(scenery[index])
            }
        }

        for index in aircraft.indices {
            let shouldBeEnabled = profile.aircraftFolderNames.contains(aircraft[index].folderName)
            if aircraft[index].isEnabled != shouldBeEnabled && !aircraft[index].isOffline {
                toggleAircraft(aircraft[index])
            }
        }

        for index in luaScripts.indices {
            let shouldBeEnabled = profile.luaScriptFolderNames.contains(luaScripts[index].folderName)
            if luaScripts[index].isEnabled != shouldBeEnabled && !luaScripts[index].isOffline {
                toggleLuaScript(luaScripts[index])
            }
        }

        self.activeScripts = profile.scripts
        self.activeEnvironmentVariables = profile.environmentVariables
    }

    // MARK: - Add-on Deletion

    private func removeAddonFromAllProfiles(folderName: String, category: AddonCategory) {
        var modified = false
        for i in 0..<profiles.count {
            switch category {
            case .plugins:
                if profiles[i].pluginFolderNames.contains(folderName) {
                    profiles[i].pluginFolderNames.removeAll { $0 == folderName }
                    modified = true
                }
            case .aircraft:
                if profiles[i].aircraftFolderNames.contains(folderName) {
                    profiles[i].aircraftFolderNames.removeAll { $0 == folderName }
                    modified = true
                }
            case .scenery:
                if profiles[i].sceneryFolderNames.contains(folderName) {
                    profiles[i].sceneryFolderNames.removeAll { $0 == folderName }
                    modified = true
                }
            case .luaScripts:
                if profiles[i].luaScriptFolderNames.contains(folderName) {
                    profiles[i].luaScriptFolderNames.removeAll { $0 == folderName }
                    modified = true
                }
            }
        }
        if modified {
            profileService.saveProfiles(profiles)
        }
    }

    func deletePlugin(_ plugin: Plugin) {
        guard !isPluginOffline(plugin) else {
            self.lastErrorMessage = "Cannot delete '\(plugin.name)' because its storage drive is currently disconnected."
            return
        }

        do {
            if let xPlanePath = xPlanePath {
                let targetFolder = pathService.pluginsTargetFolder(for: xPlanePath)
                let cleanName = try? PathSecurity.sanitizePathComponent(plugin.folderName)
                if let clean = cleanName,
                   let linkURL = try? PathSecurity.validateSubpath(relativePath: clean, within: targetFolder) {
                    try? FileManager.default.removeItem(at: linkURL)
                }
            }

            if let sourceURL = plugin.sourceURL ?? findSourceURL(folderName: plugin.folderName, subfolder: .plugins) {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.removeItem(at: sourceURL)
                }
            }

            removeAddonFromAllProfiles(folderName: plugin.folderName, category: .plugins)
            scanPlugins()
            refreshStoragePoolStats()
            ConsoleLogger.shared.log("Deleted plugin '\(plugin.name)'", category: .plugins)
        } catch {
            self.lastErrorMessage = "Failed to delete plugin '\(plugin.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to delete plugin '\(plugin.name)': \(error.localizedDescription)", category: .plugins, level: .error)
        }
    }

    func deleteAircraft(_ item: Aircraft) {
        guard !isAircraftOffline(item) else {
            self.lastErrorMessage = "Cannot delete '\(item.name)' because its storage drive is currently disconnected."
            return
        }

        do {
            if let xPlanePath = xPlanePath {
                let targetFolder = pathService.aircraftTargetFolder(for: xPlanePath)
                let cleanName = try? PathSecurity.sanitizePathComponent(item.folderName)
                if let clean = cleanName,
                   let linkURL = try? PathSecurity.validateSubpath(relativePath: clean, within: targetFolder) {
                    try? FileManager.default.removeItem(at: linkURL)
                }
            }

            if let sourceURL = item.sourceURL ?? findSourceURL(folderName: item.folderName, subfolder: .aircraft) {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.removeItem(at: sourceURL)
                }
            }

            removeAddonFromAllProfiles(folderName: item.folderName, category: .aircraft)
            scanAircraft()
            refreshStoragePoolStats()
            ConsoleLogger.shared.log("Deleted aircraft '\(item.name)'", category: .aircraft)
        } catch {
            self.lastErrorMessage = "Failed to delete aircraft '\(item.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to delete aircraft '\(item.name)': \(error.localizedDescription)", category: .aircraft, level: .error)
        }
    }

    func deleteLuaScript(_ item: LuaScript) {
        guard !isLuaScriptOffline(item) else {
            self.lastErrorMessage = "Cannot delete '\(item.name)' because its storage drive is currently disconnected."
            return
        }

        do {
            if let targetFolder = flyWithLuaScriptsFolder, let sourceURL = item.sourceURL ?? findSourceURL(folderName: item.folderName, subfolder: .luaScripts) {
                let modulesFolder = flyWithLuaModulesFolder
                try? symlinkService.setLuaScriptEnabled(item: item, enabled: false, sourceURL: sourceURL, targetFolder: targetFolder, modulesTargetFolder: modulesFolder)
            }

            if let sourceURL = item.sourceURL ?? findSourceURL(folderName: item.folderName, subfolder: .luaScripts) {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.removeItem(at: sourceURL)
                }
            }

            removeAddonFromAllProfiles(folderName: item.folderName, category: .luaScripts)
            scanLuaScripts()
            refreshStoragePoolStats()
            ConsoleLogger.shared.log("Deleted Lua script '\(item.name)'", category: .lua)
        } catch {
            self.lastErrorMessage = "Failed to delete Lua script '\(item.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to delete Lua script '\(item.name)': \(error.localizedDescription)", category: .lua, level: .error)
        }
    }

    func deleteScenery(_ item: Scenery) {
        guard item.isManaged else {
            self.lastErrorMessage = "Cannot delete unmanaged scenery '\(item.name)'."
            return
        }
        guard !isSceneryOffline(item) else {
            self.lastErrorMessage = "Cannot delete '\(item.name)' because its storage drive is currently disconnected."
            return
        }

        do {
            if let xPlanePath = xPlanePath {
                let customScenery = pathService.customSceneryFolder(for: xPlanePath)
                try? sceneryService.unlinkScenery(folderName: item.folderName, customSceneryFolder: customScenery)
            }

            if let sourceURL = item.sourceURL ?? findSourceURL(folderName: item.folderName, subfolder: .scenery) {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.removeItem(at: sourceURL)
                }
            }

            removeFromGroup(item)
            scenery.removeAll { $0.id == item.id }
            saveSceneryOrder()
            removeAddonFromAllProfiles(folderName: item.folderName, category: .scenery)
            scanScenery()
            refreshStoragePoolStats()
            ConsoleLogger.shared.log("Deleted scenery '\(item.name)'", category: .scenery)
        } catch {
            self.lastErrorMessage = "Failed to delete scenery '\(item.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to delete scenery '\(item.name)': \(error.localizedDescription)", category: .scenery, level: .error)
        }
    }

    // MARK: - Script Management

    func addScript(name: String, path: String) {
        let newScript = ProfileScript(path: path, isEnabled: true)
        activeScripts.append(newScript)
        if let profile = selectedProfile {
            ConsoleLogger.shared.log("Profile '\(profile.name)': added script '\(name)'", category: .profiles)
        }
    }

    func deleteScript(_ script: ProfileScript) {
        let name = URL(fileURLWithPath: script.path).lastPathComponent
        activeScripts.removeAll { $0.id == script.id || $0.path == script.path }
        if let profile = selectedProfile {
            ConsoleLogger.shared.log("Profile '\(profile.name)': deleted script '\(name)'", category: .profiles)
        }
    }

    func toggleScript(_ script: ProfileScript) {
        if let index = activeScripts.firstIndex(where: { $0.id == script.id || $0.path == script.path }) {
            activeScripts[index].isEnabled.toggle()
            let name = URL(fileURLWithPath: script.path).lastPathComponent
            let isEnabled = activeScripts[index].isEnabled
            if let profile = selectedProfile {
                ConsoleLogger.shared.log("Profile '\(profile.name)': \(isEnabled ? "enabled" : "disabled") script '\(name)'", category: .profiles)
            }
        }
    }

    // MARK: - Profile Environment Variables

    func addProfileEnvVar(key: String = "NEW_VAR", value: String = "VALUE") {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        let newVar = ScriptEnvVar(key: trimmedKey, value: value)
        activeEnvironmentVariables.append(newVar)
        if let profile = selectedProfile {
            ConsoleLogger.shared.log("Profile '\(profile.name)': added environment variable '\(trimmedKey)'", category: .profiles)
        }
    }

    func deleteProfileEnvVar(id: UUID) {
        if let index = activeEnvironmentVariables.firstIndex(where: { $0.id == id }) {
            let key = activeEnvironmentVariables[index].key
            activeEnvironmentVariables.remove(at: index)
            if let profile = selectedProfile {
                ConsoleLogger.shared.log("Profile '\(profile.name)': deleted environment variable '\(key)'", category: .profiles)
            }
        }
    }

    // MARK: - Launching

    func launchXPlane() {
        guard let xPlanePath = xPlanePath else { return }

        let profileName = profiles.first(where: { $0.id == selectedProfileId })?.name ?? "Default"
        ConsoleLogger.shared.log("Initiating launch sequence with profile '\(profileName)'", category: .launch)

        for script in activeScripts where script.isEnabled {
            do {
                try launchService.executeShellScript(
                    at: script.path,
                    profileName: profileName,
                    globalEnv: scriptEnvironment,
                    profileEnv: activeEnvironmentVariables
                )
            } catch {
                let err = AppError.scriptExecutionFailed(path: script.path, underlyingError: error.localizedDescription).localizedDescription
                self.lastErrorMessage = err
                ConsoleLogger.shared.log("Profile script failed: \(err)", category: .launch, level: .error)
            }
        }

        launchService.launchXPlane(
            at: xPlanePath,
            onSuccess: {
                NSApp.terminate(nil)
            },
            onFailure: { [weak self] error in
                self?.lastErrorMessage = "Failed to launch X-Plane: \(error.localizedDescription)"
            }
        )
    }
}
