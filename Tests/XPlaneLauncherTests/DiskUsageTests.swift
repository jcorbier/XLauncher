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

final class DiskUsageTests: XCTestCase {
    var tempDir: URL!
    var xPlaneDir: URL!
    var poolDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DiskUsageTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        xPlaneDir = tempDir.appendingPathComponent("X-Plane")
        poolDir = tempDir.appendingPathComponent("StoragePool")

        try FileManager.default.createDirectory(at: xPlaneDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: poolDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Size Calculation & Symlink Exclusion Tests

    func testCalculateItemSizeAndSymlinkExclusion() throws {
        let service = DiskUsageService.shared
        let realFolder = tempDir.appendingPathComponent("RealAddon")
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)

        let dummyData = Data(repeating: 0x41, count: 1024 * 64) // 64 KB
        try dummyData.write(to: realFolder.appendingPathComponent("file1.dat"))
        try dummyData.write(to: realFolder.appendingPathComponent("file2.dat"))

        let (size, count) = service.calculateItemSize(at: realFolder)
        XCTAssertEqual(size, 1024 * 128)
        XCTAssertEqual(count, 2)

        // Create a symlink pointing to the real folder
        let symlinkURL = tempDir.appendingPathComponent("SymlinkAddon")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realFolder)

        // A symlink must report 0 bytes to prevent double-counting
        let (symlinkSize, symlinkCount) = service.calculateItemSize(at: symlinkURL)
        XCTAssertEqual(symlinkSize, 0)
        XCTAssertEqual(symlinkCount, 1)
    }

    // MARK: - Scenery Classification Tests

    func testClassifySceneryHeuristics() throws {
        let service = DiskUsageService.shared

        // 1. Airport: contains Earth nav data/apt.dat
        let airportDir = tempDir.appendingPathComponent("LFPG_CharlesDeGaulle")
        let aptDir = airportDir.appendingPathComponent("Earth nav data")
        try FileManager.default.createDirectory(at: aptDir, withIntermediateDirectories: true)
        try "I\n1100 Version\n".write(to: aptDir.appendingPathComponent("apt.dat"), atomically: true, encoding: .utf8)
        XCTAssertEqual(service.classifyScenery(url: airportDir, folderName: "LFPG_CharlesDeGaulle"), .sceneryAirports)

        // 2. Orthophoto: folder name prefix zOrtho
        let orthoDir = tempDir.appendingPathComponent("zOrtho4XP_+48+002")
        try FileManager.default.createDirectory(at: orthoDir, withIntermediateDirectories: true)
        XCTAssertEqual(service.classifyScenery(url: orthoDir, folderName: "zOrtho4XP_+48+002"), .sceneryOrthos)

        // 3. Library: contains library.txt
        let libDir = tempDir.appendingPathComponent("MyCustomLibrary")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        try "A\n800\nLIBRARY\n".write(to: libDir.appendingPathComponent("library.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(service.classifyScenery(url: libDir, folderName: "MyCustomLibrary"), .sceneryLibraries)

        // 4. Mesh: contains Earth nav data with DSF but no apt.dat
        let meshDir = tempDir.appendingPathComponent("Alps_UHD_Mesh")
        let meshNavDir = meshDir.appendingPathComponent("Earth nav data")
        try FileManager.default.createDirectory(at: meshNavDir, withIntermediateDirectories: true)
        try "dummy dsf".write(to: meshNavDir.appendingPathComponent("+45+006.dsf"), atomically: true, encoding: .utf8)
        XCTAssertEqual(service.classifyScenery(url: meshDir, folderName: "Alps_UHD_Mesh"), .sceneryMesh)
    }

    // MARK: - Orphan Detection & Cache Clearing Tests

    func testAnalyzeDiskUsageAndOrphanDetection() async throws {
        let service = DiskUsageService.shared

        // 1. Setup primary X-Plane structure
        let cachesDir = xPlaneDir.appendingPathComponent("Output/caches")
        let crashDir = xPlaneDir.appendingPathComponent("Output/crash_reports")
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)

        let shaderData = Data(repeating: 0x55, count: 5000)
        try shaderData.write(to: cachesDir.appendingPathComponent("pipeline.cache"))

        let crashData = Data(repeating: 0x66, count: 3000)
        try crashData.write(to: crashDir.appendingPathComponent("crash.dmp"))

        // 2. Setup storage pool with 1 referenced addon and 1 orphan addon
        let poolSceneryDir = poolDir.appendingPathComponent("Custom Scenery")
        try FileManager.default.createDirectory(at: poolSceneryDir, withIntermediateDirectories: true)

        let activeAddon = poolSceneryDir.appendingPathComponent("ActiveAirport")
        let orphanAddon = poolSceneryDir.appendingPathComponent("OrphanScenery")
        try FileManager.default.createDirectory(at: activeAddon, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphanAddon, withIntermediateDirectories: true)

        try "content1".write(to: activeAddon.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try "content2".write(to: orphanAddon.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let pool = StoragePool(
            id: UUID(),
            name: "TestPool",
            url: poolDir,
            isPrimary: false
        )

        let profile = PluginProfile(
            name: "Default Profile",
            pluginFolderNames: [],
            sceneryFolderNames: ["ActiveAirport"]
        )

        let summary = await service.analyzeDiskUsage(
            xPlanePath: xPlaneDir,
            storagePools: [pool],
            profiles: [profile]
        )

        XCTAssertGreaterThan(summary.totalBytes, 0)
        XCTAssertTrue(summary.orphanItems.contains(where: { $0.name == "OrphanScenery" }))
        XCTAssertFalse(summary.orphanItems.contains(where: { $0.name == "ActiveAirport" }))

        XCTAssertTrue(summary.cacheItems.contains(where: { $0.category == AddonStorageCategory.caches }))
        XCTAssertTrue(summary.cacheItems.contains(where: { $0.category == AddonStorageCategory.logsAndCrashes }))

        // 3. Test Clearing Shaders
        let freedShader = try await service.clearShaderCache(xPlanePath: xPlaneDir)
        XCTAssertGreaterThanOrEqual(freedShader, 5000)
        let remainingCaches = try FileManager.default.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(remainingCaches.isEmpty)

        // 4. Test Clearing Crash Reports
        let freedCrash = try await service.clearCrashReports(xPlanePath: xPlaneDir)
        XCTAssertGreaterThanOrEqual(freedCrash, 3000)
        let remainingCrashes = try FileManager.default.contentsOfDirectory(at: crashDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(remainingCrashes.isEmpty)
    }
}
