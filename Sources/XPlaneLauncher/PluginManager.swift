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
        self.hasCompletedWelcome = defaults.bool(forKey: .hasCompletedWelcome)

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

        if let dataFolder = luaScriptsDataFolder, let targetFolder = flyWithLuaScriptsFolder {
            symlinkService.repairStaleLinks(
                in: targetFolder,
                using: symlinkService.luaScriptLinkSources(in: dataFolder)
            )
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
        } catch {
            self.lastErrorMessage = "Error scanning plugins: \(error.localizedDescription)"
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
        } catch {
            self.lastErrorMessage = "Error scanning aircraft: \(error.localizedDescription)"
        }
    }

    func scanLuaScripts() {
        guard let luaScriptsFolder = luaScriptsDataFolder else {
            luaScripts = []
            return
        }

        let targetFolder = flyWithLuaScriptsFolder
        do {
            self.luaScripts = try symlinkService.scanLuaScripts(dataFolder: luaScriptsFolder, targetFolder: targetFolder)
        } catch {
            self.lastErrorMessage = "Error scanning Lua scripts: \(error.localizedDescription)"
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
        } catch {
            self.lastErrorMessage = "Error scanning Custom Scenery: \(error.localizedDescription)"
        }
    }

    func saveSceneryOrder() {
        guard let xPlanePath = xPlanePath else { return }
        let customSceneryURL = pathService.customSceneryFolder(for: xPlanePath)
        let iniURL = pathService.sceneryPacksIniURL(for: xPlanePath)

        do {
            try sceneryService.saveSceneryOrder(scenery: scenery, customSceneryFolder: customSceneryURL, iniURL: iniURL)
        } catch {
            self.lastErrorMessage = "Failed to save scenery_packs.ini: \(error.localizedDescription)"
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
            }
        } catch {
            self.lastErrorMessage = "Failed to \(plugin.isEnabled ? "disable" : "enable") plugin '\(plugin.name)': \(error.localizedDescription)"
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
            }
        } catch {
            self.lastErrorMessage = "Failed to \(item.isEnabled ? "disable" : "enable") aircraft '\(item.name)': \(error.localizedDescription)"
        }
    }

    func toggleLuaScript(_ item: LuaScript) {
        guard let targetFolder = flyWithLuaScriptsFolder,
              let sourceRoot = luaScriptsDataFolder else { return }

        let newEnabled = !item.isEnabled

        do {
            try symlinkService.setLuaScriptEnabled(item: item, enabled: newEnabled, dataFolder: sourceRoot, targetFolder: targetFolder)
            if let index = luaScripts.firstIndex(where: { $0.id == item.id }) {
                luaScripts[index].isEnabled = newEnabled
            }
        } catch {
            self.lastErrorMessage = "Failed to \(item.isEnabled ? "disable" : "enable") Lua script '\(item.name)': \(error.localizedDescription)"
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
                    return
                }
            }
            newItem.isEnabled = true
        } else {
            newItem.isEnabled = false
        }

        scenery[index] = newItem
        saveSceneryOrder()
    }

    func unlinkScenery(_ item: Scenery) {
        guard let index = scenery.firstIndex(where: { $0.id == item.id }) else { return }
        guard item.isManaged else { return }

        if let xPlanePath = xPlanePath {
            let customScenery = pathService.customSceneryFolder(for: xPlanePath)
            do {
                try sceneryService.unlinkScenery(folderName: item.folderName, customSceneryFolder: customScenery)
            } catch {
                self.lastErrorMessage = "Failed to unlink scenery '\(item.name)': \(error.localizedDescription)"
                return
            }
        }

        var newItem = scenery[index]
        newItem.isEnabled = false
        newItem.isInIni = false
        scenery[index] = newItem

        if let groupIndex = sceneryGroups.firstIndex(where: { $0.childFolderNames.contains(item.folderName) }) {
            var group = sceneryGroups[groupIndex]
            group.childFolderNames.removeAll(where: { $0 == item.folderName })
            sceneryGroups[groupIndex] = group
        }

        saveSceneryOrder()
        scanScenery()
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
        self.sceneryGroups = sceneryService.removeFromGroup(sceneryItem: sceneryItem, existingGroups: sceneryGroups)
    }

    // MARK: - Profile Management

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
    }

    func duplicateProfile(_ profile: PluginProfile) {
        let copy = profileService.duplicateProfile(profile)
        profiles.append(copy)
        profileService.saveProfiles(profiles)
        selectedProfileId = copy.id
        applyProfile(copy)
    }

    private func applyProfile(_ profile: PluginProfile) {
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

    // MARK: - Script Management

    func addScript(name: String, path: String) {
        let newScript = ProfileScript(path: path, isEnabled: true)
        activeScripts.append(newScript)
    }

    func deleteScript(_ script: ProfileScript) {
        activeScripts.removeAll { $0.id == script.id }
    }

    func toggleScript(_ script: ProfileScript) {
        if let index = activeScripts.firstIndex(where: { $0.id == script.id }) {
            activeScripts[index].isEnabled.toggle()
        }
    }

    func addProfileEnvVar(key: String = "NEW_VAR", value: String = "VALUE") {
        activeEnvironmentVariables.append(ScriptEnvVar(key: key, value: value))
    }

    func deleteProfileEnvVar(id: UUID) {
        activeEnvironmentVariables.removeAll { $0.id == id }
    }

    // MARK: - Launch & Execution

    func launchXPlane() {
        guard let xPlanePath = xPlanePath else { return }

        let profileName = profiles.first(where: { $0.id == selectedProfileId })?.name ?? "Default"
        for script in activeScripts where script.isEnabled {
            do {
                try launchService.executeShellScript(
                    at: script.path,
                    profileName: profileName,
                    globalEnv: scriptEnvironment,
                    profileEnv: activeEnvironmentVariables
                )
            } catch {
                self.lastErrorMessage = AppError.scriptExecutionFailed(path: script.path, underlyingError: error.localizedDescription).localizedDescription
            }
        }

        launchService.launchXPlane(
            at: xPlanePath,
            onSuccess: {
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            },
            onFailure: { [weak self] error in
                DispatchQueue.main.async {
                    self?.lastErrorMessage = "Failed to launch X-Plane: \(error.localizedDescription)"
                }
            }
        )
    }
}
