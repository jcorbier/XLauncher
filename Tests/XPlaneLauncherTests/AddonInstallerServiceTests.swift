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

final class AddonInstallerServiceTests: XCTestCase {

    var tempDir: URL!
    var dataFolder: URL!
    let installerService = AddonInstallerService.shared
    let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("XLauncher_InstallerTests_\(UUID().uuidString)")
        dataFolder = tempDir.appendingPathComponent("Data")
        try fm.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        PathService.shared.ensureDirectories(for: dataFolder)
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Directory Category Detection Tests

    func testAnalyzeAircraftDirectory() async throws {
        let acDir = tempDir.appendingPathComponent("Boeing737")
        try fm.createDirectory(at: acDir, withIntermediateDirectories: true)
        let acfFile = acDir.appendingPathComponent("B737.acf")
        try "ACF DATA".write(to: acfFile, atomically: true, encoding: .utf8)

        let analysis = try await installerService.analyze(url: acDir)
        XCTAssertEqual(analysis.detectedCategory, .aircraft)
        XCTAssertEqual(analysis.suggestedPackageName, "Boeing737")
        XCTAssertFalse(analysis.isArchive)
    }

    func testAnalyzeSceneryDirectory() async throws {
        let sceneryDir = tempDir.appendingPathComponent("LFPO_Airport")
        let navDataDir = sceneryDir.appendingPathComponent("Earth nav data")
        try fm.createDirectory(at: navDataDir, withIntermediateDirectories: true)
        let aptDat = sceneryDir.appendingPathComponent("apt.dat")
        try "APT DATA".write(to: aptDat, atomically: true, encoding: .utf8)

        let analysis = try await installerService.analyze(url: sceneryDir)
        XCTAssertEqual(analysis.detectedCategory, .scenery)
        XCTAssertEqual(analysis.suggestedPackageName, "LFPO_Airport")
    }

    func testAnalyzePluginDirectory() async throws {
        let pluginDir = tempDir.appendingPathComponent("TerrainRadar")
        let macDir = pluginDir.appendingPathComponent("mac_x64")
        try fm.createDirectory(at: macDir, withIntermediateDirectories: true)
        let xplFile = macDir.appendingPathComponent("TerrainRadar.xpl")
        try "BINARY DATA".write(to: xplFile, atomically: true, encoding: .utf8)

        let analysis = try await installerService.analyze(url: pluginDir)
        XCTAssertEqual(analysis.detectedCategory, .plugins)
        XCTAssertEqual(analysis.suggestedPackageName, "TerrainRadar")
    }

    func testAnalyzeSingleLuaFile() async throws {
        let luaFile = tempDir.appendingPathComponent("view_toggle.lua")
        try "print('toggle')".write(to: luaFile, atomically: true, encoding: .utf8)

        let analysis = try await installerService.analyze(url: luaFile)
        XCTAssertEqual(analysis.detectedCategory, .luaScripts)
        XCTAssertEqual(analysis.suggestedPackageName, "view_toggle")
        XCTAssertEqual(analysis.entriesCount, 1)
        XCTAssertFalse(analysis.isArchive)
    }

    // MARK: - Directory Installation Execution Tests

    func testInstallDirectoryPluginAndCheckExecutablePermissions() async throws {
        let pluginDir = tempDir.appendingPathComponent("MyPlugin")
        let mac64 = pluginDir.appendingPathComponent("mac_x64")
        try fm.createDirectory(at: mac64, withIntermediateDirectories: true)
        let binary = mac64.appendingPathComponent("plugin.xpl")
        try "binary".write(to: binary, atomically: true, encoding: .utf8)

        let analysis = try await installerService.analyze(url: pluginDir)

        let installedURL = try await installerService.install(
            analysis: analysis,
            category: .plugins,
            packageName: "MyPlugin",
            launcherDataFolder: dataFolder
        )

        let expectedURL = PathService.shared.dataFolder(.plugins, in: dataFolder).appendingPathComponent("MyPlugin")
        XCTAssertEqual(installedURL.path, expectedURL.path)
        XCTAssertTrue(fm.fileExists(atPath: installedURL.path))

        // Check executable permissions on plugin binary (0o755)
        let installedBinary = installedURL.appendingPathComponent("mac_x64/plugin.xpl")
        let attrs = try fm.attributesOfItem(atPath: installedBinary.path)
        let posixPerms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(posixPerms, 0o755)
    }

    func testInstallRejectsExistingDestination() async throws {
        let pluginDir = tempDir.appendingPathComponent("ExistingPlugin")
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let existingDest = PathService.shared.dataFolder(.plugins, in: dataFolder).appendingPathComponent("ExistingPlugin")
        try fm.createDirectory(at: existingDest, withIntermediateDirectories: true)

        let analysis = try await installerService.analyze(url: pluginDir)

        do {
            _ = try await installerService.install(
                analysis: analysis,
                category: .plugins,
                packageName: "ExistingPlugin",
                launcherDataFolder: dataFolder
            )
            XCTFail("Should have thrown destinationExists error")
        } catch AddonInstallerError.destinationExists {
            // Success
        }
    }
}
