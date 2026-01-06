import Foundation
import SwiftUI

@Observable
class PluginManager {
    var xPlanePath: URL? {
        didSet {
            savePath()
            scanPlugins()
        }
    }
    var plugins: [Plugin] = []
    
    // Profiles
    struct PluginProfile: Identifiable, Codable, Hashable {
        var id = UUID()
        var name: String
        var pluginFolderNames: [String]
    }
    
    var profiles: [PluginProfile] = []

    
    struct Plugin: Identifiable, Equatable {
        let id = UUID()
        let name: String
        var isEnabled: Bool
        let folderName: String // The actual folder name in "available plugins"
    }
    
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let pathKey = "XPlanePath"

    private let profilesKey = "PluginProfiles"
    private let selectedProfileIdKey = "SelectedProfileId"
    
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
                scanPlugins()
                
                // Validate preserved profile selection
                if let savedIdString = defaults.string(forKey: selectedProfileIdKey),
                   let savedId = UUID(uuidString: savedIdString),
                   let profile = profiles.first(where: { $0.id == savedId }) {
                    
                    let currentEnabled = Set(plugins.filter { $0.isEnabled }.map { $0.folderName })
                    let profileEnabled = Set(profile.pluginFolderNames)
                    
                    if currentEnabled == profileEnabled {
                        self.selectedProfileId = savedId
                    } else {
                        // Mismatch, clear persistence
                        defaults.removeObject(forKey: selectedProfileIdKey)
                    }
                }
            }
        }
    }
    
    var selectedProfileId: UUID? {
        didSet {
            if let id = selectedProfileId {
                defaults.set(id.uuidString, forKey: selectedProfileIdKey)
                if let profile = profiles.first(where: { $0.id == id }) {
                    isApplyingProfile = true
                    applyProfile(profile)
                    isApplyingProfile = false
                }
            } else {
                defaults.removeObject(forKey: selectedProfileIdKey)
            }
        }
    }
    func savePath() {
        if let path = xPlanePath {
            defaults.set(path.path, forKey: pathKey)
        }
    }
    
    func scanPlugins() {
        guard let xPlanePath = xPlanePath else {
            plugins = []
            return
        }
        
        // Define paths
        let resourcesURL = xPlanePath.appendingPathComponent("Resources")
        let availablePluginsURL = resourcesURL.appendingPathComponent("available plugins")
        let pluginsURL = resourcesURL.appendingPathComponent("plugins")
        
        // Check if directories exist
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: availablePluginsURL.path, isDirectory: &isDir), isDir.boolValue else {
            print("Resources/available plugins not found")
            plugins = []
            return
        }
        
        // Ensure plugins directory exists (it should, but good to check)
        
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
    
    func togglePlugin(_ plugin: Plugin) {
        guard let xPlanePath = xPlanePath else { return }
        
        let pluginsURL = xPlanePath.appendingPathComponent("Resources").appendingPathComponent("plugins")
        let availablePluginURL = xPlanePath.appendingPathComponent("Resources").appendingPathComponent("available plugins").appendingPathComponent(plugin.folderName)
        let linkURL = pluginsURL.appendingPathComponent(plugin.folderName)
        
        print("Toggling \(plugin.name). Current state: \(plugin.isEnabled)")
        
        do {
            if plugin.isEnabled {
                // Was enabled, now disabling -> Remove symlink
                if fileManager.fileExists(atPath: linkURL.path) {
                    try fileManager.removeItem(at: linkURL)
                }
            } else {
                // Was disabled, now enabling -> Create symlink
                // Note: Symlinks need absolute path to target if we want them to be robust, 
                // but usually relative path is better if the whole X-Plane folder moves.
                // However, 'available plugins' is a sibling of 'plugins'. 
                // Target: ../available plugins/PluginName
                
                // Let's rely on absolute paths for simplicity first, or relative if standard.
                // Standard ln -s command usually takes target then name.
                // FileManager createSymbolicLink(at:withDestinationURL:)
                
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: availablePluginURL)
            }
            
            // Update model
            if let index = plugins.firstIndex(where: { $0.id == plugin.id }) {
                plugins[index].isEnabled.toggle()
            }
            
            if !isApplyingProfile {
                selectedProfileId = nil
            }
            
        } catch {
            print("Error toggling plugin: \(error)")
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
            // Maybe it's not a .app bundle in the root?
            // User selected the "X-Plane 12 folder". usually contains 'X-Plane.app'
             print("X-Plane.app not found in \(xPlanePath.path)")
        }
    }
    
    // MARK: - Profile Management
    
    func saveProfile(name: String) {
        let enabledPlugins = plugins.filter { $0.isEnabled }.map { $0.folderName }
        let newProfile = PluginProfile(name: name, pluginFolderNames: enabledPlugins)
        profiles.append(newProfile)
        saveProfilesToDisk()
        selectedProfileId = newProfile.id // Select it
    }
    
    func updateProfile(_ profile: PluginProfile) {
        let enabledPlugins = plugins.filter { $0.isEnabled }.map { $0.folderName }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].pluginFolderNames = enabledPlugins
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
        // Force refresh of model happens inside togglePlugin but we are iterating.
        // togglePlugin modifies 'plugins' array.
        // Swift array iteration issues?
        // Let's re-scan at the end or handle index safely.
        // togglePlugin updates by index finding ID. It should be safe.
        // Optimization: Batch updates?
        // Current togglePlugin does FS op + array update. 
        // It's acceptable for now.
    }
}
