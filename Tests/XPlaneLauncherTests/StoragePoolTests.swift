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

        UserDefaults.standard.removeObject(forKey: .pluginProfiles)
        UserDefaults.standard.removeObject(forKey: .sceneryGroups)
        UserDefaults.standard.removeObject(forKey: .storagePools)
        UserDefaults.standard.removeObject(forKey: .selectedProfileId)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        UserDefaults.standard.removeObject(forKey: .pluginProfiles)
        UserDefaults.standard.removeObject(forKey: .sceneryGroups)
        UserDefaults.standard.removeObject(forKey: .storagePools)
        UserDefaults.standard.removeObject(forKey: .selectedProfileId)
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

    // MARK: - Profile and Scenery Purge on Storage Pool Removal

    @MainActor
    func testRemoveStoragePoolPurgesAddonsFromAllProfiles() throws {
        PathService.shared.ensureDirectories(for: pool1Dir)
        PathService.shared.ensureDirectories(for: pool2Dir)

        try FileManager.default.createDirectory(at: PathService.shared.pluginsTargetFolder(for: xPlaneDir), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: PathService.shared.aircraftTargetFolder(for: xPlaneDir), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: PathService.shared.customSceneryFolder(for: xPlaneDir), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: PathService.shared.flyWithLuaScriptsFolder(for: xPlaneDir), withIntermediateDirectories: true)

        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true)
        let pool2 = StoragePool(name: "External", url: pool2Dir, isPrimary: false)

        // Populate pool1
        try FileManager.default.createDirectory(at: pool1Dir.appendingPathComponent("Plugins/Pool1Plugin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool1Dir.appendingPathComponent("Aircraft/Pool1Plane"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool1Dir.appendingPathComponent("Scenery/Pool1Scenery"), withIntermediateDirectories: true)
        try "print('lua1')".write(to: pool1Dir.appendingPathComponent("LuaScripts/Pool1Script.lua"), atomically: true, encoding: .utf8)

        // Populate pool2
        try FileManager.default.createDirectory(at: pool2Dir.appendingPathComponent("Plugins/Pool2Plugin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool2Dir.appendingPathComponent("Aircraft/Pool2Plane"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool2Dir.appendingPathComponent("Scenery/Pool2Scenery"), withIntermediateDirectories: true)
        try "print('lua2')".write(to: pool2Dir.appendingPathComponent("LuaScripts/Pool2Script.lua"), atomically: true, encoding: .utf8)

        let pm = PluginManager()
        pm.storagePools = [pool1, pool2]
        pm.launcherDataFolder = pool1Dir
        pm.xPlanePath = xPlaneDir
        pm.rescanAll()

        let profile1 = PluginProfile(
            name: "Mixed Profile",
            pluginFolderNames: ["Pool1Plugin", "Pool2Plugin"],
            sceneryFolderNames: ["Pool1Scenery", "Pool2Scenery"],
            aircraftFolderNames: ["Pool1Plane", "Pool2Plane"],
            luaScriptFolderNames: ["Pool1Script.lua", "Pool2Script.lua"]
        )
        let profile2 = PluginProfile(
            name: "Pool2 Only Profile",
            pluginFolderNames: ["Pool2Plugin"],
            sceneryFolderNames: ["Pool2Scenery"],
            aircraftFolderNames: ["Pool2Plane"],
            luaScriptFolderNames: ["Pool2Script.lua"]
        )
        pm.profiles = [profile1, profile2]
        ProfileService.shared.saveProfiles(pm.profiles)

        let sceneryGroup = SceneryGroup(
            name: "All Scenery",
            childFolderNames: ["Pool1Scenery", "Pool2Scenery"]
        )
        pm.sceneryGroups = [sceneryGroup]

        // Remove pool2
        pm.removeStoragePool(id: pool2.id)

        // Verify pool2 is removed
        XCTAssertEqual(pm.storagePools.count, 1)
        XCTAssertEqual(pm.storagePools[0].id, pool1.id)

        // Verify profile1 has pool2 addons purged and pool1 addons retained
        let updatedProfile1 = pm.profiles.first(where: { $0.id == profile1.id })
        XCTAssertNotNil(updatedProfile1)
        XCTAssertEqual(updatedProfile1?.pluginFolderNames, ["Pool1Plugin"])
        XCTAssertEqual(updatedProfile1?.aircraftFolderNames, ["Pool1Plane"])
        XCTAssertEqual(updatedProfile1?.sceneryFolderNames, ["Pool1Scenery"])
        XCTAssertEqual(updatedProfile1?.luaScriptFolderNames, ["Pool1Script.lua"])

        // Verify profile2 has all addons purged
        let updatedProfile2 = pm.profiles.first(where: { $0.id == profile2.id })
        XCTAssertNotNil(updatedProfile2)
        XCTAssertEqual(updatedProfile2?.pluginFolderNames, [])
        XCTAssertEqual(updatedProfile2?.aircraftFolderNames, [])
        XCTAssertEqual(updatedProfile2?.sceneryFolderNames, [])
        XCTAssertEqual(updatedProfile2?.luaScriptFolderNames, [])

        // Verify scenery group has Pool2Scenery purged
        XCTAssertEqual(pm.sceneryGroups.first?.childFolderNames, ["Pool1Scenery"])

        // Verify persistence
        let persistedProfiles = ProfileService.shared.loadProfiles()
        XCTAssertEqual(persistedProfiles.count, 2)
        XCTAssertEqual(persistedProfiles.first(where: { $0.id == profile1.id })?.pluginFolderNames, ["Pool1Plugin"])

        let persistedGroups = ProfileService.shared.loadSceneryGroups()
        XCTAssertEqual(persistedGroups.first?.childFolderNames, ["Pool1Scenery"])
    }

    @MainActor
    func testRemoveStoragePoolRetainsSharedAddons() throws {
        PathService.shared.ensureDirectories(for: pool1Dir)
        PathService.shared.ensureDirectories(for: pool2Dir)

        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true)
        let pool2 = StoragePool(name: "External", url: pool2Dir, isPrimary: false)

        // Both pools contain an addon with the same folder name
        try FileManager.default.createDirectory(at: pool1Dir.appendingPathComponent("Plugins/SharedPlugin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool2Dir.appendingPathComponent("Plugins/SharedPlugin"), withIntermediateDirectories: true)

        let pm = PluginManager()
        pm.storagePools = [pool1, pool2]
        pm.launcherDataFolder = pool1Dir
        pm.xPlanePath = xPlaneDir
        pm.rescanAll()

        let profile = PluginProfile(
            name: "Shared Profile",
            pluginFolderNames: ["SharedPlugin"]
        )
        pm.profiles = [profile]
        ProfileService.shared.saveProfiles(pm.profiles)

        // Remove pool2
        pm.removeStoragePool(id: pool2.id)

        // SharedPlugin should still be retained because pool1 still contains it
        let updatedProfile = pm.profiles.first(where: { $0.id == profile.id })
        XCTAssertEqual(updatedProfile?.pluginFolderNames, ["SharedPlugin"])
    }

    @MainActor
    func testRemoveOfflineStoragePoolPurgesAddonsFromAllProfiles() throws {
        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true)
        let offlineURL = tempDir.appendingPathComponent("OfflineVolume_\(UUID().uuidString)")
        let pool2 = StoragePool(name: "Offline Drive", url: offlineURL, isPrimary: false)

        let pm = PluginManager()
        pm.storagePools = [pool1, pool2]
        pm.launcherDataFolder = pool1Dir
        pm.xPlanePath = xPlaneDir

        // Emulate known items belonging to offline pool2
        let offlinePlugin = Plugin(
            name: "OfflinePlugin",
            isEnabled: false,
            folderName: "OfflinePlugin",
            storagePoolId: pool2.id,
            storagePoolName: pool2.name,
            sourceURL: offlineURL.appendingPathComponent("Plugins/OfflinePlugin"),
            isOffline: true
        )
        pm.plugins = [offlinePlugin]

        let profile = PluginProfile(
            name: "Offline Test Profile",
            pluginFolderNames: ["OfflinePlugin"]
        )
        pm.profiles = [profile]
        ProfileService.shared.saveProfiles(pm.profiles)

        // Remove offline pool
        pm.removeStoragePool(id: pool2.id)

        // Verify plugin reference is purged from profile
        let updatedProfile = pm.profiles.first(where: { $0.id == profile.id })
        XCTAssertEqual(updatedProfile?.pluginFolderNames, [])

        // Verify offline plugin is no longer in plugins list after rescan
        XCTAssertFalse(pm.plugins.contains(where: { $0.folderName == "OfflinePlugin" }))
    }

    @MainActor
    func testBrokenSymlinksWithoutStoragePoolAreCleanedUpAndNotReported() throws {
        let pluginsTarget = PathService.shared.pluginsTargetFolder(for: xPlaneDir)
        let aircraftTarget = PathService.shared.aircraftTargetFolder(for: xPlaneDir)
        let sceneryTarget = PathService.shared.customSceneryFolder(for: xPlaneDir)
        let luaTarget = PathService.shared.flyWithLuaScriptsFolder(for: xPlaneDir)

        try FileManager.default.createDirectory(at: pluginsTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aircraftTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sceneryTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: luaTarget, withIntermediateDirectories: true)

        let nonExistentVolume = tempDir.appendingPathComponent("DeletedVolume_\(UUID().uuidString)")

        // Create broken symlinks pointing into nonExistentVolume
        let brokenPlugin = pluginsTarget.appendingPathComponent("OrphanedPlugin")
        let brokenAircraft = aircraftTarget.appendingPathComponent("OrphanedAircraft")
        let brokenScenery = sceneryTarget.appendingPathComponent("OrphanedScenery")
        let brokenLua = luaTarget.appendingPathComponent("test.lua")

        try FileManager.default.createSymbolicLink(at: brokenPlugin, withDestinationURL: nonExistentVolume.appendingPathComponent("Plugins/OrphanedPlugin"))
        try FileManager.default.createSymbolicLink(at: brokenAircraft, withDestinationURL: nonExistentVolume.appendingPathComponent("Aircraft/OrphanedAircraft"))
        try FileManager.default.createSymbolicLink(at: brokenScenery, withDestinationURL: nonExistentVolume.appendingPathComponent("Scenery/OrphanedScenery"))
        try FileManager.default.createSymbolicLink(at: brokenLua, withDestinationURL: nonExistentVolume.appendingPathComponent("LuaScripts/test.lua"))

        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true)
        let pm = PluginManager()
        pm.storagePools = [pool1]
        pm.launcherDataFolder = pool1Dir
        pm.xPlanePath = xPlaneDir

        // Run rescan
        pm.rescanAll()

        // Assert they are not reported in the UI lists
        XCTAssertFalse(pm.plugins.contains(where: { $0.folderName == "OrphanedPlugin" }))
        XCTAssertFalse(pm.aircraft.contains(where: { $0.folderName == "OrphanedAircraft" }))
        XCTAssertFalse(pm.scenery.contains(where: { $0.folderName == "OrphanedScenery" }))
        XCTAssertFalse(pm.luaScripts.contains(where: { $0.folderName == "test.lua" }))

        // Assert the broken symlinks were cleaned up from disk
        var statBuf = stat()
        XCTAssertNotEqual(lstat(brokenPlugin.path, &statBuf), 0, "brokenPlugin symlink should be removed")
        XCTAssertNotEqual(lstat(brokenAircraft.path, &statBuf), 0, "brokenAircraft symlink should be removed")
        XCTAssertNotEqual(lstat(brokenScenery.path, &statBuf), 0, "brokenScenery symlink should be removed")
        XCTAssertNotEqual(lstat(brokenLua.path, &statBuf), 0, "brokenLua symlink should be removed")
    }

    @MainActor
    func testRemoveStoragePoolUnlinksActiveSymlinksFromXPlane() throws {
        let pluginsTarget = PathService.shared.pluginsTargetFolder(for: xPlaneDir)
        let aircraftTarget = PathService.shared.aircraftTargetFolder(for: xPlaneDir)
        let sceneryTarget = PathService.shared.customSceneryFolder(for: xPlaneDir)
        let luaTarget = PathService.shared.flyWithLuaScriptsFolder(for: xPlaneDir)

        try FileManager.default.createDirectory(at: pluginsTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aircraftTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sceneryTarget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: luaTarget, withIntermediateDirectories: true)

        let pool1 = StoragePool(name: "Internal", url: pool1Dir, isPrimary: true)
        let pool2 = StoragePool(name: "External", url: pool2Dir, isPrimary: false)

        // Setup source files in pool2
        let pool2Plugin = pool2Dir.appendingPathComponent("Plugins/MyPlugin")
        let pool2Plane = pool2Dir.appendingPathComponent("Aircraft/MyPlane")
        let pool2Scenery = pool2Dir.appendingPathComponent("Scenery/MyScenery")
        let pool2Lua = pool2Dir.appendingPathComponent("LuaScripts/test.lua")

        try FileManager.default.createDirectory(at: pool2Plugin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool2Plane, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool2Scenery, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pool2Dir.appendingPathComponent("LuaScripts"), withIntermediateDirectories: true)
        try "print('hello')".write(to: pool2Lua, atomically: true, encoding: .utf8)

        // Create active symlinks in X-Plane
        let linkPlugin = pluginsTarget.appendingPathComponent("MyPlugin")
        let linkPlane = aircraftTarget.appendingPathComponent("MyPlane")
        let linkScenery = sceneryTarget.appendingPathComponent("MyScenery")
        let linkLua = luaTarget.appendingPathComponent("test.lua")

        try FileManager.default.createSymbolicLink(at: linkPlugin, withDestinationURL: pool2Plugin)
        try FileManager.default.createSymbolicLink(at: linkPlane, withDestinationURL: pool2Plane)
        try FileManager.default.createSymbolicLink(at: linkScenery, withDestinationURL: pool2Scenery)
        try FileManager.default.createSymbolicLink(at: linkLua, withDestinationURL: pool2Lua)

        let pm = PluginManager()
        pm.storagePools = [pool1, pool2]
        pm.launcherDataFolder = pool1Dir
        pm.xPlanePath = xPlaneDir
        pm.rescanAll()

        XCTAssertTrue(pm.luaScripts.contains(where: { $0.folderName == "test.lua" }))

        // Remove pool2
        pm.removeStoragePool(id: pool2.id)

        // Assert all symlinks pointing to pool2 are removed from X-Plane folders
        var statBuf = stat()
        XCTAssertNotEqual(lstat(linkPlugin.path, &statBuf), 0, "linkPlugin symlink should be unlinked")
        XCTAssertNotEqual(lstat(linkPlane.path, &statBuf), 0, "linkPlane symlink should be unlinked")
        XCTAssertNotEqual(lstat(linkScenery.path, &statBuf), 0, "linkScenery symlink should be unlinked")
        XCTAssertNotEqual(lstat(linkLua.path, &statBuf), 0, "linkLua symlink should be unlinked")

        // Assert UI list no longer contains them
        XCTAssertFalse(pm.luaScripts.contains(where: { $0.folderName == "test.lua" }))
        XCTAssertFalse(pm.plugins.contains(where: { $0.folderName == "MyPlugin" }))
    }
}
