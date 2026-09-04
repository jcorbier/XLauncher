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

final class ProfileService: Sendable {
    static let shared = ProfileService()

    func loadProfiles() -> [PluginProfile] {
        guard let data = UserDefaults.standard.data(forKey: .pluginProfiles),
              let savedProfiles = try? JSONDecoder().decode([PluginProfile].self, from: data) else {
            return []
        }
        return savedProfiles
    }

    func saveProfiles(_ profiles: [PluginProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: .pluginProfiles)
        }
    }

    func loadScriptEnvironment() -> [ScriptEnvVar] {
        guard let data = UserDefaults.standard.data(forKey: .scriptEnvVars),
              let envData = try? JSONDecoder().decode([ScriptEnvVar].self, from: data) else {
            return []
        }
        return envData
    }

    func saveScriptEnvironment(_ env: [ScriptEnvVar]) {
        if let data = try? JSONEncoder().encode(env) {
            UserDefaults.standard.set(data, forKey: .scriptEnvVars)
        }
    }

    func loadSceneryGroups() -> [SceneryGroup] {
        guard let data = UserDefaults.standard.data(forKey: .sceneryGroups),
              let groups = try? JSONDecoder().decode([SceneryGroup].self, from: data) else {
            return []
        }
        return groups
    }

    func saveSceneryGroups(_ groups: [SceneryGroup]) {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: .sceneryGroups)
        }
    }

    func duplicateProfile(_ profile: PluginProfile) -> PluginProfile {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        return copy
    }

    // MARK: - Import & Export

    func exportProfile(_ profile: PluginProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    func exportAllProfiles(_ profiles: [PluginProfile]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profiles)
    }

    func importProfiles(from data: Data, existingProfiles: [PluginProfile]) throws -> [PluginProfile] {
        let decoder = JSONDecoder()
        var imported: [PluginProfile] = []

        if let single = try? decoder.decode(PluginProfile.self, from: data) {
            imported = [single]
        } else if let array = try? decoder.decode([PluginProfile].self, from: data) {
            imported = array
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Data is neither a valid single PluginProfile nor an array of PluginProfiles."
                )
            )
        }

        var result: [PluginProfile] = []
        var existingNames = Set(existingProfiles.map { $0.name.lowercased() })
        var existingIds = Set(existingProfiles.map { $0.id })

        for var profile in imported {
            // Ensure unique ID
            if existingIds.contains(profile.id) {
                profile.id = UUID()
            }
            existingIds.insert(profile.id)

            // Resolve name collisions
            let baseName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var uniqueName = baseName.isEmpty ? "Imported Profile" : baseName
            var counter = 1
            while existingNames.contains(uniqueName.lowercased()) {
                uniqueName = "\(baseName) (Imported\(counter > 1 ? " \(counter)" : ""))"
                counter += 1
            }
            profile.name = uniqueName
            existingNames.insert(uniqueName.lowercased())

            result.append(profile)
        }

        return result
    }

    // MARK: - Sorting

    func sortProfiles(_ profiles: [PluginProfile], by option: ProfileSortOption) -> [PluginProfile] {
        switch option {
        case .nameAsc:
            return profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .mostAddons:
            return profiles.sorted { totalAddonCount(for: $0) > totalAddonCount(for: $1) }
        case .leastAddons:
            return profiles.sorted { totalAddonCount(for: $0) < totalAddonCount(for: $1) }
        }
    }

    // MARK: - Add-on Purge

    func purgeAddons(
        pluginFolderNames: Set<String> = [],
        aircraftFolderNames: Set<String> = [],
        sceneryFolderNames: Set<String> = [],
        luaScriptFolderNames: Set<String> = [],
        from profiles: [PluginProfile]
    ) -> [PluginProfile] {
        var updated = profiles
        for i in 0..<updated.count {
            if !pluginFolderNames.isEmpty {
                updated[i].pluginFolderNames.removeAll { pluginFolderNames.contains($0) }
            }
            if !aircraftFolderNames.isEmpty {
                updated[i].aircraftFolderNames.removeAll { aircraftFolderNames.contains($0) }
            }
            if !sceneryFolderNames.isEmpty {
                updated[i].sceneryFolderNames.removeAll { sceneryFolderNames.contains($0) }
            }
            if !luaScriptFolderNames.isEmpty {
                updated[i].luaScriptFolderNames.removeAll { luaScriptFolderNames.contains($0) }
            }
        }
        return updated
    }

    private func totalAddonCount(for profile: PluginProfile) -> Int {
        profile.aircraftFolderNames.count +
        profile.pluginFolderNames.count +
        profile.sceneryFolderNames.count +
        profile.luaScriptFolderNames.count
    }
}

enum ProfileSortOption: String, CaseIterable, Identifiable, Sendable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case mostAddons = "Most Add-ons"
    case leastAddons = "Least Add-ons"

    var id: String { rawValue }
}

