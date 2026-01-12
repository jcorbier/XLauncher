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
    private let sceneryGroupsKey = "SceneryGroups"
    
    private var isApplyingProfile = false
    
    struct SceneryGroup: Identifiable, Codable, Hashable {
        var id = UUID()
        var name: String
        var childFolderNames: [String] = []
        var isExpanded: Bool = true // UI state
    }
    
    var sceneryGroups: [SceneryGroup] = [] {
        didSet {
            saveSceneryGroups()
        }
    }
    
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
        
        if let data = defaults.data(forKey: sceneryGroupsKey),
           let groups = try? JSONDecoder().decode([SceneryGroup].self, from: data) {
            self.sceneryGroups = groups
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

    func saveSceneryGroups() {
        if let data = try? JSONEncoder().encode(sceneryGroups) {
            defaults.set(data, forKey: sceneryGroupsKey)
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
        
        // Remove from any group
        if let groupIndex = sceneryGroups.firstIndex(where: { $0.childFolderNames.contains(item.folderName) }) {
            var group = sceneryGroups[groupIndex]
            group.childFolderNames.removeAll(where: { $0 == item.folderName })
            sceneryGroups[groupIndex] = group
            // If group empty? Keep it or remove it? Let's keep it.
        }
        
        saveSceneryOrder()
        scanScenery()
    }
    
    // MARK: - Scenery Grouping

    func createGroup(name: String, with items: [Scenery]) {
        let folderNames = items.map { $0.folderName }
        let newGroup = SceneryGroup(name: name, childFolderNames: folderNames)
        
        // Remove items from any existing groups
        for folder in folderNames {
             for (idx, _) in sceneryGroups.enumerated() {
                 if let i = sceneryGroups[idx].childFolderNames.firstIndex(of: folder) {
                     sceneryGroups[idx].childFolderNames.remove(at: i)
                 }
             }
        }
        
        sceneryGroups.append(newGroup)
        
        // Reorder scenery list to group them physically
        // We place them after the first item's original position (or at top if none)
        if let firstItem = items.first,
           let firstIndex = scenery.firstIndex(where: { $0.folderName == firstItem.folderName }) {
            
            // Remove all items from current positions
            var remaining = scenery.filter { !folderNames.contains($0.folderName) }
            
            // Insert them back at firstIndex (clamped)
            let insertIndex = min(firstIndex, remaining.count)
            // We need to fetch the actual updated objects (scenery is value type)
            // But we can just use `items` if we trust they are fresh, better get from `scenery`
            let movingItems = scenery.filter { folderNames.contains($0.folderName) }
            
            remaining.insert(contentsOf: movingItems, at: insertIndex)
            scenery = remaining
        }
        
        saveSceneryOrder()
    }
    
    func deleteGroup(_ group: SceneryGroup) {
        sceneryGroups.removeAll { $0.id == group.id }
        // Items remain in `scenery` list, just ungrouped.
    }
    
    func toggleGroup(_ group: SceneryGroup, isEnabled: Bool) {
        // Toggle all children
        // We need to find them in `scenery`
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
    
    func moveSceneryToGroup(_ sceneryItem: Scenery, group: SceneryGroup) {
        // 1. Identify current members before addition (to find location)
        let currentMembers = scenery.filter { group.childFolderNames.contains($0.folderName) }
        
        // 2. Remove from old group (metadata)
        removeFromGroup(sceneryItem)
        
        // 3. Add to new group (metadata)
        if let index = sceneryGroups.firstIndex(where: { $0.id == group.id }) {
            sceneryGroups[index].childFolderNames.append(sceneryItem.folderName)
            
            // 4. Physical Move
            // If group already has members, move this item to be after the last member.
            if let lastMember = currentMembers.last,
               let targetIndex = scenery.firstIndex(where: { $0.id == lastMember.id }),
               let currentIndex = scenery.firstIndex(where: { $0.id == sceneryItem.id }) {
                
                var newScenery = scenery
                // Remove from old pos
                let item = newScenery.remove(at: currentIndex)
                
                // Calculate insert index. 
                // If currentIndex < targetIndex, removing shifts targetIndex down by 1.
                var insertAt = targetIndex
                if currentIndex < targetIndex {
                    if let reFoundIndex = newScenery.firstIndex(where: { $0.id == lastMember.id }) {
                        insertAt = reFoundIndex + 1
                    }
                } else {
                    // Item was after group. Removing it doesn't change group indices.
                    // targetIndex is valid.
                     if let reFoundIndex = newScenery.firstIndex(where: { $0.id == lastMember.id }) {
                        insertAt = reFoundIndex + 1
                    }
                }
                
                // Boundary check
                insertAt = min(insertAt, newScenery.count)
                newScenery.insert(item, at: insertAt)
                
                self.scenery = newScenery
                saveSceneryOrder()
            } else {
                // Group was empty. Item stays where it is, and defines the new group position.
                // Just save to trigger updates
                saveSceneryOrder()
            }
        }
    }
    
    func moveScenery(_ item: Scenery, relativeTo target: Scenery) {
        guard item.id != target.id else { return }
        
        // 1. Remove from old group (metadata)
        removeFromGroup(item)
        
        // 2. Check target's group
        if let targetGroup = sceneryGroups.first(where: { $0.childFolderNames.contains(target.folderName) }) {
             // Target is in a group, add item to it
             if let idx = sceneryGroups.firstIndex(where: { $0.id == targetGroup.id }) {
                 sceneryGroups[idx].childFolderNames.append(item.folderName)
             }
        }
        
        // 3. Physical Move
        // We want 'item' to be immediately after 'target'
        if let _ = scenery.firstIndex(where: { $0.id == target.id }),
           let currentIndex = scenery.firstIndex(where: { $0.id == item.id }) {
            
            var newScenery = scenery
            let movingItem = newScenery.remove(at: currentIndex)
            
            // Re-find target index
            if let newTargetIndex = newScenery.firstIndex(where: { $0.id == target.id }) {
                // Insert after
                let insertIndex = min(newTargetIndex + 1, newScenery.count)
                newScenery.insert(movingItem, at: insertIndex)
                
                self.scenery = newScenery
                saveSceneryOrder()
            }
        }
    }
    
    func removeFromGroup(_ sceneryItem: Scenery) {
         for (idx, _) in sceneryGroups.enumerated() {
             if let i = sceneryGroups[idx].childFolderNames.firstIndex(of: sceneryItem.folderName) {
                 sceneryGroups[idx].childFolderNames.remove(at: i)
             }
         }
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
