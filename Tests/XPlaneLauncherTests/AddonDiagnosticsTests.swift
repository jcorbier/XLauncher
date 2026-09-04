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

final class AddonDiagnosticsTests: XCTestCase {
    var tempDir: URL!
    var xPlaneDir: URL!
    var customSceneryDir: URL!
    var pluginsDir: URL!
    var poolDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("XLauncherDiagnosticsTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        xPlaneDir = tempDir.appendingPathComponent("X-Plane")
        customSceneryDir = xPlaneDir.appendingPathComponent("Custom Scenery")
        pluginsDir = xPlaneDir.appendingPathComponent("Resources").appendingPathComponent("plugins")
        poolDir = tempDir.appendingPathComponent("StoragePool")

        try FileManager.default.createDirectory(at: customSceneryDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: poolDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Mach-O Architecture Tests

    func testMachOAnalyzer64BitThinHeaders() {
        let analyzer = MachOAnalyzer.shared

        // 1. Thin arm64: magic 0xFEEDFACF, cputype 0x0100000C
        var arm64Data = Data()
        var magic64: UInt32 = 0xFEEDFACF
        var cputypeArm64: UInt32 = 0x0100000C
        arm64Data.append(Data(bytes: &magic64, count: 4))
        arm64Data.append(Data(bytes: &cputypeArm64, count: 4))
        arm64Data.append(Data(repeating: 0, count: 32))

        let arm64Result = analyzer.analyzeData(arm64Data)
        XCTAssertNotNil(arm64Result)
        XCTAssertTrue(arm64Result!.hasArm64)
        XCTAssertFalse(arm64Result!.hasX86_64)
        XCTAssertFalse(arm64Result!.isUniversal)

        // 2. Thin x86_64: magic 0xFEEDFACF, cputype 0x01000007
        var x86Data = Data()
        var cputypeX86_64: UInt32 = 0x01000007
        x86Data.append(Data(bytes: &magic64, count: 4))
        x86Data.append(Data(bytes: &cputypeX86_64, count: 4))
        x86Data.append(Data(repeating: 0, count: 32))

        let x86Result = analyzer.analyzeData(x86Data)
        XCTAssertNotNil(x86Result)
        XCTAssertFalse(x86Result!.hasArm64)
        XCTAssertTrue(x86Result!.hasX86_64)
        XCTAssertFalse(x86Result!.isUniversal)
    }

    func testMachOAnalyzerUniversalFatBinary() {
        let analyzer = MachOAnalyzer.shared

        // FAT Universal binary: magic 0xCAFEBABE, nfat_arch = 2
        var fatData = Data()
        var fatMagic: UInt32 = UInt32(0xCAFEBABE).bigEndian
        var nArch: UInt32 = UInt32(2).bigEndian
        fatData.append(Data(bytes: &fatMagic, count: 4))
        fatData.append(Data(bytes: &nArch, count: 4))

        // Arch 1: arm64 (cputype 0x0100000C)
        var cputype1: UInt32 = UInt32(0x0100000C).bigEndian
        var subtype1: UInt32 = 0
        var offset1: UInt32 = UInt32(4096).bigEndian
        var size1: UInt32 = UInt32(1000).bigEndian
        var align1: UInt32 = UInt32(14).bigEndian
        fatData.append(Data(bytes: &cputype1, count: 4))
        fatData.append(Data(bytes: &subtype1, count: 4))
        fatData.append(Data(bytes: &offset1, count: 4))
        fatData.append(Data(bytes: &size1, count: 4))
        fatData.append(Data(bytes: &align1, count: 4))

        // Arch 2: x86_64 (cputype 0x01000007)
        var cputype2: UInt32 = UInt32(0x01000007).bigEndian
        var subtype2: UInt32 = 0
        var offset2: UInt32 = UInt32(8192).bigEndian
        var size2: UInt32 = UInt32(1000).bigEndian
        var align2: UInt32 = UInt32(14).bigEndian
        fatData.append(Data(bytes: &cputype2, count: 4))
        fatData.append(Data(bytes: &subtype2, count: 4))
        fatData.append(Data(bytes: &offset2, count: 4))
        fatData.append(Data(bytes: &size2, count: 4))
        fatData.append(Data(bytes: &align2, count: 4))

        let fatResult = analyzer.analyzeData(fatData)
        XCTAssertNotNil(fatResult)
        XCTAssertTrue(fatResult!.hasArm64)
        XCTAssertTrue(fatResult!.hasX86_64)
        XCTAssertTrue(fatResult!.isUniversal)
        XCTAssertEqual(fatResult!.displayDescription, "Universal (arm64 + x86_64)")
    }

    // MARK: - Airport Conflict Detection Tests

    func testAirportConflictDetection() async throws {
        let packA = customSceneryDir.appendingPathComponent("Pack_A")
        let packB = customSceneryDir.appendingPathComponent("Pack_B")

        let aptDatDirA = packA.appendingPathComponent("Earth nav data")
        let aptDatDirB = packB.appendingPathComponent("Earth nav data")
        try FileManager.default.createDirectory(at: aptDatDirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aptDatDirB, withIntermediateDirectories: true)

        let aptContentA = """
        I
        1000 Version
        1 292 1 0 LFPO Paris Orly
        100 45.00 1 0 0.25 0 2 0 07L 48.72 2.37 0 0 2 0 0 0
        99
        """

        let aptContentB = """
        I
        1000 Version
        1 290 1 0 LFPO Orly Airport Duplicate
        1 83 1 0 EGLL London Heathrow
        99
        """

        try aptContentA.write(to: aptDatDirA.appendingPathComponent("apt.dat"), atomically: true, encoding: .utf8)
        try aptContentB.write(to: aptDatDirB.appendingPathComponent("apt.dat"), atomically: true, encoding: .utf8)

        let sceneryItems = [
            PluginManager.Scenery(name: "Pack_A", isEnabled: true, folderName: "Pack_A", isManaged: false),
            PluginManager.Scenery(name: "Pack_B", isEnabled: true, folderName: "Pack_B", isManaged: false)
        ]

        let (conflicts, issues) = await AddonDiagnosticsService.shared.analyzeAirportConflicts(
            in: customSceneryDir,
            scenery: sceneryItems
        )

        XCTAssertEqual(conflicts.count, 1)
        let conflict = conflicts.first!
        XCTAssertEqual(conflict.icao, "LFPO")
        XCTAssertEqual(conflict.declaringPacks.count, 2)
        XCTAssertTrue(conflict.declaringPacks[0].isHigherPriority)
        XCTAssertEqual(conflict.declaringPacks[0].folderName, "Pack_A")
        XCTAssertFalse(conflict.declaringPacks[1].isHigherPriority)
        XCTAssertEqual(conflict.declaringPacks[1].folderName, "Pack_B")

        XCTAssertEqual(issues.count, 1)
        let issue = issues.first!
        XCTAssertEqual(issue.category, .sceneryConflict)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.title.contains("LFPO"))
        XCTAssertEqual(issue.quickAction, .disableScenery(folderName: "Pack_B"))
    }

    // MARK: - DSF Overlap Detection Tests

    func testDSFOverlapDetection() async throws {
        let orthoPack = customSceneryDir.appendingPathComponent("zOrtho4XP_+48+002")
        let meshPack = customSceneryDir.appendingPathComponent("yOrtho_Mesh_+48+002")

        let dsfDir1 = orthoPack.appendingPathComponent("Earth nav data/+40+000")
        let dsfDir2 = meshPack.appendingPathComponent("Earth nav data/+40+000")
        try FileManager.default.createDirectory(at: dsfDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dsfDir2, withIntermediateDirectories: true)

        try "dummy dsf 1".write(to: dsfDir1.appendingPathComponent("+48+002.dsf"), atomically: true, encoding: .utf8)
        try "dummy dsf 2".write(to: dsfDir2.appendingPathComponent("+48+002.dsf"), atomically: true, encoding: .utf8)

        let sceneryItems = [
            PluginManager.Scenery(name: "zOrtho4XP_+48+002", isEnabled: true, folderName: "zOrtho4XP_+48+002", isManaged: false),
            PluginManager.Scenery(name: "yOrtho_Mesh_+48+002", isEnabled: true, folderName: "yOrtho_Mesh_+48+002", isManaged: false)
        ]

        let (overlaps, issues) = await AddonDiagnosticsService.shared.analyzeDSFOverlaps(
            in: customSceneryDir,
            scenery: sceneryItems
        )

        // Verifies DSF overlaps are tracked for reporting but do NOT emit warning issues for standard orthos
        XCTAssertEqual(overlaps.count, 1)
        XCTAssertEqual(overlaps.first?.tileCoordinates, "+48+002")
        XCTAssertEqual(overlaps.first?.declaringPacks.count, 2)
        XCTAssertTrue(issues.isEmpty)
    }

    func testBS2001ObjectLibraryDetectionAndSelfExclusion() async throws {
        // Create BS2001 Object Library folder with spaces
        let bs2001Dir = customSceneryDir.appendingPathComponent("BS2001 Object Library")
        try FileManager.default.createDirectory(at: bs2001Dir, withIntermediateDirectories: true)

        let bs2001LibTxt = """
        A
        800
        LIBRARY
        EXPORT bs2001_objects/hangars/hangar1.obj objects/hangar1.obj
        """
        try bs2001LibTxt.write(to: bs2001Dir.appendingPathComponent("library.txt"), atomically: true, encoding: .utf8)
        try "BS2001 Object Library Readme".write(to: bs2001Dir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let sceneryItems = [
            PluginManager.Scenery(name: "BS2001 Object Library", isEnabled: true, folderName: "BS2001 Object Library", isManaged: false)
        ]

        let (missingLibs, issues) = await AddonDiagnosticsService.shared.analyzeMissingLibraries(
            in: customSceneryDir,
            scenery: sceneryItems
        )

        // 1. BS2001 must NOT report itself as missing BS2001
        XCTAssertNil(missingLibs.first(where: { $0.identifier == "bs2001_library" }))
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: - Missing Library Detection Tests

    func testMissingLibraryDetection() async throws {
        let airportPack = customSceneryDir.appendingPathComponent("My_Airport_Pack")
        try FileManager.default.createDirectory(at: airportPack, withIntermediateDirectories: true)

        let manifestContent = """
        A
        800
        LIBRARY
        # Uses OpenSceneryX and MisterX
        EXPORT opensceneryx/buildings/hangar.obj objects/hangar.obj
        EXPORT misterx_library/vehicles/car.obj objects/car.obj
        """
        try manifestContent.write(to: airportPack.appendingPathComponent("library.txt"), atomically: true, encoding: .utf8)

        let sceneryItems = [
            PluginManager.Scenery(name: "My_Airport_Pack", isEnabled: true, folderName: "My_Airport_Pack", isManaged: false)
        ]

        // 1. When libraries are NOT installed:
        let (missingLibs, _) = await AddonDiagnosticsService.shared.analyzeMissingLibraries(
            in: customSceneryDir,
            scenery: sceneryItems
        )

        XCTAssertFalse(missingLibs.isEmpty)
        let openSceneryXRecord = missingLibs.first(where: { $0.identifier == "opensceneryx" })
        XCTAssertNotNil(openSceneryXRecord)
        XCTAssertEqual(openSceneryXRecord?.name, "OpenSceneryX")
        XCTAssertEqual(openSceneryXRecord?.downloadURL?.host, "www.opensceneryx.com")

        // 2. When OpenSceneryX IS installed:
        let installedLibDir = customSceneryDir.appendingPathComponent("OpenSceneryX")
        try FileManager.default.createDirectory(at: installedLibDir, withIntermediateDirectories: true)
        let libTxt = """
        A
        800
        LIBRARY
        EXPORT opensceneryx/buildings/hangar.obj actual_hangar.obj
        """
        try libTxt.write(to: installedLibDir.appendingPathComponent("library.txt"), atomically: true, encoding: .utf8)

        let (missingAfterInstall, _) = await AddonDiagnosticsService.shared.analyzeMissingLibraries(
            in: customSceneryDir,
            scenery: sceneryItems
        )
        XCTAssertNil(missingAfterInstall.first(where: { $0.identifier == "opensceneryx" }))
    }

    // MARK: - Add-on Integrity Tests

    func testAddonIntegrityBrokenSymlinkAndEmptyFolder() async throws {
        // 1. Create a broken symlink in plugins
        let brokenLink = pluginsDir.appendingPathComponent("DanglingPlugin")
        let nonExistentTarget = tempDir.appendingPathComponent("NonExistent_Folder")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: nonExistentTarget)

        // 2. Create an empty folder in storage pool
        let emptyAircraft = poolDir.appendingPathComponent("Aircraft").appendingPathComponent("GhostPlane")
        try FileManager.default.createDirectory(at: emptyAircraft, withIntermediateDirectories: true)

        let pool = StoragePool(name: "MainPool", url: poolDir, isPrimary: true)

        let issues = await AddonDiagnosticsService.shared.analyzeAddonIntegrity(
            xPlanePath: xPlaneDir,
            storagePools: [pool],
            plugins: [],
            aircraft: [],
            scenery: [],
            luaScripts: []
        )

        let brokenSymlinkIssue = issues.first(where: { $0.title.contains("Broken Symlink: DanglingPlugin") })
        XCTAssertNotNil(brokenSymlinkIssue)
        XCTAssertEqual(brokenSymlinkIssue?.severity, .warning)
        if case .deleteItem(let url) = brokenSymlinkIssue?.quickAction {
            XCTAssertEqual(url.lastPathComponent, brokenLink.lastPathComponent)
        } else {
            XCTFail("Expected deleteItem quickAction for broken symlink")
        }

        let emptyFolderIssue = issues.first(where: { $0.title.contains("Empty Add-on Folder: GhostPlane") })
        XCTAssertNotNil(emptyFolderIssue)
        XCTAssertEqual(emptyFolderIssue?.severity, .info)
        if case .deleteItem(let url) = emptyFolderIssue?.quickAction {
            XCTAssertEqual(url.lastPathComponent, emptyAircraft.lastPathComponent)
        } else {
            XCTFail("Expected deleteItem quickAction for empty folder")
        }
    }

    // MARK: - Plugin Platform Compatibility Tests

    func testPluginPlatformCompatibilityWindowsOnly() async throws {
        let winPluginDir = pluginsDir.appendingPathComponent("WindowsOnlyPlugin")
        let win64Dir = winPluginDir.appendingPathComponent("win_x64")
        try FileManager.default.createDirectory(at: win64Dir, withIntermediateDirectories: true)
        try "dummy exe".write(to: win64Dir.appendingPathComponent("win.xpl"), atomically: true, encoding: .utf8)

        let plugin = PluginManager.Plugin(
            name: "WindowsOnlyPlugin",
            isEnabled: true,
            folderName: "WindowsOnlyPlugin"
        )

        let issues = await AddonDiagnosticsService.shared.analyzePluginCompatibility(
            xPlanePath: xPlaneDir,
            plugins: [plugin]
        )

        XCTAssertEqual(issues.count, 1)
        let issue = issues.first!
        XCTAssertEqual(issue.category, .compatibility)
        XCTAssertEqual(issue.severity, .critical)
        XCTAssertTrue(issue.title.contains("Non-macOS Plugin"))
        XCTAssertEqual(issue.quickAction, .disablePlugin(folderName: "WindowsOnlyPlugin"))
    }

    // MARK: - Known Library Loading Tests

    func testKnownLibrariesLoading() {
        let libraries = AddonDiagnosticsService.knownLibraries
        XCTAssertFalse(libraries.isEmpty, "Known libraries list should not be empty")
        XCTAssertTrue(libraries.contains(where: { $0.identifier == "opensceneryx" }))
        XCTAssertTrue(libraries.contains(where: { $0.identifier == "misterx_library" }))
        XCTAssertTrue(libraries.contains(where: { $0.identifier == "bs2001_library" }))

        for lib in libraries {
            XCTAssertFalse(lib.identifier.isEmpty)
            XCTAssertFalse(lib.name.isEmpty)
            XCTAssertFalse(lib.prefixKeys.isEmpty)
        }
    }
}
