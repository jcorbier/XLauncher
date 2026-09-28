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

final class SceneryServiceTests: XCTestCase {

    var tempDir: URL!
    var customSceneryFolder: URL!
    var managedSceneryFolder: URL!
    var iniURL: URL!
    let sceneryService = SceneryService.shared
    let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("XLauncher_SceneryTests_\(UUID().uuidString)")
        customSceneryFolder = tempDir.appendingPathComponent("Custom Scenery")
        managedSceneryFolder = tempDir.appendingPathComponent("ManagedScenery")
        iniURL = customSceneryFolder.appendingPathComponent("scenery_packs.ini")

        try fm.createDirectory(at: customSceneryFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: managedSceneryFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Scan Scenery Tests

    func testScanSceneryWithIniAndInstalledPacks() throws {
        // 1. Create scenery packs in Custom Scenery
        let packA = customSceneryFolder.appendingPathComponent("PackA")
        let packB = customSceneryFolder.appendingPathComponent("PackB")
        let packC = customSceneryFolder.appendingPathComponent("PackC") // Not in INI
        try fm.createDirectory(at: packA, withIntermediateDirectories: true)
        try fm.createDirectory(at: packB, withIntermediateDirectories: true)
        try fm.createDirectory(at: packC, withIntermediateDirectories: true)

        // 2. Create managed scenery pack in Central Data Folder
        let packD = managedSceneryFolder.appendingPathComponent("PackD")
        try fm.createDirectory(at: packD, withIntermediateDirectories: true)

        // 3. Write scenery_packs.ini
        let iniContent = """
        I
        1000 Version
        SCENERY

        SCENERY_PACK Custom Scenery/PackA/
        SCENERY_PACK_DISABLED Custom Scenery/PackB/
        SCENERY_PACK *GLOBAL_AIRPORTS*
        """
        try iniContent.write(to: iniURL, atomically: true, encoding: .utf8)

        // 4. Scan
        let result = try sceneryService.scanScenery(
            customSceneryFolder: customSceneryFolder,
            managedSceneryFolder: managedSceneryFolder,
            iniURL: iniURL
        )

        // Expected order:
        // 1. Installed but not in INI (PackC, and newly linked managed pack PackD)
        // 2. INI items (PackA, PackB, *GLOBAL_AIRPORTS*)
        XCTAssertEqual(result.count, 5)

        XCTAssertEqual(result[0].name, "PackC")
        XCTAssertTrue(result[0].isEnabled)
        XCTAssertFalse(result[0].isManaged)

        XCTAssertEqual(result[1].name, "PackD")
        XCTAssertTrue(result[1].isEnabled)
        XCTAssertTrue(result[1].isManaged)

        XCTAssertEqual(result[2].name, "PackA")
        XCTAssertTrue(result[2].isEnabled)

        XCTAssertEqual(result[3].name, "PackB")
        XCTAssertFalse(result[3].isEnabled)

        XCTAssertEqual(result[4].name, "*GLOBAL_AIRPORTS*")
        XCTAssertTrue(result[4].isEnabled)
        XCTAssertFalse(result[4].isToggleable)
    }

    // MARK: - Save Scenery Order Tests

    func testSaveSceneryOrder() throws {
        let packA = customSceneryFolder.appendingPathComponent("PackA")
        let packB = customSceneryFolder.appendingPathComponent("PackB")
        try fm.createDirectory(at: packA, withIntermediateDirectories: true)
        try fm.createDirectory(at: packB, withIntermediateDirectories: true)

        let sceneryItems: [Scenery] = [
            Scenery(name: "PackA", isEnabled: true, folderName: "PackA", isManaged: false, iniLine: ""),
            Scenery(name: "*SPECIAL*", isEnabled: true, folderName: "*SPECIAL*", isManaged: false, iniLine: ""),
            Scenery(name: "PackB", isEnabled: false, folderName: "PackB", isManaged: false, iniLine: ""),
            Scenery(name: "UninstalledPack", isEnabled: false, folderName: "UninstalledPack", isManaged: true, iniLine: "")
        ]

        try sceneryService.saveSceneryOrder(scenery: sceneryItems, customSceneryFolder: customSceneryFolder, iniURL: iniURL)

        let savedContent = try String(contentsOf: iniURL, encoding: .utf8)
        let lines = savedContent.components(separatedBy: .newlines).filter { !$0.isEmpty }

        XCTAssertEqual(lines[0], "I")
        XCTAssertEqual(lines[1], "1000 Version")
        XCTAssertEqual(lines[2], "SCENERY")
        XCTAssertEqual(lines[3], "SCENERY_PACK Custom Scenery/PackA/")
        XCTAssertEqual(lines[4], "SCENERY_PACK *SPECIAL*")
        XCTAssertEqual(lines[5], "SCENERY_PACK_DISABLED Custom Scenery/PackB/")
        // UninstalledPack does not exist on disk in customSceneryFolder and is not special, so it must NOT be written to the INI
        XCTAssertFalse(savedContent.contains("UninstalledPack"))
    }

    func testSaveSceneryOrderRejectsOutOfBoundaryIni() {
        let outOfBoundsIni = tempDir.appendingPathComponent("other.ini")
        let items: [Scenery] = []

        XCTAssertThrowsError(
            try sceneryService.saveSceneryOrder(scenery: items, customSceneryFolder: customSceneryFolder, iniURL: outOfBoundsIni)
        )
    }

    // MARK: - Link & Unlink Tests

    func testLinkAndUnlinkScenery() throws {
        let packName = "LFPG_Paris"
        let sourceFolder = managedSceneryFolder.appendingPathComponent(packName)
        try fm.createDirectory(at: sourceFolder, withIntermediateDirectories: true)

        // 1. Link
        try sceneryService.linkScenery(
            folderName: packName,
            managedSceneryFolder: managedSceneryFolder,
            customSceneryFolder: customSceneryFolder
        )

        let linkURL = customSceneryFolder.appendingPathComponent(packName)
        XCTAssertTrue(fm.fileExists(atPath: linkURL.path))
        let attrs = try fm.attributesOfItem(atPath: linkURL.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)

        // 2. Unlink
        try sceneryService.unlinkScenery(folderName: packName, customSceneryFolder: customSceneryFolder)
        XCTAssertFalse(fm.fileExists(atPath: linkURL.path))
        XCTAssertTrue(fm.fileExists(atPath: sourceFolder.path), "Source folder in managed directory must remain intact")
    }

    func testLinkSceneryDoesNotOverwriteRealDirectory() throws {
        let packName = "RealScenery"
        let realDir = customSceneryFolder.appendingPathComponent(packName)
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)
        let markerFile = realDir.appendingPathComponent("marker.txt")
        try "important data".write(to: markerFile, atomically: true, encoding: .utf8)

        let managedDir = managedSceneryFolder.appendingPathComponent(packName)
        try fm.createDirectory(at: managedDir, withIntermediateDirectories: true)

        // Attempting to link should not overwrite existing unmanaged directory
        try sceneryService.linkScenery(
            folderName: packName,
            managedSceneryFolder: managedSceneryFolder,
            customSceneryFolder: customSceneryFolder
        )

        XCTAssertTrue(fm.fileExists(atPath: markerFile.path))
        let attrs = try fm.attributesOfItem(atPath: realDir.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeDirectory)
    }

    // MARK: - Group Management Tests

    func testCreateGroupAndRemoveFromGroup() {
        let item1 = Scenery(name: "Scenery1", isEnabled: true, folderName: "Scenery1", isManaged: true, iniLine: "")
        let item2 = Scenery(name: "Scenery2", isEnabled: true, folderName: "Scenery2", isManaged: true, iniLine: "")
        let item3 = Scenery(name: "Scenery3", isEnabled: true, folderName: "Scenery3", isManaged: true, iniLine: "")

        let existingScenery = [item1, item2, item3]
        let existingGroups: [SceneryGroup] = []

        let result = sceneryService.createGroup(
            name: "Airports",
            items: [item1, item3],
            existingGroups: existingGroups,
            existingScenery: existingScenery
        )

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].name, "Airports")
        XCTAssertEqual(result.groups[0].childFolderNames, ["Scenery1", "Scenery3"])

        // Test deleteGroup
        let remainingGroups = sceneryService.deleteGroup(group: result.groups[0], existingGroups: result.groups)
        XCTAssertTrue(remainingGroups.isEmpty)

        // Test removeFromGroup
        let afterRemoval = sceneryService.removeFromGroup(sceneryItem: item1, existingGroups: result.groups)
        XCTAssertEqual(afterRemoval[0].childFolderNames, ["Scenery3"])
    }

    // MARK: - Auto-Organize Tests

    func testAutoOrganizeSceneryStandardHierarchy() {
        let airport1 = Scenery(name: "LFPG Paris CDG", isEnabled: true, folderName: "LFPG_Paris_CDG", isManaged: true, iniLine: "")
        let airport2 = Scenery(name: "EDDF Frankfurt", isEnabled: true, folderName: "EDDF_Frankfurt", isManaged: true, iniLine: "")
        let landmark = Scenery(name: "Paris Landmarks VFR", isEnabled: true, folderName: "Paris_Landmarks_VFR", isManaged: true, iniLine: "")
        let library = Scenery(name: "OpenSceneryX", isEnabled: true, folderName: "OpenSceneryX", isManaged: true, iniLine: "")
        let other = Scenery(name: "Custom Objects", isEnabled: true, folderName: "Custom_Objects", isManaged: true, iniLine: "")
        let overlay = Scenery(name: "SimHeaven X-World Europe Forests", isEnabled: true, folderName: "simHeaven_X-World_Europe-3-forests", isManaged: true, iniLine: "")
        let mesh = Scenery(name: "zOrtho4XP +48+002", isEnabled: true, folderName: "zOrtho4XP_+48+002", isManaged: true, iniLine: "")

        // Pass sceneries in reverse/random order
        let unordered = [mesh, overlay, library, landmark, airport1, other, airport2]

        let organized = sceneryService.autoOrganizeScenery(scenery: unordered, groups: []) { item in
            switch item.folderName {
            case "LFPG_Paris_CDG", "EDDF_Frankfurt": return .airport
            case "Paris_Landmarks_VFR": return .landmark
            case "OpenSceneryX": return .library
            case "Custom_Objects": return .other
            case "simHeaven_X-World_Europe-3-forests": return .overlay
            case "zOrtho4XP_+48+002": return .meshOrtho
            default: return .other
            }
        }

        // Expected hierarchy:
        // 1. Airports (alphabetical: EDDF Frankfurt, then LFPG Paris CDG)
        // 2. Landmarks (Paris Landmarks VFR)
        // 3. Libraries (OpenSceneryX)
        // 4. Other (Custom Objects)
        // 5. Overlays (SimHeaven X-World Europe Forests)
        // 6. Mesh & Ortho (zOrtho4XP +48+002)
        let expectedNames = [
            "EDDF Frankfurt",
            "LFPG Paris CDG",
            "Paris Landmarks VFR",
            "OpenSceneryX",
            "Custom Objects",
            "SimHeaven X-World Europe Forests",
            "zOrtho4XP +48+002"
        ]

        XCTAssertEqual(organized.map(\.name), expectedNames)
    }

    func testAutoOrganizeSceneryWithGroups() {
        let airport = Scenery(name: "LFPG Paris", isEnabled: true, folderName: "LFPG_Paris", isManaged: true, iniLine: "")
        let shVFR = Scenery(name: "simHeaven X-World Europe 1 VFR", isEnabled: true, folderName: "sh_1_vfr", isManaged: true, iniLine: "")
        let shRegions = Scenery(name: "simHeaven X-World Europe 2 Regions", isEnabled: true, folderName: "sh_2_regions", isManaged: true, iniLine: "")
        let shForests = Scenery(name: "simHeaven X-World Europe 3 Forests", isEnabled: true, folderName: "sh_3_forests", isManaged: true, iniLine: "")
        let mesh = Scenery(name: "zOrtho4XP +48+002", isEnabled: true, folderName: "zOrtho4XP_+48+002", isManaged: true, iniLine: "")

        let shGroup = SceneryGroup(
            name: "SimHeaven Europe",
            childFolderNames: ["sh_3_forests", "sh_1_vfr", "sh_2_regions"]
        )

        let unordered = [mesh, airport, shForests, shVFR, shRegions]

        let organized = sceneryService.autoOrganizeScenery(scenery: unordered, groups: [shGroup]) { item in
            switch item.folderName {
            case "LFPG_Paris": return .airport
            case "sh_1_vfr", "sh_2_regions", "sh_3_forests": return .overlay
            case "zOrtho4XP_+48+002": return .meshOrtho
            default: return .other
            }
        }

        // Expected:
        // 1. Airport (LFPG Paris)
        // 2. SimHeaven Group (SimHeaven Europe members sorted naturally within the group: sh_1_vfr, sh_2_regions, sh_3_forests)
        // 3. Mesh (zOrtho4XP +48+002)
        XCTAssertEqual(organized.count, 5)
        XCTAssertEqual(organized[0].folderName, "LFPG_Paris")
        XCTAssertEqual(organized[1].folderName, "sh_1_vfr")
        XCTAssertEqual(organized[2].folderName, "sh_2_regions")
        XCTAssertEqual(organized[3].folderName, "sh_3_forests")
        XCTAssertEqual(organized[4].folderName, "zOrtho4XP_+48+002")
    }
}
