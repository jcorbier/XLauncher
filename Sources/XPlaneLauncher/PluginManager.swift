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

    private let defaults = UserDefaults.standard
    private var isLoading = true
    private var isRestoringState = false

    // MARK: - Paths

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

    var launcherDataFolder: URL? {
        didSet {
            guard !isLoading else { return }
            savePath()
            ensureLauncherDataDirectories()
            repairStaleLinks()
            scanPlugins()
            scanScenery()
            scanAircraft()
            scanLuaScripts()
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
        if let defaultFolder = PathService.defaultLauncherDataFolder {
            self.launcherDataFolder = defaultFolder
        }

        if let savedDataPath = defaults.string(forKey: .launcherDataFolder) {
            let url = URL(fileURLWithPath: savedDataPath)
            if pathService.isDirectory(at: url) {
                self.launcherDataFolder = url
            }
        }

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

        self.scriptEnvironment = profileService.loadScriptEnvironment()
        self.sceneryGroups = profileService.loadSceneryGroups()
        self.enableCSLSupport = defaults.bool(forKey: .enableCSLSupport)
        self.enableCSLXP12Lights = defaults.bool(forKey: .enableCSLXP12Lights)
        self.enableNavdataSupport = defaults.bool(forKey: .enableNavdataSupport)
        self.hasCompletedWelcome = defaults.bool(forKey: .hasCompletedWelcome)

        logProfileStartupState()

        isLoading = false
    }

    // MARK: - Directory & Persistence Helpers

    func ensureLauncherDataDirectories() {
        guard let dataFolder = launcherDataFolder else { return }
        pathService.ensureDirectories(for: dataFolder)
    }

    func savePath() {
        if let path = xPlanePath {
            defaults.set(path.path, forKey: .xPlanePath)
        }
        if let path = launcherDataFolder {
            defaults.set(path.path, forKey: .launcherDataFolder)
        } else {
            defaults.removeObject(forKey: .launcherDataFolder)
        }
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

        if let dataFolder = pluginsDataFolder {
            symlinkService.repairStaleLinks(
                in: pathService.pluginsTargetFolder(for: xPlanePath),
                using: symlinkService.linkSources(in: dataFolder)
            )
        }

        if let dataFolder = aircraftDataFolder {
            symlinkService.repairStaleLinks(
                in: pathService.aircraftTargetFolder(for: xPlanePath),
                using: symlinkService.linkSources(in: dataFolder)
            )
        }

        if let dataFolder = sceneryDataFolder {
            symlinkService.repairStaleLinks(
                in: pathService.customSceneryFolder(for: xPlanePath),
                using: symlinkService.linkSources(in: dataFolder)
            )
        }

        if let dataFolder = luaScriptsDataFolder {
            if let targetFolder = flyWithLuaScriptsFolder {
                symlinkService.repairStaleLinks(
                    in: targetFolder,
                    using: symlinkService.luaScriptLinkSources(in: dataFolder)
                )
            }
            if let modulesFolder = flyWithLuaModulesFolder {
                symlinkService.repairStaleLinks(
                    in: modulesFolder,
                    using: symlinkService.luaModuleLinkSources(in: dataFolder)
                )
            }
        }
    }

    // MARK: - Scanning

    func scanPlugins() {
        guard let xPlanePath = xPlanePath,
              let pluginsURL = pluginsDataFolder else {
            plugins = []
            return
        }

        let targetFolder = pathService.pluginsTargetFolder(for: xPlanePath)
        do {
            self.plugins = try symlinkService.scanPlugins(dataFolder: pluginsURL, targetFolder: targetFolder)
            ConsoleLogger.shared.log("Scanned \(self.plugins.count) plugins (\(self.plugins.filter { $0.isEnabled }.count) enabled)", category: .plugins)
        } catch {
            self.lastErrorMessage = "Error scanning plugins: \(error.localizedDescription)"
            ConsoleLogger.shared.log("Error scanning plugins: \(error.localizedDescription)", category: .plugins, level: .error)
        }
    }

    func scanAircraft() {
        guard let xPlanePath = xPlanePath,
              let aircraftFolder = aircraftDataFolder else {
            aircraft = []
            return
        }

        let targetFolder = pathService.aircraftTargetFolder(for: xPlanePath)
        do {
            self.aircraft = try symlinkService.scanAircraft(dataFolder: aircraftFolder, targetFolder: targetFolder)
            ConsoleLogger.shared.log("Scanned \(self.aircraft.count) aircraft (\(self.aircraft.filter { $0.isEnabled }.count) enabled)", category: .aircraft)
        } catch {
            self.lastErrorMessage = "Error scanning aircraft: \(error.localizedDescription)"
            ConsoleLogger.shared.log("Error scanning aircraft: \(error.localizedDescription)", category: .aircraft, level: .error)
        }
    }

    func scanLuaScripts() {
        guard let luaScriptsFolder = luaScriptsDataFolder else {
            luaScripts = []
            return
        }

        let targetFolder = flyWithLuaScriptsFolder
        let modulesFolder = flyWithLuaModulesFolder
        do {
            self.luaScripts = try symlinkService.scanLuaScripts(dataFolder: luaScriptsFolder, targetFolder: targetFolder, modulesTargetFolder: modulesFolder)
            ConsoleLogger.shared.log("Scanned \(self.luaScripts.count) Lua scripts (\(self.luaScripts.filter { $0.isEnabled }.count) enabled)", category: .lua)
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
                managedSceneryFolder: sceneryDataFolder,
                iniURL: iniURL
            )
            ConsoleLogger.shared.log("Scanned \(self.scenery.count) scenery packs (\(self.scenery.filter { $0.isEnabled }.count) enabled)", category: .scenery)
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

    func togglePlugin(_ plugin: Plugin) {
        guard let xPlanePath = xPlanePath,
              let pluginsFolder = pluginsDataFolder else { return }

        let targetFolder = pathService.pluginsTargetFolder(for: xPlanePath)
        let newEnabled = !plugin.isEnabled
        do {
            try symlinkService.setPluginEnabled(folderName: plugin.folderName, enabled: newEnabled, dataFolder: pluginsFolder, targetFolder: targetFolder)
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
        guard let xPlanePath = xPlanePath,
              let aircraftFolder = aircraftDataFolder else { return }

        let targetFolder = pathService.aircraftTargetFolder(for: xPlanePath)
        let newEnabled = !item.isEnabled

        do {
            try symlinkService.setAircraftEnabled(folderName: item.folderName, enabled: newEnabled, dataFolder: aircraftFolder, targetFolder: targetFolder)
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
        guard let targetFolder = flyWithLuaScriptsFolder,
              let sourceRoot = luaScriptsDataFolder else { return }

        let modulesFolder = flyWithLuaModulesFolder
        let newEnabled = !item.isEnabled

        do {
            try symlinkService.setLuaScriptEnabled(item: item, enabled: newEnabled, dataFolder: sourceRoot, targetFolder: targetFolder, modulesTargetFolder: modulesFolder)
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
        guard let index = scenery.firstIndex(where: { $0.id == item.id }) else { return }
        guard item.isToggleable else { return }

        var newItem = scenery[index]
        let wasEnabled = newItem.isEnabled

        if !wasEnabled {
            if let xPlanePath = xPlanePath, let sceneryFolder = sceneryDataFolder {
                let customScenery = pathService.customSceneryFolder(for: xPlanePath)
                do {
                    try sceneryService.linkScenery(folderName: newItem.folderName, managedSceneryFolder: sceneryFolder, customSceneryFolder: customScenery)
                    newItem.isManaged = true
                } catch {
                    self.lastErrorMessage = "Failed to enable scenery '\(newItem.name)': \(error.localizedDescription)"
                    ConsoleLogger.shared.log("Failed to enable scenery '\(newItem.name)': \(error.localizedDescription)", category: .scenery, level: .error)
                    return
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

    func moveScenery(from source: IndexSet, to destination: Int) {
        scenery.move(fromOffsets: source, toOffset: destination)
        saveSceneryOrder()
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

    func removeFromGroup(_ sceneryItem: Scenery) {
        for (idx, group) in sceneryGroups.enumerated() {
            if group.childFolderNames.contains(sceneryItem.folderName) {
                sceneryGroups[idx].childFolderNames.removeAll(where: { $0 == sceneryItem.folderName })
            }
        }
    }

    // MARK: - Profiles

    func saveProfile(name: String) {
        let enabledPlugins = plugins.filter { $0.isEnabled }.map { $0.folderName }
        let enabledScenery = scenery.filter { $0.isEnabled }.map { $0.folderName }
        let enabledAircraft = aircraft.filter { $0.isEnabled }.map { $0.folderName }
        let enabledLua = luaScripts.filter { $0.isEnabled }.map { $0.folderName }

        let newProfile = PluginProfile(
            name: name,
            pluginFolderNames: enabledPlugins,
            sceneryFolderNames: enabledScenery,
            aircraftFolderNames: enabledAircraft,
            luaScriptFolderNames: enabledLua,
            scripts: activeScripts,
            environmentVariables: activeEnvironmentVariables
        )
        profiles.append(newProfile)
        profileService.saveProfiles(profiles)
        selectedProfileId = newProfile.id
        ConsoleLogger.shared.log("Saved new profile '\(name)'", category: .profiles)
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

    private func applyProfile(_ profile: PluginProfile) {
        ConsoleLogger.shared.log("Applying profile '\(profile.name)'", category: .profiles)
        for index in plugins.indices {
            let shouldBeEnabled = profile.pluginFolderNames.contains(plugins[index].folderName)
            if plugins[index].isEnabled != shouldBeEnabled {
                togglePlugin(plugins[index])
            }
        }

        for index in scenery.indices {
            let shouldBeEnabled = profile.sceneryFolderNames.contains(scenery[index].folderName)
            if scenery[index].isEnabled != shouldBeEnabled {
                toggleScenery(scenery[index])
            }
        }

        for index in aircraft.indices {
            let shouldBeEnabled = profile.aircraftFolderNames.contains(aircraft[index].folderName)
            if aircraft[index].isEnabled != shouldBeEnabled {
                toggleAircraft(aircraft[index])
            }
        }

        for index in luaScripts.indices {
            let shouldBeEnabled = profile.luaScriptFolderNames.contains(luaScripts[index].folderName)
            if luaScripts[index].isEnabled != shouldBeEnabled {
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
        guard let dataFolder = pluginsDataFolder else { return }
        do {
            if let xPlanePath = xPlanePath {
                let targetFolder = pathService.pluginsTargetFolder(for: xPlanePath)
                try? symlinkService.setPluginEnabled(folderName: plugin.folderName, enabled: false, dataFolder: dataFolder, targetFolder: targetFolder)
            }

            let cleanName = try PathSecurity.sanitizePathComponent(plugin.folderName)
            let sourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: dataFolder)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
            }

            removeAddonFromAllProfiles(folderName: plugin.folderName, category: .plugins)
            scanPlugins()
            ConsoleLogger.shared.log("Deleted plugin '\(plugin.name)'", category: .plugins)
        } catch {
            self.lastErrorMessage = "Failed to delete plugin '\(plugin.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to delete plugin '\(plugin.name)': \(error.localizedDescription)", category: .plugins, level: .error)
        }
    }

    func deleteAircraft(_ item: Aircraft) {
        guard let dataFolder = aircraftDataFolder else { return }
        do {
            if let xPlanePath = xPlanePath {
                let targetFolder = pathService.aircraftTargetFolder(for: xPlanePath)
                try? symlinkService.setAircraftEnabled(folderName: item.folderName, enabled: false, dataFolder: dataFolder, targetFolder: targetFolder)
            }

            let cleanName = try PathSecurity.sanitizePathComponent(item.folderName)
            let sourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: dataFolder)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
            }

            removeAddonFromAllProfiles(folderName: item.folderName, category: .aircraft)
            scanAircraft()
            ConsoleLogger.shared.log("Deleted aircraft '\(item.name)'", category: .aircraft)
        } catch {
            self.lastErrorMessage = "Failed to delete aircraft '\(item.name)': \(error.localizedDescription)"
            ConsoleLogger.shared.log("Failed to delete aircraft '\(item.name)': \(error.localizedDescription)", category: .aircraft, level: .error)
        }
    }

    func deleteLuaScript(_ item: LuaScript) {
        guard let dataFolder = luaScriptsDataFolder else { return }
        do {
            if let targetFolder = flyWithLuaScriptsFolder {
                let modulesFolder = flyWithLuaModulesFolder
                try? symlinkService.setLuaScriptEnabled(item: item, enabled: false, dataFolder: dataFolder, targetFolder: targetFolder, modulesTargetFolder: modulesFolder)
            }

            let cleanName = try PathSecurity.sanitizePathComponent(item.folderName)
            let sourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: dataFolder)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
            }

            removeAddonFromAllProfiles(folderName: item.folderName, category: .luaScripts)
            scanLuaScripts()
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
        guard let dataFolder = sceneryDataFolder else { return }

        do {
            if let xPlanePath = xPlanePath {
                let customScenery = pathService.customSceneryFolder(for: xPlanePath)
                try? sceneryService.unlinkScenery(folderName: item.folderName, customSceneryFolder: customScenery)
            }

            let cleanName = try PathSecurity.sanitizePathComponent(item.folderName)
            let sourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: dataFolder)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
            }

            removeFromGroup(item)
            scenery.removeAll { $0.id == item.id }
            saveSceneryOrder()
            removeAddonFromAllProfiles(folderName: item.folderName, category: .scenery)
            scanScenery()
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
        activeScripts.removeAll { $0.id == script.id }
        if let profile = selectedProfile {
            ConsoleLogger.shared.log("Profile '\(profile.name)': removed script '\(name)'", category: .profiles)
        }
    }

    func toggleScript(_ script: ProfileScript) {
        if let index = activeScripts.firstIndex(where: { $0.id == script.id }) {
            activeScripts[index].isEnabled.toggle()
            let name = URL(fileURLWithPath: script.path).lastPathComponent
            if let profile = selectedProfile {
                ConsoleLogger.shared.log("Profile '\(profile.name)': script '\(name)' is now \(activeScripts[index].isEnabled ? "enabled" : "disabled")", category: .profiles)
            }
        }
    }

    func addProfileEnvVar(key: String = "NEW_VAR", value: String = "VALUE") {
        activeEnvironmentVariables.append(ScriptEnvVar(key: key, value: value))
        if let profile = selectedProfile {
            ConsoleLogger.shared.log("Profile '\(profile.name)': added environment variable '\(key)'", category: .profiles)
        }
    }

    func deleteProfileEnvVar(id: UUID) {
        let key = activeEnvironmentVariables.first(where: { $0.id == id })?.key ?? "var"
        activeEnvironmentVariables.removeAll { $0.id == id }
        if let profile = selectedProfile {
            ConsoleLogger.shared.log("Profile '\(profile.name)': removed environment variable '\(key)'", category: .profiles)
        }
    }

    // MARK: - Launch & Execution

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
