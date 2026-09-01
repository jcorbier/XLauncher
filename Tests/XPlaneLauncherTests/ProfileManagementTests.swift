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

        let sceneryA = Scenery(name: "SceneryA", isEnabled: true, folderName: "SceneryA", isManaged: true, iniLine: "")
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

    // MARK: - Missing Addon Detection

    func testMissingAddonDetection() {
        let profile = PluginProfile(
            name: "Test Profile",
            pluginFolderNames: ["InstalledPlugin", "MissingPlugin"],
            sceneryFolderNames: ["MissingScenery"],
            aircraftFolderNames: ["InstalledAircraft"],
            luaScriptFolderNames: ["MissingLua.lua"]
        )

        pluginManager.plugins = [Plugin(name: "InstalledPlugin", isEnabled: true, folderName: "InstalledPlugin")]
        pluginManager.scenery = []
        pluginManager.aircraft = [Aircraft(name: "InstalledAircraft", isEnabled: true, folderName: "InstalledAircraft")]
        pluginManager.luaScripts = []

        XCTAssertTrue(pluginManager.hasMissingAddons(for: profile))

        let missing = pluginManager.missingAddons(for: profile)
        XCTAssertEqual(missing[.plugins], ["MissingPlugin"])
        XCTAssertEqual(missing[.scenery], ["MissingScenery"])
        XCTAssertEqual(missing[.luaScripts], ["MissingLua.lua"])
        XCTAssertNil(missing[.aircraft])
    }

    // MARK: - Import & Export

    func testProfileExportAndImportSingle() throws {
        let original = PluginProfile(
            name: "OriginalProfile",
            pluginFolderNames: ["Plugin1", "Plugin2"],
            sceneryFolderNames: ["Scenery1"],
            aircraftFolderNames: ["Plane1"],
            luaScriptFolderNames: ["script.lua"]
        )

        let data = try profileService.exportProfile(original)
        XCTAssertFalse(data.isEmpty)

        let imported = try profileService.importProfiles(from: data, existingProfiles: [])
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].name, "OriginalProfile")
        XCTAssertEqual(imported[0].pluginFolderNames, original.pluginFolderNames)
        XCTAssertEqual(imported[0].sceneryFolderNames, original.sceneryFolderNames)
        XCTAssertEqual(imported[0].aircraftFolderNames, original.aircraftFolderNames)
        XCTAssertEqual(imported[0].luaScriptFolderNames, original.luaScriptFolderNames)
    }

    func testProfileExportAndImportMultiple() throws {
        let p1 = PluginProfile(name: "Profile 1", pluginFolderNames: ["A"])
        let p2 = PluginProfile(name: "Profile 2", pluginFolderNames: ["B"])

        let data = try profileService.exportAllProfiles([p1, p2])
        let imported = try profileService.importProfiles(from: data, existingProfiles: [])

        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].name, "Profile 1")
        XCTAssertEqual(imported[1].name, "Profile 2")
    }

    func testProfileImportNameCollision() throws {
        let existing = [
            PluginProfile(name: "Airliner", pluginFolderNames: []),
            PluginProfile(name: "Airliner (Imported)", pluginFolderNames: [])
        ]

        let toImport = PluginProfile(name: "Airliner", pluginFolderNames: ["NewPlugin"])
        let data = try profileService.exportProfile(toImport)

        let imported = try profileService.importProfiles(from: data, existingProfiles: existing)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].name, "Airliner (Imported 2)")
    }

    // MARK: - Reorder, Sort, and Rename

    func testReorderProfiles() {
        let p1 = PluginProfile(name: "First", pluginFolderNames: [])
        let p2 = PluginProfile(name: "Second", pluginFolderNames: [])
        let p3 = PluginProfile(name: "Third", pluginFolderNames: [])

        pluginManager.profiles = [p1, p2, p3]
        pluginManager.reorderProfiles(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(pluginManager.profiles.map { $0.name }, ["Third", "First", "Second"])
    }

    func testSortProfiles() {
        let p1 = PluginProfile(name: "Charlie", pluginFolderNames: ["A", "B", "C"])
        let p2 = PluginProfile(name: "Alpha", pluginFolderNames: ["A"])
        let p3 = PluginProfile(name: "Bravo", pluginFolderNames: ["A", "B"])

        pluginManager.profiles = [p1, p2, p3]

        pluginManager.sortProfiles(by: .nameAsc)
        XCTAssertEqual(pluginManager.profiles.map { $0.name }, ["Alpha", "Bravo", "Charlie"])

        pluginManager.sortProfiles(by: .nameDesc)
        XCTAssertEqual(pluginManager.profiles.map { $0.name }, ["Charlie", "Bravo", "Alpha"])

        pluginManager.sortProfiles(by: .mostAddons)
        XCTAssertEqual(pluginManager.profiles.map { $0.name }, ["Charlie", "Bravo", "Alpha"])

        pluginManager.sortProfiles(by: .leastAddons)
        XCTAssertEqual(pluginManager.profiles.map { $0.name }, ["Alpha", "Bravo", "Charlie"])
    }

    func testRenameProfile() {
        let p1 = PluginProfile(name: "OldName", pluginFolderNames: [])
        pluginManager.profiles = [p1]

        pluginManager.renameProfile(p1, newName: "NewName")
        XCTAssertEqual(pluginManager.profiles.first?.name, "NewName")
    }
}

