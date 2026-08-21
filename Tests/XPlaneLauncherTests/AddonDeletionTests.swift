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
final class AddonDeletionTests: XCTestCase {

    var tempDir: URL!
    var dataFolder: URL!
    var xPlaneFolder: URL!
    var pluginManager: PluginManager!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XLauncher_DeleteTests_\(UUID().uuidString)")
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
        UserDefaults.standard.removeObject(forKey: .selectedProfileId)

        pluginManager = PluginManager()
        pluginManager.launcherDataFolder = dataFolder
        pluginManager.xPlanePath = xPlaneFolder
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: .pluginProfiles)
        UserDefaults.standard.removeObject(forKey: .sceneryGroups)
        UserDefaults.standard.removeObject(forKey: .selectedProfileId)
        try await super.tearDown()
    }

    func testDeletePluginPurgesProfilesAndFiles() throws {
        let pluginName = "TestPlugin"
        let pluginFolder = PathService.shared.dataFolder(.plugins, in: dataFolder).appendingPathComponent(pluginName)
        try FileManager.default.createDirectory(at: pluginFolder, withIntermediateDirectories: true)

        let profile1 = PluginProfile(name: "P1", pluginFolderNames: [pluginName, "OtherPlugin"])
        let profile2 = PluginProfile(name: "P2", pluginFolderNames: [pluginName])
        let profile3 = PluginProfile(name: "P3", pluginFolderNames: ["OtherPlugin"])
        pluginManager.profiles = [profile1, profile2, profile3]
        ProfileService.shared.saveProfiles([profile1, profile2, profile3])

        pluginManager.scanPlugins()
        guard let plugin = pluginManager.plugins.first(where: { $0.folderName == pluginName }) else {
            XCTFail("Plugin not found after scan")
            return
        }

        pluginManager.togglePlugin(plugin)
        let linkURL = PathService.shared.pluginsTargetFolder(for: xPlaneFolder).appendingPathComponent(pluginName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkURL.path))

        pluginManager.deletePlugin(plugin)

        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginFolder.path), "Central Data Folder plugin directory should be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkURL.path), "Symlink should be removed from X-Plane")
        XCTAssertFalse(pluginManager.plugins.contains(where: { $0.folderName == pluginName }))

        let savedProfiles = ProfileService.shared.loadProfiles()
        XCTAssertEqual(savedProfiles[0].pluginFolderNames, ["OtherPlugin"])
        XCTAssertEqual(savedProfiles[1].pluginFolderNames, [])
        XCTAssertEqual(savedProfiles[2].pluginFolderNames, ["OtherPlugin"])
    }

    func testDeleteAircraftPurgesProfilesAndFiles() throws {
        let acName = "Boeing737"
        let acFolder = PathService.shared.dataFolder(.aircraft, in: dataFolder).appendingPathComponent(acName)
        try FileManager.default.createDirectory(at: acFolder, withIntermediateDirectories: true)

        let profile1 = PluginProfile(name: "P1", pluginFolderNames: [], aircraftFolderNames: [acName, "A320"])
        pluginManager.profiles = [profile1]
        ProfileService.shared.saveProfiles([profile1])

        pluginManager.scanAircraft()
        guard let aircraft = pluginManager.aircraft.first(where: { $0.folderName == acName }) else {
            XCTFail("Aircraft not found after scan")
            return
        }

        pluginManager.toggleAircraft(aircraft)
        let linkURL = PathService.shared.aircraftTargetFolder(for: xPlaneFolder).appendingPathComponent(acName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkURL.path))

        pluginManager.deleteAircraft(aircraft)

        XCTAssertFalse(FileManager.default.fileExists(atPath: acFolder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkURL.path))
        XCTAssertFalse(pluginManager.aircraft.contains(where: { $0.folderName == acName }))

        let savedProfiles = ProfileService.shared.loadProfiles()
        XCTAssertEqual(savedProfiles[0].aircraftFolderNames, ["A320"])
    }

    func testDeleteLuaScriptPurgesProfilesAndFiles() throws {
        let scriptName = "speedbrake.lua"
        let scriptFile = PathService.shared.dataFolder(.luaScripts, in: dataFolder).appendingPathComponent(scriptName)
        try "print('hello')".write(to: scriptFile, atomically: true, encoding: .utf8)

        let profile1 = PluginProfile(name: "P1", pluginFolderNames: [], luaScriptFolderNames: [scriptName])
        pluginManager.profiles = [profile1]
        ProfileService.shared.saveProfiles([profile1])

        pluginManager.scanLuaScripts()
        guard let script = pluginManager.luaScripts.first(where: { $0.folderName == scriptName }) else {
            XCTFail("Lua script not found")
            return
        }

        pluginManager.toggleLuaScript(script)
        let linkURL = PathService.shared.flyWithLuaScriptsFolder(for: xPlaneFolder).appendingPathComponent(scriptName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkURL.path))

        pluginManager.deleteLuaScript(script)

        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkURL.path))
        XCTAssertFalse(pluginManager.luaScripts.contains(where: { $0.folderName == scriptName }))

        let savedProfiles = ProfileService.shared.loadProfiles()
        XCTAssertEqual(savedProfiles[0].luaScriptFolderNames, [])
    }

    func testDeleteManagedSceneryPurgesProfilesAndGroups() throws {
        let sceneryName = "LFPG_Airport"
        let sceneryFolder = PathService.shared.dataFolder(.scenery, in: dataFolder).appendingPathComponent(sceneryName)
        try FileManager.default.createDirectory(at: sceneryFolder, withIntermediateDirectories: true)

        let group = SceneryGroup(name: "France", childFolderNames: [sceneryName, "LFMN_Airport"])
        pluginManager.sceneryGroups = [group]
        ProfileService.shared.saveSceneryGroups([group])

        let profile1 = PluginProfile(name: "P1", pluginFolderNames: [], sceneryFolderNames: [sceneryName])
        pluginManager.profiles = [profile1]
        ProfileService.shared.saveProfiles([profile1])

        pluginManager.scanScenery()
        guard let item = pluginManager.scenery.first(where: { $0.folderName == sceneryName }) else {
            XCTFail("Scenery not found")
            return
        }

        pluginManager.toggleScenery(item)
        let linkURL = PathService.shared.customSceneryFolder(for: xPlaneFolder).appendingPathComponent(sceneryName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkURL.path))

        guard let managedItem = pluginManager.scenery.first(where: { $0.folderName == sceneryName }) else {
            XCTFail("Scenery not found after toggle")
            return
        }
        XCTAssertTrue(managedItem.isManaged)

        pluginManager.deleteScenery(managedItem)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sceneryFolder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkURL.path))
        XCTAssertFalse(pluginManager.scenery.contains(where: { $0.folderName == sceneryName }))

        let savedProfiles = ProfileService.shared.loadProfiles()
        XCTAssertEqual(savedProfiles[0].sceneryFolderNames, [])

        let savedGroups = ProfileService.shared.loadSceneryGroups()
        XCTAssertEqual(savedGroups[0].childFolderNames, ["LFMN_Airport"])
    }

    func testDeleteUnmanagedSceneryIsBlocked() throws {
        let unmanagedItem = Scenery(
            name: "Global_Airports",
            isEnabled: true,
            folderName: "Global_Airports",
            isManaged: false,
            iniLine: "SCENERY_PACK Custom Scenery/Global_Airports/"
        )

        pluginManager.scenery = [unmanagedItem]
        pluginManager.deleteScenery(unmanagedItem)

        XCTAssertNotNil(pluginManager.lastErrorMessage)
        XCTAssertTrue(pluginManager.lastErrorMessage?.contains("Cannot delete unmanaged scenery") == true)
        XCTAssertEqual(pluginManager.scenery.count, 1)
    }
}
