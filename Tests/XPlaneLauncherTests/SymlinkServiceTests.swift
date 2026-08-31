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

final class SymlinkServiceTests: XCTestCase {

    var tempDir: URL!
    var dataFolder: URL!
    var targetFolder: URL!
    let service = SymlinkService.shared
    let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("XLauncher_SymlinkTests_\(UUID().uuidString)")
        dataFolder = tempDir.appendingPathComponent("Data")
        targetFolder = tempDir.appendingPathComponent("Target")

        try fm.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: targetFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Plugins & Aircraft Tests

    func testScanAndTogglePlugins() throws {
        let pluginDir = dataFolder.appendingPathComponent("TerrainRadar")
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        // 1. Initial scan - should be disabled
        var list = try service.scanPlugins(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].name, "TerrainRadar")
        XCTAssertFalse(list[0].isEnabled)

        // 2. Enable plugin (creates symlink in targetFolder)
        try service.setPluginEnabled(folderName: "TerrainRadar", enabled: true, dataFolder: dataFolder, targetFolder: targetFolder)
        let linkURL = targetFolder.appendingPathComponent("TerrainRadar")
        XCTAssertTrue(fm.fileExists(atPath: linkURL.path))

        list = try service.scanPlugins(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertTrue(list[0].isEnabled)

        // 3. Disable plugin (removes symlink)
        try service.setPluginEnabled(folderName: "TerrainRadar", enabled: false, dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(fm.fileExists(atPath: linkURL.path))
        XCTAssertTrue(fm.fileExists(atPath: pluginDir.path), "Data folder original item must not be deleted")

        list = try service.scanPlugins(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(list[0].isEnabled)
    }

    func testScanAndToggleAircraft() throws {
        let acDir = dataFolder.appendingPathComponent("B738")
        try fm.createDirectory(at: acDir, withIntermediateDirectories: true)

        // 1. Enable aircraft
        try service.setAircraftEnabled(folderName: "B738", enabled: true, dataFolder: dataFolder, targetFolder: targetFolder)
        let linkURL = targetFolder.appendingPathComponent("B738")
        XCTAssertTrue(fm.fileExists(atPath: linkURL.path))

        var list = try service.scanAircraft(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(list[0].isEnabled)

        // 2. Disable aircraft
        try service.setAircraftEnabled(folderName: "B738", enabled: false, dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(fm.fileExists(atPath: linkURL.path))

        list = try service.scanAircraft(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(list[0].isEnabled)
    }

    // MARK: - FlyWithLua Scripts (Files & Bundles)

    func testScanAndToggleSingleLuaScript() throws {
        let scriptFile = dataFolder.appendingPathComponent("fps_counter.lua")
        try "print('fps')".write(to: scriptFile, atomically: true, encoding: .utf8)

        let scriptItem = LuaScript(name: "fps_counter.lua", isEnabled: false, folderName: "fps_counter.lua", isDirectory: false)

        // Enable
        try service.setLuaScriptEnabled(item: scriptItem, enabled: true, dataFolder: dataFolder, targetFolder: targetFolder)
        let linkURL = targetFolder.appendingPathComponent("fps_counter.lua")
        XCTAssertTrue(fm.fileExists(atPath: linkURL.path))

        let scanned = try service.scanLuaScripts(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertEqual(scanned.count, 1)
        XCTAssertTrue(scanned[0].isEnabled)
        XCTAssertFalse(scanned[0].isDirectory)

        // Disable
        try service.setLuaScriptEnabled(item: scriptItem, enabled: false, dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(fm.fileExists(atPath: linkURL.path))
    }

    func testScanAndToggleDirectoryLuaScriptBundle() throws {
        // A bundle folder contains child scripts/assets linked individually into the FlyWithLua target folder
        let bundleDir = dataFolder.appendingPathComponent("MyBundle")
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let child1 = bundleDir.appendingPathComponent("subscript1.lua")
        let child2 = bundleDir.appendingPathComponent("subscript2.lua")
        try "-- sub 1".write(to: child1, atomically: true, encoding: .utf8)
        try "-- sub 2".write(to: child2, atomically: true, encoding: .utf8)

        let bundleItem = LuaScript(name: "MyBundle", isEnabled: false, folderName: "MyBundle", isDirectory: true)

        // Enable bundle
        try service.setLuaScriptEnabled(item: bundleItem, enabled: true, dataFolder: dataFolder, targetFolder: targetFolder)
        let childLink1 = targetFolder.appendingPathComponent("subscript1.lua")
        let childLink2 = targetFolder.appendingPathComponent("subscript2.lua")

        XCTAssertTrue(fm.fileExists(atPath: childLink1.path))
        XCTAssertTrue(fm.fileExists(atPath: childLink2.path))

        let scanned = try service.scanLuaScripts(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertEqual(scanned.count, 1)
        XCTAssertTrue(scanned[0].isEnabled)
        XCTAssertTrue(scanned[0].isDirectory)

        // Disable bundle
        try service.setLuaScriptEnabled(item: bundleItem, enabled: false, dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(fm.fileExists(atPath: childLink1.path))
        XCTAssertFalse(fm.fileExists(atPath: childLink2.path))
    }

    // MARK: - Structured FlyWithLua Addons (Scripts & Modules)

    func testScanAndToggleStructuredLuaScriptWithScriptsOnlyAndSkunkCraftsConfig() throws {
        let addonDir = dataFolder.appendingPathComponent("ChecklistAddon")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let cfgFile = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let whitelistFile = addonDir.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
        try "name|Checklist".write(to: cfgFile, atomically: true, encoding: .utf8)
        try "whitelist".write(to: whitelistFile, atomically: true, encoding: .utf8)

        let scriptsSubdir = addonDir.appendingPathComponent("Scripts")
        try fm.createDirectory(at: scriptsSubdir, withIntermediateDirectories: true)
        let mainScript = scriptsSubdir.appendingPathComponent("checklist_main.lua")
        let helperScript = scriptsSubdir.appendingPathComponent("checklist_helper.lua")
        try "-- main".write(to: mainScript, atomically: true, encoding: .utf8)
        try "-- helper".write(to: helperScript, atomically: true, encoding: .utf8)

        // Verify link sources detection
        let scriptSources = service.luaScriptLinkSources(in: dataFolder)
        XCTAssertEqual(scriptSources.count, 2)
        XCTAssertEqual(scriptSources["checklist_main.lua"]?.resolvingSymlinksInPath().path, mainScript.resolvingSymlinksInPath().path)
        XCTAssertEqual(scriptSources["checklist_helper.lua"]?.resolvingSymlinksInPath().path, helperScript.resolvingSymlinksInPath().path)
        XCTAssertNil(scriptSources["skunkcrafts_updater.cfg"])
        XCTAssertNil(scriptSources["Scripts"])

        let moduleSources = service.luaModuleLinkSources(in: dataFolder)
        XCTAssertTrue(moduleSources.isEmpty)

        let item = LuaScript(name: "ChecklistAddon", isEnabled: false, folderName: "ChecklistAddon", isDirectory: true)

        // Enable
        try service.setLuaScriptEnabled(item: item, enabled: true, dataFolder: dataFolder, targetFolder: targetFolder)

        let link1 = targetFolder.appendingPathComponent("checklist_main.lua")
        let link2 = targetFolder.appendingPathComponent("checklist_helper.lua")
        let wrongCfgLink = targetFolder.appendingPathComponent("skunkcrafts_updater.cfg")
        let wrongScriptsDirLink = targetFolder.appendingPathComponent("Scripts")

        XCTAssertTrue(fm.fileExists(atPath: link1.path))
        XCTAssertTrue(fm.fileExists(atPath: link2.path))
        XCTAssertFalse(fm.fileExists(atPath: wrongCfgLink.path))
        XCTAssertFalse(fm.fileExists(atPath: wrongScriptsDirLink.path))

        // Scan
        let scanned = try service.scanLuaScripts(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned[0].name, "ChecklistAddon")
        XCTAssertTrue(scanned[0].isEnabled)

        // Disable
        try service.setLuaScriptEnabled(item: item, enabled: false, dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(fm.fileExists(atPath: link1.path))
        XCTAssertFalse(fm.fileExists(atPath: link2.path))

        let scannedAfterDisable = try service.scanLuaScripts(dataFolder: dataFolder, targetFolder: targetFolder)
        XCTAssertFalse(scannedAfterDisable[0].isEnabled)
    }

    func testScanAndToggleStructuredLuaScriptWithScriptsAndModules() throws {
        let scriptsFolder = tempDir.appendingPathComponent("FlyWithLua").appendingPathComponent("Scripts")
        let modulesFolder = tempDir.appendingPathComponent("FlyWithLua").appendingPathComponent("Modules")
        try fm.createDirectory(at: scriptsFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: modulesFolder, withIntermediateDirectories: true)

        let addonDir = dataFolder.appendingPathComponent("AdvancedLuaAddon")
        let scriptsSubdir = addonDir.appendingPathComponent("Scripts")
        let modulesSubdir = addonDir.appendingPathComponent("Modules")
        try fm.createDirectory(at: scriptsSubdir, withIntermediateDirectories: true)
        try fm.createDirectory(at: modulesSubdir, withIntermediateDirectories: true)

        let cfgFile = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        try "name|Advanced".write(to: cfgFile, atomically: true, encoding: .utf8)

        let actionScript = scriptsSubdir.appendingPathComponent("action.lua")
        let libModule = modulesSubdir.appendingPathComponent("lib.lua")
        try "-- action".write(to: actionScript, atomically: true, encoding: .utf8)
        try "-- lib".write(to: libModule, atomically: true, encoding: .utf8)

        // Check source indexing
        let scriptSources = service.luaScriptLinkSources(in: dataFolder)
        XCTAssertEqual(scriptSources["action.lua"]?.resolvingSymlinksInPath().path, actionScript.resolvingSymlinksInPath().path)
        XCTAssertNil(scriptSources["lib.lua"])

        let moduleSources = service.luaModuleLinkSources(in: dataFolder)
        XCTAssertEqual(moduleSources["lib.lua"]?.resolvingSymlinksInPath().path, libModule.resolvingSymlinksInPath().path)
        XCTAssertNil(moduleSources["action.lua"])

        let item = LuaScript(name: "AdvancedLuaAddon", isEnabled: false, folderName: "AdvancedLuaAddon", isDirectory: true)

        // Enable
        try service.setLuaScriptEnabled(item: item, enabled: true, dataFolder: dataFolder, targetFolder: scriptsFolder, modulesTargetFolder: modulesFolder)

        let scriptLink = scriptsFolder.appendingPathComponent("action.lua")
        let moduleLink = modulesFolder.appendingPathComponent("lib.lua")
        let wrongCfgLink = scriptsFolder.appendingPathComponent("skunkcrafts_updater.cfg")

        XCTAssertTrue(fm.fileExists(atPath: scriptLink.path))
        XCTAssertTrue(fm.fileExists(atPath: moduleLink.path))
        XCTAssertFalse(fm.fileExists(atPath: wrongCfgLink.path))

        // Scan
        let scanned = try service.scanLuaScripts(dataFolder: dataFolder, targetFolder: scriptsFolder, modulesTargetFolder: modulesFolder)
        XCTAssertEqual(scanned.count, 1)
        XCTAssertTrue(scanned[0].isEnabled)

        // Disable
        try service.setLuaScriptEnabled(item: item, enabled: false, dataFolder: dataFolder, targetFolder: scriptsFolder, modulesTargetFolder: modulesFolder)
        XCTAssertFalse(fm.fileExists(atPath: scriptLink.path))
        XCTAssertFalse(fm.fileExists(atPath: moduleLink.path))
    }

    // MARK: - Stale Link Repair Tests

    func testRepairStaleLinks() throws {
        // Create an old location and a new location
        let oldDataDir = tempDir.appendingPathComponent("OldData")
        let newDataDir = tempDir.appendingPathComponent("NewData")
        try fm.createDirectory(at: oldDataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: newDataDir, withIntermediateDirectories: true)

        let addonAOld = oldDataDir.appendingPathComponent("AddonA")
        try fm.createDirectory(at: addonAOld, withIntermediateDirectories: true)

        // Create link pointing to old location
        let linkA = targetFolder.appendingPathComponent("AddonA")
        try fm.createSymbolicLink(at: linkA, withDestinationURL: addonAOld)

        // Now move/delete old location, create AddonA in newDataDir
        try fm.removeItem(at: oldDataDir)
        let addonANew = newDataDir.appendingPathComponent("AddonA")
        try fm.createDirectory(at: addonANew, withIntermediateDirectories: true)

        // Link is now broken (fileExists resolves to false)
        XCTAssertFalse(fm.fileExists(atPath: linkA.path))

        // Get sources and repair
        let sources = service.linkSources(in: newDataDir)
        let repaired = service.repairStaleLinks(in: targetFolder, using: sources)

        XCTAssertEqual(repaired, ["AddonA"])
        XCTAssertTrue(fm.fileExists(atPath: linkA.path), "Repaired link should now resolve to new source")
        let destination = try fm.destinationOfSymbolicLink(atPath: linkA.path)
        XCTAssertEqual(URL(fileURLWithPath: destination).resolvingSymlinksInPath().path, addonANew.resolvingSymlinksInPath().path)
    }

    func testRepairStaleLinksForStructuredLuaScriptsAndModules() throws {
        let oldDataDir = tempDir.appendingPathComponent("OldData")
        let newDataDir = tempDir.appendingPathComponent("NewData")
        let scriptsFolder = tempDir.appendingPathComponent("FlyWithLua").appendingPathComponent("Scripts")
        let modulesFolder = tempDir.appendingPathComponent("FlyWithLua").appendingPathComponent("Modules")
        try fm.createDirectory(at: oldDataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: newDataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: scriptsFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: modulesFolder, withIntermediateDirectories: true)

        let oldAddon = oldDataDir.appendingPathComponent("MyLua")
        let oldScripts = oldAddon.appendingPathComponent("Scripts")
        let oldModules = oldAddon.appendingPathComponent("Modules")
        try fm.createDirectory(at: oldScripts, withIntermediateDirectories: true)
        try fm.createDirectory(at: oldModules, withIntermediateDirectories: true)

        let oldScriptFile = oldScripts.appendingPathComponent("myscript.lua")
        let oldModuleFile = oldModules.appendingPathComponent("mymodule.lua")
        try "old script".write(to: oldScriptFile, atomically: true, encoding: .utf8)
        try "old module".write(to: oldModuleFile, atomically: true, encoding: .utf8)

        // Point links to old location
        let scriptLink = scriptsFolder.appendingPathComponent("myscript.lua")
        let moduleLink = modulesFolder.appendingPathComponent("mymodule.lua")
        try fm.createSymbolicLink(at: scriptLink, withDestinationURL: oldScriptFile)
        try fm.createSymbolicLink(at: moduleLink, withDestinationURL: oldModuleFile)

        // Delete old location, create new location in newDataDir
        try fm.removeItem(at: oldDataDir)
        let newAddon = newDataDir.appendingPathComponent("MyLua")
        let newScripts = newAddon.appendingPathComponent("Scripts")
        let newModules = newAddon.appendingPathComponent("Modules")
        try fm.createDirectory(at: newScripts, withIntermediateDirectories: true)
        try fm.createDirectory(at: newModules, withIntermediateDirectories: true)

        let newScriptFile = newScripts.appendingPathComponent("myscript.lua")
        let newModuleFile = newModules.appendingPathComponent("mymodule.lua")
        try "new script".write(to: newScriptFile, atomically: true, encoding: .utf8)
        try "new module".write(to: newModuleFile, atomically: true, encoding: .utf8)

        // Verify links are stale
        XCTAssertFalse(fm.fileExists(atPath: scriptLink.path))
        XCTAssertFalse(fm.fileExists(atPath: moduleLink.path))

        // Repair script links
        let scriptSources = service.luaScriptLinkSources(in: newDataDir)
        let repairedScripts = service.repairStaleLinks(in: scriptsFolder, using: scriptSources)
        XCTAssertEqual(repairedScripts, ["myscript.lua"])
        XCTAssertTrue(fm.fileExists(atPath: scriptLink.path))

        // Repair module links
        let moduleSources = service.luaModuleLinkSources(in: newDataDir)
        let repairedModules = service.repairStaleLinks(in: modulesFolder, using: moduleSources)
        XCTAssertEqual(repairedModules, ["mymodule.lua"])
        XCTAssertTrue(fm.fileExists(atPath: moduleLink.path))
    }
}
