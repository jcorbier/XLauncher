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

enum UserDefaultsKey: String, CaseIterable, Sendable {
    // Paths & Setup
    case xPlanePath = "XPlanePath"
    case launcherDataFolder = "LauncherDataFolder"
    case hasCompletedWelcome = "HasCompletedWelcome"

    // Profiles & Environment
    case pluginProfiles = "PluginProfiles"
    case selectedProfileId = "SelectedProfileId"
    case scriptEnvVars = "ScriptEnvVars"
    case sceneryGroups = "SceneryGroups"

    // Feature Flags & CSL / Navdata
    case enableCSLSupport = "EnableCSLSupport"
    case enableCSLXP12Lights = "EnableCSLXP12Lights"
    case enableNavdataSupport = "EnableNavdataSupport"
    case customNavdataAddonMappings = "CustomNavdataAddonMappings"
    case navigraphSession = "NavigraphSession"
    case navigraphSavedEmail = "NavigraphSavedEmail"

    // Addon Updates
    case autoCheckSkunkCraftsUpdates = "AutoCheckSkunkCraftsUpdates"
    case autoCheckXUpdaterUpdates = "AutoCheckXUpdaterUpdates"
    case autoCheckCSLUpdates = "AutoCheckCSLUpdates"
    case autoCheckNavdataUpdates = "AutoCheckNavdataUpdates"

    // App Updates
    case appUpdateAutoCheckOnLaunch = "AppUpdateAutoCheckOnLaunch"
    case appUpdateIncludePrereleases = "AppUpdateIncludePrereleases"
    case appUpdateLastCheckDate = "AppUpdateLastCheckDate"
    case appUpdateSkippedVersion = "AppUpdateSkippedVersion"
}

extension UserDefaults {
    func string(forKey key: UserDefaultsKey) -> String? {
        string(forKey: key.rawValue)
    }

    func bool(forKey key: UserDefaultsKey) -> Bool {
        bool(forKey: key.rawValue)
    }

    func data(forKey key: UserDefaultsKey) -> Data? {
        data(forKey: key.rawValue)
    }

    func object(forKey key: UserDefaultsKey) -> Any? {
        object(forKey: key.rawValue)
    }

    func set(_ value: Any?, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: Bool, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }

    func removeObject(forKey key: UserDefaultsKey) {
        removeObject(forKey: key.rawValue)
    }
}
