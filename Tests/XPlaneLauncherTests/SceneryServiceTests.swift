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

        // 2. Create managed scenery pack (uninstalled)
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
        // 1. Installed but not in INI (PackC)
        // 2. INI items (PackA, PackB, *GLOBAL_AIRPORTS*)
        // 3. Uninstalled items from managed folder (PackD)
        XCTAssertEqual(result.count, 5)

        XCTAssertEqual(result[0].name, "PackC")
        XCTAssertTrue(result[0].isEnabled)
        XCTAssertFalse(result[0].isInIni)

        XCTAssertEqual(result[1].name, "PackA")
        XCTAssertTrue(result[1].isEnabled)
        XCTAssertTrue(result[1].isInIni)

        XCTAssertEqual(result[2].name, "PackB")
        XCTAssertFalse(result[2].isEnabled)
        XCTAssertTrue(result[2].isInIni)

        XCTAssertEqual(result[3].name, "*GLOBAL_AIRPORTS*")
        XCTAssertTrue(result[3].isEnabled)
        XCTAssertTrue(result[3].isInIni)
        XCTAssertFalse(result[3].isToggleable)

        XCTAssertEqual(result[4].name, "PackD")
        XCTAssertFalse(result[4].isEnabled)
        XCTAssertTrue(result[4].isManaged)
        XCTAssertFalse(result[4].isInIni)
    }

    // MARK: - Save Scenery Order Tests

    func testSaveSceneryOrder() throws {
        let packA = customSceneryFolder.appendingPathComponent("PackA")
        let packB = customSceneryFolder.appendingPathComponent("PackB")
        try fm.createDirectory(at: packA, withIntermediateDirectories: true)
        try fm.createDirectory(at: packB, withIntermediateDirectories: true)

        let sceneryItems: [Scenery] = [
            Scenery(name: "PackA", isEnabled: true, folderName: "PackA", isManaged: false, isInIni: true, iniLine: ""),
            Scenery(name: "*SPECIAL*", isEnabled: true, folderName: "*SPECIAL*", isManaged: false, isInIni: true, iniLine: ""),
            Scenery(name: "PackB", isEnabled: false, folderName: "PackB", isManaged: false, isInIni: true, iniLine: ""),
            Scenery(name: "UninstalledPack", isEnabled: false, folderName: "UninstalledPack", isManaged: true, isInIni: false, iniLine: "")
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
        let item1 = Scenery(name: "Scenery1", isEnabled: true, folderName: "Scenery1", isManaged: true, isInIni: true, iniLine: "")
        let item2 = Scenery(name: "Scenery2", isEnabled: true, folderName: "Scenery2", isManaged: true, isInIni: true, iniLine: "")
        let item3 = Scenery(name: "Scenery3", isEnabled: true, folderName: "Scenery3", isManaged: true, isInIni: true, iniLine: "")

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
}
