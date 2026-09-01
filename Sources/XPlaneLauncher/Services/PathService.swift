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

/// The subfolders holding source add-ons inside the central data folder.
/// These are launcher-side names and differ from the X-Plane target folders
/// they are linked into (`Custom Scenery`, `Resources/plugins/FlyWithLua/Scripts`).
enum DataSubfolder: String, CaseIterable, Sendable {
    case aircraft = "Aircraft"
    case plugins = "Plugins"
    case scenery = "Scenery"
    case luaScripts = "LuaScripts"
}

final class PathService: Sendable {
    static let shared = PathService()

    private var fileManager: FileManager { FileManager.default }

    static var defaultLauncherDataFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("XPlaneLauncher")
    }

    func dataFolder(_ subfolder: DataSubfolder, in launcherDataFolder: URL) -> URL {
        launcherDataFolder.appendingPathComponent(subfolder.rawValue)
    }

    func ensureDirectories(for launcherDataFolder: URL) {
        for subfolder in DataSubfolder.allCases {
            let path = dataFolder(subfolder, in: launcherDataFolder)
            if !fileManager.fileExists(atPath: path.path) {
                try? fileManager.createDirectory(at: path, withIntermediateDirectories: true)
            }
        }
    }

    func ensureDirectories(for pools: [StoragePool]) {
        for pool in pools where pool.isOnline {
            ensureDirectories(for: pool.url)
        }
    }

    func pluginsTargetFolder(for xPlanePath: URL) -> URL {
        xPlanePath.appendingPathComponent("Resources").appendingPathComponent("plugins")
    }

    func aircraftTargetFolder(for xPlanePath: URL) -> URL {
        xPlanePath.appendingPathComponent("Aircraft")
    }

    func customSceneryFolder(for xPlanePath: URL) -> URL {
        xPlanePath.appendingPathComponent("Custom Scenery")
    }

    func sceneryPacksIniURL(for xPlanePath: URL) -> URL {
        customSceneryFolder(for: xPlanePath).appendingPathComponent("scenery_packs.ini")
    }

    func flyWithLuaFolder(for xPlanePath: URL) -> URL {
        xPlanePath.appendingPathComponent("Resources").appendingPathComponent("plugins").appendingPathComponent("FlyWithLua")
    }

    func flyWithLuaScriptsFolder(for xPlanePath: URL) -> URL {
        flyWithLuaFolder(for: xPlanePath).appendingPathComponent("Scripts")
    }

    func flyWithLuaModulesFolder(for xPlanePath: URL) -> URL {
        flyWithLuaFolder(for: xPlanePath).appendingPathComponent("Modules")
    }

    func cslFolder(for xPlanePath: URL) -> URL {
        xPlanePath.appendingPathComponent("Resources").appendingPathComponent("plugins").appendingPathComponent("IVAO_CSL").appendingPathComponent("CSL")
    }

    func logTxtURL(for xPlanePath: URL) -> URL {
        xPlanePath.appendingPathComponent("Log.txt")
    }

    func logArchiveFolder(for xPlanePath: URL) -> URL {
        xPlanePath.appendingPathComponent("Output").appendingPathComponent("Log Archive")
    }

    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
