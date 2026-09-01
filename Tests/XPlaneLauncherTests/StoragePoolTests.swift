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

final class StoragePoolTests: XCTestCase {
    var tempDir: URL!
    var pool1Dir: URL!
    var pool2Dir: URL!
    var xPlaneDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("StoragePoolTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        pool1Dir = tempDir.appendingPathComponent("PrimaryPool")
        pool2Dir = tempDir.appendingPathComponent("ExternalDrive")
        xPlaneDir = tempDir.appendingPathComponent("XPlane")

        try FileManager.default.createDirectory(at: pool1Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool2Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xPlaneDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Model & Metrics Tests

    func testStoragePoolOnlineAndMetrics() {
        let pool = StoragePool(
            name: "Primary SSD",
            url: pool1Dir,
            isPrimary: true,
            defaultCategories: [.plugins, .aircraft]
        )

        XCTAssertTrue(pool.isOnline)
        XCTAssertEqual(pool.name, "Primary SSD")
        XCTAssertTrue(pool.isPrimary)
        XCTAssertEqual(pool.defaultCategories, [.plugins, .aircraft])
        XCTAssertNotNil(pool.volumeMetrics)
        if let metrics = pool.volumeMetrics {
            XCTAssertGreaterThan(metrics.totalCapacity, 0)
            XCTAssertGreaterThanOrEqual(metrics.availableCapacity, 0)
        }
        XCTAssertEqual(pool.iconName, "internaldrive")

        let nonExistentURL = tempDir.appendingPathComponent("UnmountedVolume_\(UUID().uuidString)")
        let offlinePool = StoragePool(name: "Disconnected SSD", url: nonExistentURL)
        XCTAssertFalse(offlinePool.isOnline)
        XCTAssertEqual(offlinePool.iconName, "externaldrive.badge.xmark")
    }

    // MARK: - Category Routing Resolution

    func testCategoryRoutingResolution() {
        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true, defaultCategories: [.plugins, .luaScripts])
        let pool2 = StoragePool(name: "External SSD", url: pool2Dir, isPrimary: false, defaultCategories: [.scenery, .aircraft])

        let pools = [pool1, pool2]

        let sceneryTarget = StoragePoolService.shared.resolveDestinationPool(category: .scenery, in: pools)
        XCTAssertEqual(sceneryTarget?.id, pool2.id)

        let pluginTarget = StoragePoolService.shared.resolveDestinationPool(category: .plugins, in: pools)
        XCTAssertEqual(pluginTarget?.id, pool1.id)

        // If a category has no explicit routing, falls back to primary pool
        let pool3 = StoragePool(name: "Empty Categories", url: pool2Dir, isPrimary: false, defaultCategories: [])
        let unroutedTarget = StoragePoolService.shared.resolveDestinationPool(category: .aircraft, in: [pool1, pool3])
        XCTAssertEqual(unroutedTarget?.id, pool1.id)
    }

    // MARK: - Storage Pool Stats Calculation

    func testStoragePoolStatsCalculation() throws {
        let pool = StoragePool(name: "Test Pool", url: pool1Dir, isPrimary: true)
        PathService.shared.ensureDirectories(for: pool.url)

        let pluginsFolder = PathService.shared.dataFolder(.plugins, in: pool.url)
        let samplePlugin = pluginsFolder.appendingPathComponent("SamplePlugin")
        try FileManager.default.createDirectory(at: samplePlugin, withIntermediateDirectories: true)
        try "dummy binary content".data(using: .utf8)?.write(to: samplePlugin.appendingPathComponent("plugin.xpl"))

        let sceneryFolder = PathService.shared.dataFolder(.scenery, in: pool.url)
        let sampleScenery = sceneryFolder.appendingPathComponent("CustomAirport")
        try FileManager.default.createDirectory(at: sampleScenery, withIntermediateDirectories: true)
        try "dummy scenery".data(using: .utf8)?.write(to: sampleScenery.appendingPathComponent("Earth nav data.txt"))

        let stats = StoragePoolService.shared.calculateStats(for: pool)
        XCTAssertEqual(stats.pluginCount, 1)
        XCTAssertGreaterThan(stats.pluginSizeBytes, 0)
        XCTAssertEqual(stats.sceneryCount, 1)
        XCTAssertGreaterThan(stats.scenerySizeBytes, 0)
        XCTAssertEqual(stats.aircraftCount, 0)
        XCTAssertEqual(stats.luaScriptCount, 0)
    }

    // MARK: - Multi-Pool Symlink Aggregation & Offline Handling

    func testMultiPoolScanningAndOfflineDetection() throws {
        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true)
        let pool2 = StoragePool(name: "External", url: pool2Dir, isPrimary: false)

        PathService.shared.ensureDirectories(for: pool1.url)
        PathService.shared.ensureDirectories(for: pool2.url)

        let targetFolder = xPlaneDir.appendingPathComponent("Resources/plugins")
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        // Plugin 1 on Internal
        let p1Source = PathService.shared.dataFolder(.plugins, in: pool1.url).appendingPathComponent("InternalPlugin")
        try FileManager.default.createDirectory(at: p1Source, withIntermediateDirectories: true)

        // Plugin 2 on External
        let p2Source = PathService.shared.dataFolder(.plugins, in: pool2.url).appendingPathComponent("ExternalPlugin")
        try FileManager.default.createDirectory(at: p2Source, withIntermediateDirectories: true)

        // Link Plugin 1 & 2
        try SymlinkService.shared.setPluginEnabled(folderName: "InternalPlugin", enabled: true, sourceURL: p1Source, targetFolder: targetFolder)
        try SymlinkService.shared.setPluginEnabled(folderName: "ExternalPlugin", enabled: true, sourceURL: p2Source, targetFolder: targetFolder)

        // Scan both pools
        let scanned = try SymlinkService.shared.scanPlugins(storagePools: [pool1, pool2], targetFolder: targetFolder)
        XCTAssertEqual(scanned.count, 2)
        XCTAssertTrue(scanned.contains(where: { $0.folderName == "InternalPlugin" && $0.isEnabled && !$0.isOffline && $0.storagePoolId == pool1.id }))
        XCTAssertTrue(scanned.contains(where: { $0.folderName == "ExternalPlugin" && $0.isEnabled && !$0.isOffline && $0.storagePoolId == pool2.id }))

        // Simulate disconnecting pool 2: unmount directory
        let offlinePool2 = StoragePool(id: pool2.id, name: "External", url: tempDir.appendingPathComponent("UnmountedExternal"), isPrimary: false)

        let rescanned = try SymlinkService.shared.scanPlugins(storagePools: [pool1, offlinePool2], targetFolder: targetFolder, knownPlugins: scanned)
        XCTAssertEqual(rescanned.count, 2)

        let externalItem = rescanned.first(where: { $0.folderName == "ExternalPlugin" })
        XCTAssertNotNil(externalItem)
        XCTAssertTrue(externalItem?.isOffline == true)
        XCTAssertFalse(externalItem?.isEnabled == true)

        let internalItem = rescanned.first(where: { $0.folderName == "InternalPlugin" })
        XCTAssertNotNil(internalItem)
        XCTAssertFalse(internalItem?.isOffline == true)
        XCTAssertTrue(internalItem?.isEnabled == true)
    }

    // MARK: - Multi-Pool Scenery Scanning

    func testMultiPoolSceneryScanning() throws {
        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true)
        let pool2 = StoragePool(name: "External SSD", url: pool2Dir, isPrimary: false)

        PathService.shared.ensureDirectories(for: pool1.url)
        PathService.shared.ensureDirectories(for: pool2.url)

        let customScenery = xPlaneDir.appendingPathComponent("Custom Scenery")
        let iniURL = customScenery.appendingPathComponent("scenery_packs.ini")
        try FileManager.default.createDirectory(at: customScenery, withIntermediateDirectories: true)

        // Pack on Pool 1
        let s1Source = PathService.shared.dataFolder(.scenery, in: pool1.url).appendingPathComponent("Airport_A")
        try FileManager.default.createDirectory(at: s1Source, withIntermediateDirectories: true)
        try SceneryService.shared.linkScenery(folderName: "Airport_A", sourceURL: s1Source, customSceneryFolder: customScenery)

        // Pack on Pool 2
        let s2Source = PathService.shared.dataFolder(.scenery, in: pool2.url).appendingPathComponent("Airport_B")
        try FileManager.default.createDirectory(at: s2Source, withIntermediateDirectories: true)
        try SceneryService.shared.linkScenery(folderName: "Airport_B", sourceURL: s2Source, customSceneryFolder: customScenery)

        // Write ini
        let iniContent = """
        I
        1000 Version
        SCENERY

        SCENERY_PACK Custom Scenery/Airport_A/
        SCENERY_PACK Custom Scenery/Airport_B/
        """
        try iniContent.write(to: iniURL, atomically: true, encoding: .utf8)

        let scanned = try SceneryService.shared.scanScenery(
            customSceneryFolder: customScenery,
            storagePools: [pool1, pool2],
            iniURL: iniURL
        )

        XCTAssertEqual(scanned.count, 2)
        XCTAssertEqual(scanned[0].folderName, "Airport_A")
        XCTAssertEqual(scanned[0].storagePoolId, pool1.id)
        XCTAssertEqual(scanned[1].folderName, "Airport_B")
        XCTAssertEqual(scanned[1].storagePoolId, pool2.id)
    }

    // MARK: - Addon Installer Destination Routing & Storage Check

    func testAddonInstallerTargetRouting() async throws {
        let pool = StoragePool(name: "External SSD", url: pool2Dir, isPrimary: false)
        PathService.shared.ensureDirectories(for: pool.url)

        let packageFolder = tempDir.appendingPathComponent("TestPluginSource")
        try FileManager.default.createDirectory(at: packageFolder, withIntermediateDirectories: true)
        try "test binary".data(using: .utf8)?.write(to: packageFolder.appendingPathComponent("mac.xpl"))

        let analysis = AddonPackageAnalysis(
            sourceURL: packageFolder,
            isArchive: false,
            detectedCategory: .plugins,
            suggestedPackageName: "InstalledTestPlugin",
            entriesCount: 1,
            totalUncompressedSize: 100,
            internalRootPrefix: nil,
            detectedIndicators: ["mac.xpl"]
        )

        let installedURL = try await AddonInstallerService.shared.install(
            analysis: analysis,
            category: .plugins,
            packageName: "InstalledTestPlugin",
            storagePool: pool
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: installedURL.path))
        XCTAssertTrue(installedURL.path.hasPrefix(pool2Dir.path))
        XCTAssertEqual(installedURL.lastPathComponent, "InstalledTestPlugin")
    }

    func testAddonInstallerOfflinePoolRejection() async throws {
        let offlinePool = StoragePool(name: "Disconnected Drive", url: tempDir.appendingPathComponent("NonExistentVolume"))
        let packageFolder = tempDir.appendingPathComponent("DummySource")
        try FileManager.default.createDirectory(at: packageFolder, withIntermediateDirectories: true)

        let analysis = AddonPackageAnalysis(
            sourceURL: packageFolder,
            isArchive: false,
            detectedCategory: .scenery,
            suggestedPackageName: "DummyScenery",
            entriesCount: 1,
            totalUncompressedSize: 50,
            internalRootPrefix: nil,
            detectedIndicators: []
        )

        do {
            _ = try await AddonInstallerService.shared.install(
                analysis: analysis,
                category: .scenery,
                packageName: "DummyScenery",
                storagePool: offlinePool
            )
            XCTFail("Should have thrown error for offline storage pool")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("offline") || error.localizedDescription.contains("unmounted"))
        }
    }

    func testColdDetectionOfOfflineSymlinks() throws {
        let unmountedVolume = tempDir.appendingPathComponent("DisconnectedDisk")
        let pool = StoragePool(name: "ExtSSD", url: unmountedVolume, isPrimary: false)

        let targetFolder = xPlaneDir.appendingPathComponent("Resources/plugins")
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)

        // Create a symlink pointing to an unmounted / non-existent target
        let brokenLink = targetFolder.appendingPathComponent("OfflinePlugin")
        let nonExistentTarget = unmountedVolume.appendingPathComponent("Plugins/OfflinePlugin")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: nonExistentTarget)

        // Scan without passing any knownPlugins (cold launch)
        let scanned = try SymlinkService.shared.scanPlugins(storagePools: [pool], targetFolder: targetFolder, knownPlugins: [])
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned[0].folderName, "OfflinePlugin")
        XCTAssertTrue(scanned[0].isOffline)
        XCTAssertFalse(scanned[0].isEnabled)
        XCTAssertEqual(scanned[0].storagePoolId, pool.id)
    }

    func testColdDetectionOfOfflineScenery() throws {
        let unmountedVolume = tempDir.appendingPathComponent("DisconnectedDisk")
        let pool = StoragePool(name: "ExtSSD", url: unmountedVolume, isPrimary: false)

        let customScenery = xPlaneDir.appendingPathComponent("Custom Scenery")
        let iniURL = customScenery.appendingPathComponent("scenery_packs.ini")
        try FileManager.default.createDirectory(at: customScenery, withIntermediateDirectories: true)

        let brokenLink = customScenery.appendingPathComponent("OfflineScenery")
        let nonExistentTarget = unmountedVolume.appendingPathComponent("Scenery/OfflineScenery")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: nonExistentTarget)

        let iniContent = """
        I
        1000 Version
        SCENERY

        SCENERY_PACK Custom Scenery/OfflineScenery/
        """
        try iniContent.write(to: iniURL, atomically: true, encoding: .utf8)

        let scanned = try SceneryService.shared.scanScenery(
            customSceneryFolder: customScenery,
            storagePools: [pool],
            iniURL: iniURL,
            knownScenery: []
        )

        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned[0].folderName, "OfflineScenery")
        XCTAssertTrue(scanned[0].isOffline)
        XCTAssertFalse(scanned[0].isEnabled)
        XCTAssertEqual(scanned[0].storagePoolId, pool.id)
    }
}
