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
}
