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

final class UpdaterConfigParserTests: XCTestCase {

    var tempDir: URL!
    let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempDir = fm.temporaryDirectory.appendingPathComponent("XLauncher_UpdaterTests_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - SkunkCrafts Updater Tests

    func testParseSkunkCraftsConfigPipeFormat() throws {
        let configFile = tempDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let content = """
        # SkunkCrafts Updater Configuration
        name|ToLiss A321
        version|1.4.1
        url|https://updates.toliss.com/a321/
        """
        try content.write(to: configFile, atomically: true, encoding: .utf8)

        let service = SkunkCraftsUpdaterService.shared
        let config = service.parseConfig(at: configFile, defaultName: "DefaultName")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.name, "ToLiss A321")
        XCTAssertEqual(config?.version, "1.4.1")
        XCTAssertEqual(config?.remoteManifestURL, "https://updates.toliss.com/a321/")
    }

    func testParseSkunkCraftsWhitelist() {
        let whitelistContent = """
        # Metadata header lines
        name|Aircraft
        version|1.0

        # Whitelisted files
        plugins/sound.xpl|0xABCD1234|102400
        liveries/texture.dds|4294967295|2048000
        documentation/manual.pdf
        """

        let service = SkunkCraftsUpdaterService.shared
        let items = service.parseWhitelist(content: whitelistContent)

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].relativePath, "plugins/sound.xpl")
        XCTAssertEqual(items[0].expectedCRC, "0xABCD1234")
        XCTAssertEqual(items[0].expectedSize, 102400)

        XCTAssertEqual(items[1].relativePath, "liveries/texture.dds")
        XCTAssertEqual(items[1].expectedCRC, "4294967295")

        XCTAssertEqual(items[2].relativePath, "documentation/manual.pdf")
        XCTAssertNil(items[2].expectedCRC)
    }

    func testSkunkCraftsIgnoreMatching() {
        let service = SkunkCraftsUpdaterService.shared
        let ignoredSet: Set<String> = [
            "preferences/settings.cfg",
            "liveries/custom",
            "*.bak"
        ]

        XCTAssertTrue(service.isIgnored(relativePath: "preferences/settings.cfg", ignoredSet: ignoredSet))
        XCTAssertTrue(service.isIgnored(relativePath: "liveries/custom/paint.png", ignoredSet: ignoredSet))
        XCTAssertTrue(service.isIgnored(relativePath: "plane.obj.bak", ignoredSet: ignoredSet))
        XCTAssertFalse(service.isIgnored(relativePath: "objects/plane.obj", ignoredSet: ignoredSet))
    }

    func testSkunkCraftsCRC32Parsing() {
        let service = SkunkCraftsUpdaterService.shared
        XCTAssertEqual(service.parseCRC32("4294967295"), UInt32(4294967295))
        XCTAssertEqual(service.parseCRC32("0xFFFFFFFF"), UInt32(0xFFFFFFFF))
        XCTAssertEqual(service.parseCRC32("0x1a2b3c4d"), UInt32(0x1a2b3c4d))
        XCTAssertNil(service.parseCRC32("invalid"))
    }

    // MARK: - X-Updater Tests

    func testParseXUpdaterSettingsIni() throws {
        let configFile = tempDir.appendingPathComponent("settings.ini")
        let content = """
        [General]
        product_name = FlightFactor 777-200ER
        product_version = 020100
        snapshot_num = 450
        update_url = https://update.x-plane.org
        user_name = pilot@flightfactor.aero
        license_key = ABCDE-12345
        productid = ff777_v2
        preferred_release_type = release
        """
        try content.write(to: configFile, atomically: true, encoding: .utf8)

        let service = XUpdaterService.shared
        let config = service.parseConfig(at: configFile, defaultName: "FF777")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.name, "FlightFactor 777-200ER")
        // 6-digit version format "020100" converts to "2.1.0"
        XCTAssertEqual(config?.version, "2.1.0")
        XCTAssertEqual(config?.snapshotNum, 450)
        XCTAssertEqual(config?.login, "pilot@flightfactor.aero")
        XCTAssertEqual(config?.licenseKey, "ABCDE-12345")
        XCTAssertEqual(config?.productId, "ff777_v2")
        XCTAssertFalse(config?.betaEnabled ?? true)
    }

    func testXUpdaterResolveLocalFilePNGDDSAndCaseInsensitivity() throws {
        let service = XUpdaterService.shared
        let texturesDir = tempDir.appendingPathComponent("objects")
        try fm.createDirectory(at: texturesDir, withIntermediateDirectories: true)

        // Create texture.dds on disk
        let ddsFile = texturesDir.appendingPathComponent("fuselage.dds")
        try "DDS DATA".write(to: ddsFile, atomically: true, encoding: .utf8)

        // Manifest requests objects/fuselage.png (PNG <-> DDS equivalence)
        let resolved = service.resolveLocalFile(itemPath: "objects/fuselage.png", in: tempDir)
        XCTAssertTrue(resolved.exists)
        XCTAssertEqual(resolved.actualURL?.lastPathComponent, "fuselage.dds")
    }

    // MARK: - CSL Index Parser Tests

    func testCSLIndexParser() {
        let indexContent = """
        0 Comment line
        11%B737_Package%150000000%Reserve%2026-08-01%12:00
        10%B737_Package/xsb_aircraft.txt%4096%a1b2c3d4e5f6%2026-08-01%12:00
        10%B737_Package/objects/b738.obj%1024000%098f6bcd4621d373cade4e832627b4f6%2026-08-01%12:00
        11%A320_Package%200000000%Reserve%2026-08-01%12:00
        10%A320_Package/xsb_aircraft.txt%2048%e5f6a1b2c3d4%2026-08-01%12:00
        """

        let packages = CSLIndexParser.parseIndex(content: indexContent)

        XCTAssertEqual(packages.count, 2)
        XCTAssertEqual(packages[0].name, "A320_Package")
        XCTAssertEqual(packages[0].headerSize, 200000000)
        XCTAssertEqual(packages[0].files.count, 1)

        XCTAssertEqual(packages[1].name, "B737_Package")
        XCTAssertEqual(packages[1].headerSize, 150000000)
        XCTAssertEqual(packages[1].files.count, 2)
        XCTAssertEqual(packages[1].files[0].path, "B737_Package/xsb_aircraft.txt")
        XCTAssertEqual(packages[1].files[1].md5, "098f6bcd4621d373cade4e832627b4f6")
    }
}
