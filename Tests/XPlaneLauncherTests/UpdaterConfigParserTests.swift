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

    func testParseSkunkCraftsWhitelistColonFormat() {
        let whitelistContent = """
        # Metadata
        name:Some Addon
        version:2.0.0

        # Files
        plugins/win.xpl:0x12345678:65536
        sounds/GPWS/PULL UP.MP3:14678
        liveries\\custom\\paint.png:4294967295:1024
        /objects/aircraft.obj:abcd1234:2048
        """

        let service = SkunkCraftsUpdaterService.shared
        let items = service.parseWhitelist(content: whitelistContent)

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].relativePath, "plugins/win.xpl")
        XCTAssertEqual(items[0].expectedCRC, "0x12345678")
        XCTAssertEqual(items[0].expectedSize, 65536)

        XCTAssertEqual(items[1].relativePath, "sounds/GPWS/PULL UP.MP3")
        XCTAssertEqual(items[1].expectedCRC, "14678")
        XCTAssertNil(items[1].expectedSize)

        XCTAssertEqual(items[2].relativePath, "liveries/custom/paint.png")
        XCTAssertEqual(items[2].expectedCRC, "4294967295")
        XCTAssertEqual(items[2].expectedSize, 1024)

        XCTAssertEqual(items[3].relativePath, "objects/aircraft.obj")
        XCTAssertEqual(items[3].expectedCRC, "abcd1234")
        XCTAssertEqual(items[3].expectedSize, 2048)
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
        XCTAssertEqual(service.parseCRC32("0X1A2B3C4D"), UInt32(0x1a2b3c4d))
        XCTAssertEqual(service.parseCRC32("abcd1234"), UInt32(0xabcd1234))
        XCTAssertEqual(service.parseCRC32("ABCD1234"), UInt32(0xabcd1234))
        XCTAssertEqual(service.parseCRC32("-1"), UInt32(0xFFFFFFFF))
        XCTAssertEqual(service.parseCRC32("-1053423"), UInt32(bitPattern: -1053423))
        XCTAssertNil(service.parseCRC32("invalid"))
    }

    func testSkunkCraftsCalculateCRC32() throws {
        let service = SkunkCraftsUpdaterService.shared
        let testFile = tempDir.appendingPathComponent("test_crc.txt")
        // "123456789" is standard test vector for CRC32 -> 0xCBF43926 = 3421780262
        try "123456789".write(to: testFile, atomically: true, encoding: .utf8)

        let crc = service.calculateCRC32UInt32(for: testFile)
        XCTAssertEqual(crc, UInt32(0xCBF43926))
    }

    func testSkunkCraftsSentinelCRCsRecognized() {
        let service = SkunkCraftsUpdaterService.shared
        // 4294967295, 0xFFFFFFFF, -1, and 0 are sentinel placeholder CRCs in SkunkCrafts manifests
        XCTAssertEqual(service.parseCRC32("4294967295"), 0xFFFFFFFF)
        XCTAssertEqual(service.parseCRC32("0xFFFFFFFF"), 0xFFFFFFFF)
        XCTAssertEqual(service.parseCRC32("-1"), 0xFFFFFFFF)
        XCTAssertEqual(service.parseCRC32("0"), 0)
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

    func testXUpdaterUpdateLocalSettingsIniWithSixDigitVersion() async throws {
        let service = XUpdaterService.shared
        let addonDir = tempDir.appendingPathComponent("FF777")
        let updaterDir = addonDir.appendingPathComponent(".xupdater")
        try fm.createDirectory(at: updaterDir, withIntermediateDirectories: true)

        let settingsFile = updaterDir.appendingPathComponent("settings.ini")
        let initialContent = """
        [General]
        product_name = FlightFactor 777-200ER
        product_version = 020523
        snapshot_num = 27
        """
        try initialContent.write(to: settingsFile, atomically: true, encoding: .utf8)

        // Update settings to snapshot 28 and version 2.5.26
        await service.updateLocalSettings(in: addonDir, newSnapshotNum: 28, newVersion: "2.5.26")

        let config = service.parseConfig(at: settingsFile, defaultName: "FF777")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.version, "2.5.26")
        XCTAssertEqual(config?.snapshotNum, 28)

        let writtenContent = try String(contentsOf: settingsFile, encoding: .utf8)
        XCTAssertTrue(writtenContent.contains("product_version=020526") || writtenContent.contains("product_version = 020526"))
        XCTAssertTrue(writtenContent.contains("snapshot_num=28") || writtenContent.contains("snapshot_num = 28"))
    }

    func testXUpdaterUpdateLocalSettingsJson() async throws {
        let service = XUpdaterService.shared
        let addonDir = tempDir.appendingPathComponent("CustomAddon")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let jsonFile = addonDir.appendingPathComponent("x-updater.json")
        let initialJson: [String: Any] = [
            "name": "Custom Aircraft",
            "version": "1.0.0",
            "snapshot_num": 10
        ]
        let data = try JSONSerialization.data(withJSONObject: initialJson, options: .prettyPrinted)
        try data.write(to: jsonFile)

        await service.updateLocalSettings(in: addonDir, newSnapshotNum: 11, newVersion: "1.1.0")

        let config = service.parseConfig(at: jsonFile, defaultName: "Custom Aircraft")
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.version, "1.1.0")
        XCTAssertEqual(config?.snapshotNum, 11)
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

    func testCSLPackageConfigParsing() {
        let iniContent = """
        [x-csl-package]
        ; not change
        remoteDir="."
        localDir="Resources/plugins/IVAO_CSL/CSL"

        [folders]
        ; additional folders prefixes
        PilotUI="Resources/plugins/ivao_pilot/PilotUI/data"
        Resources="Resources/plugins/IVAO_CSL"
        """

        let config = CSLPackageConfig.parse(content: iniContent)
        XCTAssertEqual(config.remoteDir, ".")
        XCTAssertEqual(config.localDir, "Resources/plugins/IVAO_CSL/CSL")
        XCTAssertEqual(config.folders["PilotUI"], "Resources/plugins/ivao_pilot/PilotUI/data")
        XCTAssertEqual(config.folders["Resources"], "Resources/plugins/IVAO_CSL")
    }

    func testAltitudeDestinationResolution() {
        let iniContent = """
        [x-csl-package]
        remoteDir="."
        localDir="Resources/plugins/IVAO_CSL/CSL"

        [folders]
        PilotUI="Resources/plugins/ivao_pilot/PilotUI/data"
        Resources="Resources/plugins/IVAO_CSL"
        """
        let config = CSLPackageConfig.parse(content: iniContent)

        let fakeXPlane = tempDir.appendingPathComponent("X-Plane")
        let fakeCSL = fakeXPlane.appendingPathComponent("Resources/plugins/IVAO_CSL/CSL")

        // 1. ALTITUDE/PilotUI/mtlList.xml -> <fakeXPlane>/Resources/plugins/ivao_pilot/PilotUI/data/mtlList.xml
        let mtlURL = CSLUpdaterService.resolveDestinationURL(
            fileItemPath: "ALTITUDE/PilotUI/mtlList.xml",
            packageName: "ALTITUDE",
            config: config,
            cslBaseFolder: fakeCSL,
            xPlaneBaseFolder: fakeXPlane
        )
        XCTAssertNotNil(mtlURL)
        XCTAssertTrue(mtlURL?.path.hasSuffix("Resources/plugins/ivao_pilot/PilotUI/data/mtlList.xml") ?? false)

        // 2. ALTITUDE/Resources/Doc8643.txt -> <fakeXPlane>/Resources/plugins/IVAO_CSL/Doc8643.txt
        let docURL = CSLUpdaterService.resolveDestinationURL(
            fileItemPath: "ALTITUDE/Resources/Doc8643.txt",
            packageName: "ALTITUDE",
            config: config,
            cslBaseFolder: fakeCSL,
            xPlaneBaseFolder: fakeXPlane
        )
        XCTAssertNotNil(docURL)
        XCTAssertTrue(docURL?.path.hasSuffix("Resources/plugins/IVAO_CSL/Doc8643.txt") ?? false)

        // 3. Regular model: B738/xsb_aircraft.txt -> <fakeCSL>/B738/xsb_aircraft.txt
        let cslModelURL = CSLUpdaterService.resolveDestinationURL(
            fileItemPath: "B738/xsb_aircraft.txt",
            packageName: "B738",
            config: nil,
            cslBaseFolder: fakeCSL,
            xPlaneBaseFolder: fakeXPlane
        )
        XCTAssertNotNil(cslModelURL)
        XCTAssertTrue(cslModelURL?.path.hasSuffix("Resources/plugins/IVAO_CSL/CSL/B738/xsb_aircraft.txt") ?? false)
    }

    func testAltitudeFilesIndexParsing() {
        let altitudeIndex = """
        0 X-CSL-Package index file; Version: ver.10-08-2026.19:27; Created: 10.08.2026 19:27:35;
        11%ALTITUDE%1049562%Reserve%29-07-2024%22:41:43
        10%ALTITUDE/Resources/Doc8643.txt%334474%0f82f77d9d19f87f3d6ae35814fc0d40%13.04.2024%20:42:38
        10%ALTITUDE/Resources/Contrail/Contrail.obj%189%31d0d5e4548de2dce43ff38313cc578f%16.10.2023%18:26:34
        10%ALTITUDE/PilotUI/mtlList.xml%687921%c3323fee685c09396031e59baab6725f%10.08.2026%19:27:30
        """

        let packages = CSLIndexParser.parseIndex(content: altitudeIndex)
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].name, "ALTITUDE")
        XCTAssertEqual(packages[0].files.count, 3)
        XCTAssertEqual(packages[0].files[2].path, "ALTITUDE/PilotUI/mtlList.xml")
        XCTAssertEqual(packages[0].files[2].sizeBytes, 687921)
    }

    func testAltitudeDestinationResolutionWhenDisabledInCentralFolder() throws {
        let iniContent = """
        [x-csl-package]
        remoteDir="."
        localDir="Resources/plugins/IVAO_CSL/CSL"

        [folders]
        PilotUI="Resources/plugins/ivao_pilot/PilotUI/data"
        Resources="Resources/plugins/IVAO_CSL"
        """
        let config = CSLPackageConfig.parse(content: iniContent)

        let fakeXPlane = tempDir.appendingPathComponent("X-Plane")
        let fakeCSL = fakeXPlane.appendingPathComponent("Resources/plugins/IVAO_CSL/CSL")
        let fakeCentral = tempDir.appendingPathComponent("CentralData")
        let fakeCentralIvaoPilot = fakeCentral.appendingPathComponent("Plugins/ivao_pilot/PilotUI/data")
        try fm.createDirectory(at: fakeCentralIvaoPilot, withIntermediateDirectories: true)

        // ivao_pilot is NOT present in fakeXPlane/Resources/plugins, only in fakeCentral/Plugins/ivao_pilot
        let mtlURL = CSLUpdaterService.resolveDestinationURL(
            fileItemPath: "ALTITUDE/PilotUI/mtlList.xml",
            packageName: "ALTITUDE",
            config: config,
            cslBaseFolder: fakeCSL,
            xPlaneBaseFolder: fakeXPlane,
            launcherDataFolder: fakeCentral
        )
        XCTAssertNotNil(mtlURL)
        XCTAssertEqual(mtlURL?.path, fakeCentralIvaoPilot.appendingPathComponent("mtlList.xml").path)
    }

    @MainActor
    func testCSLLightsUpdaterDeduplication() async throws {
        let pkgDir = tempDir.appendingPathComponent("TestPackage")
        try fm.createDirectory(at: pkgDir, withIntermediateDirectories: true)

        let xsbFile = pkgDir.appendingPathComponent("xsb_aircraft.txt")
        let xsbContent = """
        OBJ8_AIRCRAFT AFR_CRJ2
        ICAO CRJ2
        OBJ8 AIRCRAFT YES TestPackage/CRJ2.obj

        OBJ8_AIRCRAFT DLH_CRJ2
        ICAO CRJ2
        OBJ8 AIRCRAFT YES TestPackage/CRJ2.obj

        OBJ8_AIRCRAFT BAW_CRJ2
        ICAO CRJ2
        OBJ8 AIRCRAFT YES TestPackage/CRJ2.obj
        """
        try xsbContent.write(to: xsbFile, atomically: true, encoding: .utf8)

        let objFile = pkgDir.appendingPathComponent("CRJ2.obj")
        let objContent = """
        I
        800
        OBJ
        ANIM_begin
        ANIM_hide 0 0 libxplanemp/controls/landing_lites_on
        LIGHT_NAMED airplane_landing 1.0 2.0 3.0
        ANIM_end
        """
        try objContent.write(to: objFile, atomically: true, encoding: .utf8)

        var loggedMessages: [String] = []
        await CSLLightsUpdater.shared.processPackage(packageURL: pkgDir, flashingBeacons: true) { msg in
            loggedMessages.append(msg)
        }

        // Even though xsb_aircraft.txt has 3 entries referencing CRJ2.obj, it should only be converted once
        XCTAssertEqual(loggedMessages.count, 1)
        XCTAssertEqual(loggedMessages.first, "[XP12 Lights] Converted CRJ2.obj (CRJ2)")
        XCTAssertTrue(fm.fileExists(atPath: pkgDir.appendingPathComponent("CRJ2.bak").path))
    }
}


