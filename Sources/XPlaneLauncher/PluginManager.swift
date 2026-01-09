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

import Foundation
import SwiftUI

@Observable
class PluginManager {
    private var isLoading = true

    var xPlanePath: URL? {
        didSet {
            guard !isLoading else { return }
            savePath()
            scanPlugins()
            scanScenery()
        }
    }
    var availablePluginsPath: URL? {
        didSet {
            guard !isLoading else { return }
            savePath()
            scanPlugins()
        }
    }
    var availableSceneryPath: URL? {
        didSet {
            guard !isLoading else { return }
            savePath()
            scanScenery()
        }
    }
    var plugins: [Plugin] = []
    var scenery: [Scenery] = []
    struct ScriptEnvVar: Identifiable, Codable, Hashable {
        var id = UUID()
        var key: String
        var value: String
    }
    
    var scriptEnvironment: [ScriptEnvVar] = [] {
        didSet {
            saveScriptEnvironment()
        }
    }
    
    // Profiles
    struct PluginProfile: Identifiable, Codable, Hashable {
        var id = UUID()
        var name: String
        var pluginFolderNames: [String]
        var sceneryFolderNames: [String] = []
        var shellScriptPath: String?
    }
    
    var profiles: [PluginProfile] = []

    
    struct Plugin: Identifiable, Equatable {
        let id = UUID()
        let name: String
        var isEnabled: Bool
        let folderName: String // The actual folder name in "available plugins"
    }
    
    struct Scenery: Identifiable, Equatable, Hashable {
        let id = UUID()
        var name: String
        var isEnabled: Bool // true = SCENERY_PACK, false = DISABLED or Unlinked
        var folderName: String
        var isManaged: Bool // true if a symlink exists/can be created (managed content), false if just a folder
        var isInIni: Bool // true if found in scenery_packs.ini (and thus installed/linked)
        var iniLine: String // Store the exact line from INI to preserve formatting if needed
        var isToggleable: Bool {
            !folderName.hasPrefix("*")
        }
    }
    
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let pathKey = "XPlanePath"
    private let availablePluginsPathKey = "AvailablePluginsPath"
    private let availableSceneryPathKey = "AvailableSceneryPath"
    private let kXPlaneCustomSceneryFileName = "scenery_packs.ini"

    private let profilesKey = "PluginProfiles"
    private let selectedProfileIdKey = "SelectedProfileId"
    private let scriptEnvironmentKey = "ScriptEnvVars"
    
    private var isApplyingProfile = false
    
    init() {
        // Load profiles
        if let data = defaults.data(forKey: profilesKey),
           let savedProfiles = try? JSONDecoder().decode([PluginProfile].self, from: data) {
            self.profiles = savedProfiles
        }
        
        if let savedPath = defaults.string(forKey: pathKey) {
            // Verify it exists
            let url = URL(fileURLWithPath: savedPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                self.xPlanePath = url
                
                // Validate preserved profile selection
                if let savedIdString = defaults.string(forKey: selectedProfileIdKey),
                   let savedId = UUID(uuidString: savedIdString) {
                     isRestoringState = true
                     self.selectedProfileId = savedId
                     isRestoringState = false
                }
            }
        }
        
        if let savedPluginPath = defaults.string(forKey: availablePluginsPathKey) {
            let url = URL(fileURLWithPath: savedPluginPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                self.availablePluginsPath = url
            }
        }
        
        if let savedSceneryPath = defaults.string(forKey: availableSceneryPathKey) {
            let url = URL(fileURLWithPath: savedSceneryPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                self.availableSceneryPath = url
            }
        }
        
        // Initial scan if paths are ready (xPlanePath is set above)
        scanPlugins()
        scanScenery()
        
        if let data = defaults.data(forKey: scriptEnvironmentKey),
           let envData = try? JSONDecoder().decode([ScriptEnvVar].self, from: data) {
            self.scriptEnvironment = envData
        }
        
        isLoading = false
    }
    
    
    var selectedProfileId: UUID? {
        didSet {
            if let id = selectedProfileId {
                defaults.set(id.uuidString, forKey: selectedProfileIdKey)
                if let profile = profiles.first(where: { $0.id == id }) {
                    if !isRestoringState {
                         isApplyingProfile = true
                         applyProfile(profile)
                         isApplyingProfile = false
                    }
                }
            } else {
                defaults.removeObject(forKey: selectedProfileIdKey)
            }
        }
    }
    
    private var isRestoringState = false
    
    var isCurrentProfileModified: Bool {
        guard let selectedProfileId = selectedProfileId,
              let profile = profiles.first(where: { $0.id == selectedProfileId }) else {
            return false
        }
        
        let currentEnabledPlugins = Set(plugins.filter { $0.isEnabled }.map { $0.folderName })
        let profileEnabledPlugins = Set(profile.pluginFolderNames)
        
        let currentEnabledScenery = Set(scenery.filter { $0.isEnabled }.map { $0.folderName })
        let profileEnabledScenery = Set(profile.sceneryFolderNames)
        
        return currentEnabledPlugins != profileEnabledPlugins || currentEnabledScenery != profileEnabledScenery
    }
    func savePath() {
        if let path = xPlanePath {
            defaults.set(path.path, forKey: pathKey)
        }
        if let path = availablePluginsPath {
             defaults.set(path.path, forKey: availablePluginsPathKey)
        } else {
            defaults.removeObject(forKey: availablePluginsPathKey)
        }
        if let path = availableSceneryPath {
            defaults.set(path.path, forKey: availableSceneryPathKey)
        } else {
            defaults.removeObject(forKey: availableSceneryPathKey)
        }
    }
    
    func saveScriptEnvironment() {
        if let data = try? JSONEncoder().encode(scriptEnvironment) {
            defaults.set(data, forKey: scriptEnvironmentKey)
        }
    }
    
    func scanPlugins() {
        guard let xPlanePath = xPlanePath else {
            plugins = []
            return
        }
        
        // Define paths
        let resourcesURL = xPlanePath.appendingPathComponent("Resources")
        // Use custom path if set, otherwise default
        let availablePluginsURL = availablePluginsPath ?? resourcesURL.appendingPathComponent("available plugins")
        let pluginsURL = resourcesURL.appendingPathComponent("plugins")
        
        // Check if directories exist
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: availablePluginsURL.path, isDirectory: &isDir), isDir.boolValue else {
            // Only print if we are actually expecting it (i.e. xPlanePath is valid)
            print("available plugins not found at \(availablePluginsURL.path)")
            plugins = []
            return
        }
        
        do {
            let availableContents = try fileManager.contentsOfDirectory(at: availablePluginsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            
            // Filter only directories
            var newPlugins: [Plugin] = []
            
            for folder in availableContents {
                var isFolder: ObjCBool = false
                if fileManager.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue {
                    let folderName = folder.lastPathComponent
                    
                    // Check if symlinked in 'plugins'
                    let targetLink = pluginsURL.appendingPathComponent(folderName)
                    let isEnabled = fileManager.fileExists(atPath: targetLink.path)
                    
                    newPlugins.append(Plugin(name: folderName, isEnabled: isEnabled, folderName: folderName))
                }
            }
            
            self.plugins = newPlugins.sorted { $0.name < $1.name }
            
        } catch {
            print("Error scanning plugins: \(error)")
        }
    }
    
    // MARK: - Scenery Management
    
    // Helper to get scenery_packs.ini URL
    private var sceneryPackIniURL: URL? {
        xPlanePath?.appendingPathComponent("Custom Scenery").appendingPathComponent(kXPlaneCustomSceneryFileName)
    }

    func scanScenery() {
        guard let xPlanePath = xPlanePath else {
            scenery = []
            return
        }
        
        let customSceneryURL = xPlanePath.appendingPathComponent("Custom Scenery")
        let availableSceneryURL = availableSceneryPath ?? xPlanePath.appendingPathComponent("Resources").appendingPathComponent("available scenery")

        // 1. Read scenery_packs.ini to establish order
        var iniItems: [(line: String, folderName: String, enabled: Bool)] = []
        var foundFolderNames: Set<String> = []
        
        if let iniPath = sceneryPackIniURL,
           let content = try? String(contentsOf: iniPath, encoding: .utf8) {
            
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "SCENERY_PACK") {
                    // Extract path
                    // Format: SCENERY_PACK Custom Scenery/FolderName/
                    //      or SCENERY_PACK_DISABLED Custom Scenery/FolderName/
                    
                    let isEnabled = trimmed.starts(with: "SCENERY_PACK ") // space important to distinguish from DISABLED
                    
                    // Remove prefix
                    let prefix = isEnabled ? "SCENERY_PACK " : "SCENERY_PACK_DISABLED "
                    let pathPart = String(trimmed.dropFirst(prefix.count))
                    
                    // Normalize path to get folder name
                    // usually "Custom Scenery/XXX/"
                    let components = pathPart.split(separator: "/")
                    if let last = components.last {
                        let folderName = String(last)
                        iniItems.append((line: trimmed, folderName: folderName, enabled: isEnabled))
                        foundFolderNames.insert(folderName)
                    }
                }
            }
        }
        
        // 2. Scan "Custom Scenery" for items NOT in INI (newly added manually)
        var installedButNotInIni: [Scenery] = []
        do {
            let csContents = try fileManager.contentsOfDirectory(at: customSceneryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for url in csContents {
                if url.lastPathComponent == kXPlaneCustomSceneryFileName { continue }
                
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let name = url.lastPathComponent
                    if !foundFolderNames.contains(name) {
                        // Found a folder not in INI. X-Plane treats these as Enabled, at the top.
                        // Is it managed?
                        // Check if it's a symlink
                        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                        let isSymlink = (attributes?[.type] as? String) == FileAttributeType.typeSymbolicLink.rawValue
                        
                        installedButNotInIni.append(Scenery(name: name,
                                                            isEnabled: true,
                                                            folderName: name,
                                                            isManaged: isSymlink,
                                                            isInIni: false,
                                                            iniLine: "SCENERY_PACK Custom Scenery/\(name)/"))
                    }
                }
            }
        } catch {
            print("Error scanning Custom Scenery: \(error)")
        }
        
        // 3. Scan "Available Scenery" for uninstalled items
        var uninstalled: [Scenery] = []
        if fileManager.fileExists(atPath: availableSceneryURL.path) {
            do {
                let availableContents = try fileManager.contentsOfDirectory(at: availableSceneryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                for url in availableContents {
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        let name = url.lastPathComponent
                        
                        // Check if it's already installed (either in INI or simply in Custom Scenery)
                        let isInstalled = foundFolderNames.contains(name) || installedButNotInIni.contains(where: { $0.folderName == name })
                        
                        if !isInstalled {
                            uninstalled.append(Scenery(name: name,
                                                       isEnabled: false,
                                                       folderName: name,
                                                       isManaged: true, // It comes from available, so we can manage it
                                                       isInIni: false,
                                                       iniLine: ""))
                        }
                    }
                }
            } catch {
                print("Error scanning available scenery: \(error)")
            }
        }
        
        // 4. Construct final list
        var finalScenery: [Scenery] = []
        
        // A. Installed but not in INI (Top priority, as X-Plane does)
        finalScenery.append(contentsOf: installedButNotInIni.sorted { $0.name < $1.name })
        
        // B. INI Items (In Order)
        for item in iniItems {
            // Verify it still exists in Custom Scenery
            let path = customSceneryURL.appendingPathComponent(item.folderName)
            // Special handling for meta-packages like *GLOBAL_AIRPORTS*
            let isSpecialIdx = item.folderName.hasPrefix("*")
            
            if isSpecialIdx || fileManager.fileExists(atPath: path.path) {
                // Check if managed (symlink)
                var isSymlink = false
                if !isSpecialIdx {
                    let attributes = try? fileManager.attributesOfItem(atPath: path.path)
                    isSymlink = (attributes?[.type] as? String) == FileAttributeType.typeSymbolicLink.rawValue
                }

                finalScenery.append(Scenery(name: item.folderName,
                                            isEnabled: item.enabled,
                                            folderName: item.folderName,
                                            isManaged: isSymlink,
                                            isInIni: true,
                                            iniLine: item.line))
            } else {
                 // Item in INI but missing from disk.
                 print("Skipping missing scenery: \(item.folderName)")
            }
        }
        
        // C. Uninstalled (Available)
        finalScenery.append(contentsOf: uninstalled.sorted { $0.name < $1.name })
        
        self.scenery = finalScenery
    }
    
    func saveSceneryOrder() {
        guard let iniURL = sceneryPackIniURL else { return }
        
        var content = "I\n1000 Version\nSCENERY\n\n"
        
        for item in scenery {
            // Only write items that are "installed" (in INI or symlinked)
            // If it's uninstalled (isManaged=true, isInIni=false), we don't write it unless we just installed it.
            // Actually, if it's in `scenery`, we should decide if it belongs in INI.
            // Items that are "Unlinked" (uninstalled) shouldn't be in INI at all.
            
            // Check if it exists in Custom Scenery
            // But wait, `scenery` array contains EVERYTHING including unlinked.
            
            if item.isInIni || item.isEnabled { 
                 // If it was in INI, we keep it (updating enabled state).
                 // If it is enabled, we definitely put it in.
                 
                 // What if it is disabled and NOT in INI (aka Uninstalled)?
                 // Then we don't write it.
                 
                 // So we verify presence on disk in Custom Scenery effectively?
                 // No, we leverage our source of truth.
                 
                 // If `item.isInIni` is true, it means it WAS in the file.
                 // If we moved it to "Uninstalled", we should have updated `isInIni` to false?
                 // The `scenery` array is our view model.
                 
                 // Let's rely on the definition:
                 // "Installed" items are those that have a corresponding folder/link in Custom Scenery.
                 // We should probably check the file system or track "isInstalled".
                 // BUT, for performance, let's assume if it is in the list and `isInIni` is true, or `isEnabled` is true, it's relevant.
                 
                 // Wait. Simpler check:
                 // The scan sets `isInIni` and `isManaged`.
                 // If the user drags an uninstalled item into the active list, we should install it (create symlink).
                 // If the user toggles it ON, we install it.
                 
                 // This function just writes the INI based on the list.
                 // It assumes the physical files are already in state.
                 // So we only write lines for items that SHOULD be in INI.
                 
                 // Which items should be in INI?
                 // Any item that is physically present in Custom Scenery.
                 // This includes `SCENERY_PACK_DISABLED` items.
                 
                 // So, effectively, any item where `folderName` exists in `Custom Scenery` should be written.
                 // We can check `fileManager` here?
            }
            
            let line: String
            let isSpecialIdx = item.folderName.hasPrefix("*")
            let prefix = item.isEnabled ? "SCENERY_PACK " : "SCENERY_PACK_DISABLED "
            
            if isSpecialIdx {
                line = "\(prefix)\(item.folderName)"
            } else {
                line = "\(prefix)Custom Scenery/\(item.folderName)/"
            }
            
            // Only write if physically present OR is special
            if isSpecialIdx {
                content += line + "\n"
            } else if let xPlanePath = xPlanePath {
                 let path = xPlanePath.appendingPathComponent("Custom Scenery").appendingPathComponent(item.folderName)
                 if fileManager.fileExists(atPath: path.path) {
                      content += line + "\n"
                 }
            }
        }
        
        do {
            try content.write(to: iniURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save scenery_packs.ini: \(error)")
        }
    }
    
    // Move items (drag and drop)
    func moveScenery(from source: IndexSet, to destination: Int) {
        scenery.move(fromOffsets: source, toOffset: destination)
        saveSceneryOrder()
    }

    func togglePlugin(_ plugin: Plugin) {
        guard let xPlanePath = xPlanePath else { return }
        
        let pluginsURL = xPlanePath.appendingPathComponent("Resources").appendingPathComponent("plugins")
        
        let sourceURL = (availablePluginsPath ?? xPlanePath.appendingPathComponent("Resources").appendingPathComponent("available plugins")).appendingPathComponent(plugin.folderName)
        let linkURL = pluginsURL.appendingPathComponent(plugin.folderName)
        
        print("Toggling \(plugin.name). Current state: \(plugin.isEnabled)")
        
        do {
            if plugin.isEnabled {
                // Remove symlink
                if fileManager.fileExists(atPath: linkURL.path) {
                    try fileManager.removeItem(at: linkURL)
                }
            } else {
                // Create symlink
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
            }
            
            // Update model
            if let index = plugins.firstIndex(where: { $0.id == plugin.id }) {
                plugins[index].isEnabled.toggle()
            }
        } catch {
            print("Error toggling plugin: \(error)")
        }
    }
    
    func toggleScenery(_ item: Scenery) {
        // Find index
        guard let index = scenery.firstIndex(where: { $0.id == item.id }) else { return }
        guard item.isToggleable else { return }
        
        // Logic:
        // 1. If currently Enabled -> Disable
        //    - Just set isEnabled = false (SCENERY_PACK_DISABLED)
        //    - Save INI.
        //    - Do NOT remove symlink automatically (user asked for "either", we default to INI disable).
        
        // 2. If currently Disabled -> Enable
        //    - If physically missing (Uninstalled), create symlink first.
        //    - Set isEnabled = true
        //    - Save INI.
        
        var newItem = scenery[index]
        let wasEnabled = newItem.isEnabled
        
        if !wasEnabled {
             // Enable
             // Check if we need to link it
             if let xPlanePath = xPlanePath {
                 let linkURL = xPlanePath.appendingPathComponent("Custom Scenery").appendingPathComponent(newItem.folderName)
                 if !fileManager.fileExists(atPath: linkURL.path) {
                     // It's missing, try to link from Available Scenery
                     let source = (availableSceneryPath ?? xPlanePath.appendingPathComponent("Resources").appendingPathComponent("available scenery")).appendingPathComponent(newItem.folderName)
                     
                     if fileManager.fileExists(atPath: source.path) {
                         try? fileManager.createSymbolicLink(at: linkURL, withDestinationURL: source)
                         newItem.isManaged = true // It is now managed
                     } else {
                         print("Cannot enable: Source not found at \(source.path)")
                         return
                     }
                 }
             }
             newItem.isEnabled = true
        } else {
            // Disable
            newItem.isEnabled = false
        }
        
        scenery[index] = newItem
        saveSceneryOrder()
    }
    
    func unlinkScenery(_ item: Scenery) {
        guard let index = scenery.firstIndex(where: { $0.id == item.id }) else { return }
        guard item.isManaged else { return } // Can only unlink managed items
        
        // Remove symlink
        if let xPlanePath = xPlanePath {
            let linkURL = xPlanePath.appendingPathComponent("Custom Scenery").appendingPathComponent(item.folderName)
            try? fileManager.removeItem(at: linkURL)
        }
        
        // Update list
        // It becomes "Uninstalled" (Disabled, isInIni=false)
        var newItem = scenery[index]
        newItem.isEnabled = false
        newItem.isInIni = false
        scenery[index] = newItem
        
        // Move to bottom? Or keep place?
        // Usually uninstalled go to bottom.
        // For now, save INI which will remove it from file since it's not on disk.
        saveSceneryOrder()
        
        // Rescan to sort correctly?
        // Or manually move. Rescan is safer.
        scanScenery()
    }
    
    func launchXPlane() {
        guard let xPlanePath = xPlanePath else { return }
        
        let appURL = xPlanePath.appendingPathComponent("X-Plane.app")

        
        // Try opening the App likely
        let workspace = NSWorkspace.shared
        
        // Check if .app exists
        if fileManager.fileExists(atPath: appURL.path) {
            // Launch
            let config = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: config) { app, error in
                if let error = error {
                    print("Failed to launch: \(error)")
                } else {
                    print("Launched X-Plane")
                    DispatchQueue.main.async {
                        NSApp.terminate(nil)
                    }
                }
            }

        } else {
            // Maybe it's not a .app bundle in the root?
            // User selected the "X-Plane 12 folder". usually contains 'X-Plane.app'
             print("X-Plane.app not found in \(xPlanePath.path)")
        }
    }
    
    // MARK: - Profile Management
    
    func saveProfile(name: String) {
        let enabledPlugins = plugins.filter { $0.isEnabled }.map { $0.folderName }
        let enabledScenery = scenery.filter { $0.isEnabled }.map { $0.folderName }
        let newProfile = PluginProfile(name: name, pluginFolderNames: enabledPlugins, sceneryFolderNames: enabledScenery)
        profiles.append(newProfile)
        saveProfilesToDisk()
        selectedProfileId = newProfile.id // Select it
    }
    
    func updateProfile(_ profile: PluginProfile) {
        let enabledPlugins = plugins.filter { $0.isEnabled }.map { $0.folderName }
        let enabledScenery = scenery.filter { $0.isEnabled }.map { $0.folderName }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            profiles[index].pluginFolderNames = enabledPlugins
            profiles[index].sceneryFolderNames = enabledScenery
            
            saveProfilesToDisk()
        }
    }
    
    func deleteProfile(_ profile: PluginProfile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfilesToDisk()
        if selectedProfileId == profile.id {
            selectedProfileId = nil
        }
    }
    
    private func saveProfilesToDisk() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
    }
    
    private func applyProfile(_ profile: PluginProfile) {
        // We need to iterate over all plugins and enable/disable them to match the profile
        // Note: scanPlugins() must have run first to populate 'plugins'
        
        for plugin in plugins {
            let shouldBeEnabled = profile.pluginFolderNames.contains(plugin.folderName)
            
            if plugin.isEnabled != shouldBeEnabled {
                // Change state
                togglePlugin(plugin)
            }
        }
        
        for item in scenery {
            let shouldBeEnabled = profile.sceneryFolderNames.contains(item.folderName)
            if item.isEnabled != shouldBeEnabled {
                toggleScenery(item)
            }
        }
        
        // Execute Shell Script if present
        if let scriptPath = profile.shellScriptPath, !scriptPath.isEmpty {
            executeShellScript(at: scriptPath, profileName: profile.name)
        }
    }
    
    private func executeShellScript(at path: String, profileName: String) {
        print("Executing shell script at: \(path) for profile: \(profileName)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        
        var env = ProcessInfo.processInfo.environment
        env["XLAUNCHER_PROFILE"] = profileName
        
        // Merge user defined environment
        for envVar in scriptEnvironment {
            if !envVar.key.isEmpty {
                env[envVar.key] = envVar.value
            }
        }
        
        process.environment = env
        
        do {
            try process.run()
        } catch {
            print("Failed to run shell script: \(error)")
        }
    }
}
