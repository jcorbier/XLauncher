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

import XCTest
@testable import XPlaneLauncher

@MainActor
final class ProfileManagementTests: XCTestCase {

    var tempDir: URL!
    var dataFolder: URL!
    var xPlaneFolder: URL!
    var pluginManager: PluginManager!
    let profileService = ProfileService.shared

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XLauncher_ProfileTests_\(UUID().uuidString)")
        dataFolder = tempDir.appendingPathComponent("Data")
        xPlaneFolder = tempDir.appendingPathComponent("XPlane")

        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xPlaneFolder, withIntermediateDirectories: true)

        PathService.shared.ensureDirectories(for: dataFolder)
        try FileManager.default.createDirectory(at: PathService.shared.pluginsTargetFolder(for: xPlaneFolder), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: PathService.shared.aircraftTargetFolder(for: xPlaneFolder), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: PathService.shared.customSceneryFolder(for: xPlaneFolder), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: PathService.shared.flyWithLuaScriptsFolder(for: xPlaneFolder), withIntermediateDirectories: true)

        UserDefaults.standard.removeObject(forKey: .pluginProfiles)
        UserDefaults.standard.removeObject(forKey: .sceneryGroups)
        UserDefaults.standard.removeObject(forKey: .scriptEnvVars)
        UserDefaults.standard.removeObject(forKey: .selectedProfileId)

        pluginManager = PluginManager()
        pluginManager.launcherDataFolder = dataFolder
        pluginManager.xPlanePath = xPlaneFolder
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: .pluginProfiles)
        UserDefaults.standard.removeObject(forKey: .sceneryGroups)
        UserDefaults.standard.removeObject(forKey: .scriptEnvVars)
        UserDefaults.standard.removeObject(forKey: .selectedProfileId)
        try await super.tearDown()
    }

    // MARK: - Profile Duplication & Persistence

    func testDuplicateProfile() {
        let script = ProfileScript(path: "/bin/test.sh", isEnabled: true)
        let envVar = ScriptEnvVar(key: "VATSIM", value: "1")
        let original = PluginProfile(
            name: "IFR Flight",
            pluginFolderNames: ["TerrainRadar", "BetterPushback"],
            sceneryFolderNames: ["LFPG"],
            aircraftFolderNames: ["A320"],
            luaScriptFolderNames: ["script.lua"],
            scripts: [script],
            environmentVariables: [envVar]
        )

        let duplicate = profileService.duplicateProfile(original)

        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertEqual(duplicate.name, "IFR Flight Copy")
        XCTAssertEqual(duplicate.pluginFolderNames, original.pluginFolderNames)
        XCTAssertEqual(duplicate.sceneryFolderNames, original.sceneryFolderNames)
        XCTAssertEqual(duplicate.aircraftFolderNames, original.aircraftFolderNames)
        XCTAssertEqual(duplicate.luaScriptFolderNames, original.luaScriptFolderNames)
        XCTAssertEqual(duplicate.scripts.count, original.scripts.count)
        XCTAssertEqual(duplicate.environmentVariables.count, original.environmentVariables.count)
    }

    func testProfileEncodingAndDecodingWithLegacyShellScript() throws {
        // Legacy JSON schema with single shellScriptPath instead of scripts array
        let legacyJson = """
        [
            {
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "name": "LegacyProfile",
                "pluginFolderNames": ["PluginA"],
                "sceneryFolderNames": [],
                "aircraftFolderNames": [],
                "luaScriptFolderNames": [],
                "shellScriptPath": "/Users/test/start.sh"
            }
        ]
        """

        let decoded = try JSONDecoder().decode([PluginProfile].self, from: legacyJson.data(using: .utf8)!)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "LegacyProfile")
        XCTAssertEqual(decoded[0].shellScriptPath, "/Users/test/start.sh")
        XCTAssertTrue(decoded[0].scripts.isEmpty)
    }

    // MARK: - Profile State & Modification Detection

    func testModificationDetection() {
        let profile = PluginProfile(
            name: "VFR",
            pluginFolderNames: ["PluginA"],
            sceneryFolderNames: ["SceneryA"],
            aircraftFolderNames: ["Cessna"],
            luaScriptFolderNames: ["vfr.lua"],
            scripts: [ProfileScript(path: "/path/to/script.sh", isEnabled: true)],
            environmentVariables: [ScriptEnvVar(key: "MY_VAR", value: "100")]
        )

        pluginManager.profiles = [profile]
        pluginManager.selectedProfileId = profile.id

        // Populate items in manager matching profile
        let pluginA = Plugin(name: "PluginA", isEnabled: true, folderName: "PluginA")
        let pluginB = Plugin(name: "PluginB", isEnabled: false, folderName: "PluginB")
        pluginManager.plugins = [pluginA, pluginB]

        let sceneryA = Scenery(name: "SceneryA", isEnabled: true, folderName: "SceneryA", isManaged: true, isInIni: true, iniLine: "")
        pluginManager.scenery = [sceneryA]

        let aircraftA = Aircraft(name: "Cessna", isEnabled: true, folderName: "Cessna")
        pluginManager.aircraft = [aircraftA]

        let luaA = LuaScript(name: "vfr.lua", isEnabled: true, folderName: "vfr.lua")
        pluginManager.luaScripts = [luaA]

        pluginManager.activeScripts = profile.scripts
        pluginManager.activeEnvironmentVariables = profile.environmentVariables

        // 1. Pristine state
        XCTAssertFalse(pluginManager.isCurrentProfileModified)
        XCTAssertFalse(pluginManager.isPluginModified(pluginA))
        XCTAssertFalse(pluginManager.isSceneryModified(sceneryA))
        XCTAssertFalse(pluginManager.isAircraftModified(aircraftA))
        XCTAssertFalse(pluginManager.isLuaScriptModified(luaA))

        // 2. Modify plugin state
        pluginManager.plugins[0].isEnabled = false
        XCTAssertTrue(pluginManager.isPluginModified(pluginManager.plugins[0]))
        XCTAssertTrue(pluginManager.isCurrentProfileModified)

        // Restore
        pluginManager.plugins[0].isEnabled = true
        XCTAssertFalse(pluginManager.isCurrentProfileModified)

        // 3. Modify environment variable
        pluginManager.activeEnvironmentVariables[0].value = "200"
        XCTAssertTrue(pluginManager.isEnvVarModified(pluginManager.activeEnvironmentVariables[0]))
        XCTAssertTrue(pluginManager.isCurrentProfileModified)
    }
}
