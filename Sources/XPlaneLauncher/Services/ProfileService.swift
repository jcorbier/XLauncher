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
}
