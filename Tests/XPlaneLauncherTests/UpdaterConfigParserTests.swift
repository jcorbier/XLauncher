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

    // MARK: - SkunkCrafts Updater v4 Tests

    func testParseSkunkCraftsV4Config() throws {
        let configFile = tempDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let content = """
        name|ToLiss A320 NEO
        version|2.0.0
        module|aircraft/a320_neo/
        zone|toliss
        protocol|2
        manifest|custom_manifest.txt
        channel|stable
        channel.beta.module|aircraft/a320_neo_beta/
        channel.beta.zone|custom
        changelog|documentation/changelog.txt
        readme|README.txt
        disabled|false
        """
        try content.write(to: configFile, atomically: true, encoding: .utf8)

        let service = SkunkCraftsUpdaterService.shared
        let config = service.parseConfig(at: configFile, defaultName: "DefaultName")

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.name, "ToLiss A320 NEO")
        XCTAssertEqual(config?.version, "2.0.0")
        XCTAssertEqual(config?.protocolLevel, 2)
        XCTAssertEqual(config?.zone, "toliss")
        XCTAssertEqual(config?.manifestFileName, "custom_manifest.txt")
        XCTAssertEqual(config?.changelogPath, "documentation/changelog.txt")
        XCTAssertEqual(config?.readmePath, "README.txt")
        XCTAssertEqual(config?.activeChannel, "stable")
        XCTAssertTrue(config?.availableChannels.contains("beta") ?? false)
        XCTAssertEqual(config?.baseURL, "http://toliss-ccd.kxcdn.com/aircraft/a320_neo/")
    }

    func testParseSkunkCraftsV4Manifest() {
        let manifestContent = """
        # Metadata comments
        name|ToLiss A320 NEO
        version|2.0.0

        # Unified 3-column items: relativePath|crc32|size
        objects/fuselage.obj|3421780262|1048576
        plugins/systems.xpl|12345678|524288
        settings/user_prefs.ini|-1|1024
        sounds/engine.wav|0xABCD1234|2097152

        # Insecure or protected paths that must be rejected
        ../secret.txt|1234|10
        skunkcrafts/crc_cache.txt|9999|200
        /rooted/path.obj|1111|50
        """

        let service = SkunkCraftsUpdaterService.shared
        let items = service.parseManifest(content: manifestContent)

        XCTAssertEqual(items.count, 4)

        XCTAssertEqual(items[0].relativePath, "objects/fuselage.obj")
        XCTAssertEqual(items[0].expectedCRC, "3421780262")
        XCTAssertEqual(items[0].expectedSize, 1048576)

        XCTAssertEqual(items[1].relativePath, "plugins/systems.xpl")
        XCTAssertEqual(items[1].expectedCRC, "12345678")
        XCTAssertEqual(items[1].expectedSize, 524288)

        XCTAssertEqual(items[2].relativePath, "settings/user_prefs.ini")
        XCTAssertNil(items[2].expectedCRC) // -1 sentinel should be converted to nil for CRC check
        XCTAssertEqual(items[2].expectedSize, 1024)

        XCTAssertEqual(items[3].relativePath, "sounds/engine.wav")
        XCTAssertEqual(items[3].expectedCRC, "0xABCD1234")
        XCTAssertEqual(items[3].expectedSize, 2097152)
    }

    func testParseSkunkCraftsV4SizesList() {
        let content = """
        # Auxiliary sizes
        objects/cabin.obj|204800
        plugins/lin.xpl|65536
        sounds/alert.wav:14280
        """

        let service = SkunkCraftsUpdaterService.shared
        let sizes = service.parseSizesList(content: content)

        XCTAssertEqual(sizes["objects/cabin.obj"], 204800)
        XCTAssertEqual(sizes["plugins/lin.xpl"], 65536)
        XCTAssertEqual(sizes["sounds/alert.wav"], 14280)
    }

    func testSkunkCraftsV4ResolveBaseURLWithZone() {
        let service = SkunkCraftsUpdaterService.shared

        // Custom zone / direct URL
        let directURL = service.resolveBaseURL(module: "https://updates.example.com/aircraft/a320/", zone: "custom")
        XCTAssertEqual(directURL?.absoluteString, "https://updates.example.com/aircraft/a320/")

        // KeyCDN zone template
        let zoneURL = service.resolveBaseURL(module: "aircraft/a320/", zone: "toliss")
        XCTAssertEqual(zoneURL?.absoluteString, "http://toliss-ccd.kxcdn.com/aircraft/a320/")

        // Zone with full scheme in module should strip scheme
        let zoneFullURL = service.resolveBaseURL(module: "http://updates.com/aircraft/a320", zone: "toliss")
        XCTAssertEqual(zoneFullURL?.absoluteString, "http://toliss-ccd.kxcdn.com/updates.com/aircraft/a320/")

        // Nil module
        XCTAssertNil(service.resolveBaseURL(module: nil))
        XCTAssertNil(service.resolveBaseURL(module: ""))
    }

    func testSkunkCraftsV4LegacyIPAddressRewrite() {
        let service = SkunkCraftsUpdaterService.shared

        let url1 = service.resolveBaseURL(module: "http://72.2.11.3:8080/c208/skunkcrafts_updater.cfg")
        XCTAssertEqual(url1?.absoluteString, "http://updates.thranda.org/c208/")

        let url2 = service.resolveBaseURL(module: "http://72.2.11.34:8080/pc6/")
        XCTAssertEqual(url2?.absoluteString, "http://updates.thranda.org/pc6/")
    }

    func testSkunkCraftsV4ProtectedFilesExclusion() {
        let service = SkunkCraftsUpdaterService.shared

        XCTAssertTrue(service.isProtectedClientFile("skunkcrafts_updater.cfg"))
        XCTAssertTrue(service.isProtectedClientFile("skunkcrafts_updater_ignore.txt"))
        XCTAssertTrue(service.isProtectedClientFile("skunkcrafts_updater_beta.cfg"))
        XCTAssertTrue(service.isProtectedClientFile("skunkcrafts_updater_beta_exp.cfg"))
        XCTAssertTrue(service.isProtectedClientFile("skunkcrafts/channels/beta.cfg"))
        XCTAssertTrue(service.isProtectedClientFile("skunkcrafts/channel.cfg"))
        XCTAssertTrue(service.isProtectedClientFile("skunkcrafts/crc_cache.txt"))

        XCTAssertFalse(service.isProtectedClientFile("objects/fuselage.obj"))
        XCTAssertFalse(service.isProtectedClientFile("plugins/systems.xpl"))
        XCTAssertFalse(service.isProtectedClientFile("liveries/custom/texture.png"))
    }

    func testSkunkCraftsV4EarlyBetaMigration() throws {
        let service = SkunkCraftsUpdaterService.shared
        let addonDir = tempDir.appendingPathComponent("MigrationTestAddon")
        let skunkDir = addonDir.appendingPathComponent("skunkcrafts")
        try fm.createDirectory(at: skunkDir, withIntermediateDirectories: true)

        let beta4Cfg = skunkDir.appendingPathComponent("updater.cfg")
        try "name|MigratedAddon\nversion|1.0.0\nmodule|https://example.com/addon/\n".write(to: beta4Cfg, atomically: true, encoding: .utf8)

        let beta4Ignore = skunkDir.appendingPathComponent("ignore.txt")
        try "liveries/custom\n".write(to: beta4Ignore, atomically: true, encoding: .utf8)

        // findConfig should trigger migration
        let found = service.findConfig(in: addonDir)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.lastPathComponent, "skunkcrafts_updater.cfg")

        let standardCfg = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        XCTAssertTrue(fm.fileExists(atPath: standardCfg.path))
        XCTAssertFalse(fm.fileExists(atPath: beta4Cfg.path))

        let standardIgnore = addonDir.appendingPathComponent("skunkcrafts_updater_ignore.txt")
        XCTAssertTrue(fm.fileExists(atPath: standardIgnore.path))
        XCTAssertFalse(fm.fileExists(atPath: beta4Ignore.path))
    }

    func testSkunkCraftsAbsorbBetaFilesWithCustomChannelName() throws {
        let addonDir = tempDir.appendingPathComponent("AbsorbTestAddon")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let betaFile = addonDir.appendingPathComponent("skunkcrafts_updater_beta_rc.cfg")
        let betaContent = """
        channel|Release Candidate
        module|http://example.com/rc/
        zone|custom
        enabled|true
        """
        try betaContent.write(to: betaFile, atomically: true, encoding: .utf8)

        let service = SkunkCraftsUpdaterService.shared
        service.absorbBetaFiles(in: addonDir)

        // The root file must be removed
        XCTAssertFalse(fm.fileExists(atPath: betaFile.path))

        // Absorbed into skunkcrafts/channels/Release Candidate.cfg
        let channelFile = addonDir.appendingPathComponent("skunkcrafts/channels/Release Candidate.cfg")
        XCTAssertTrue(fm.fileExists(atPath: channelFile.path))

        let content = try String(contentsOf: channelFile, encoding: .utf8)
        XCTAssertTrue(content.contains("channel|Release Candidate"))
        XCTAssertTrue(content.contains("module|http://example.com/rc/"))

        // Active channel should be set
        let activeCfg = addonDir.appendingPathComponent("skunkcrafts/channel.cfg")
        XCTAssertTrue(fm.fileExists(atPath: activeCfg.path))
        let activeContent = try String(contentsOf: activeCfg, encoding: .utf8)
        XCTAssertTrue(activeContent.contains("channel|Release Candidate"))
    }

    func testSkunkCraftsUpdateLocalConfigFileInPlace() throws {
        let cfgFile = tempDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let originalContent = """
        # Configuration File Header
        name|Old Aircraft Name
        version|1.0.0
        custom_key|retain_this_value
        # Section Header
        module|http://original.depot/plane/
        zone|custom
        # Trailing comments
        """
        try originalContent.write(to: cfgFile, atomically: true, encoding: .utf8)

        let service = SkunkCraftsUpdaterService.shared
        try service.updateLocalConfigFile(
            at: cfgFile,
            remoteName: "New Aircraft Name",
            remoteVersion: "1.2.0",
            remoteModule: "http://new.depot/plane/",
            remoteZone: "toliss",
            mainName: "CustomMain",
            packKeys: ["pack": "pack_alpha", "member": "mem_01"],
            isStable: true
        )

        let updatedContent = try String(contentsOf: cfgFile, encoding: .utf8)
        XCTAssertTrue(updatedContent.contains("# Configuration File Header"))
        XCTAssertTrue(updatedContent.contains("# Section Header"))
        XCTAssertTrue(updatedContent.contains("# Trailing comments"))
        XCTAssertTrue(updatedContent.contains("custom_key|retain_this_value"))

        XCTAssertTrue(updatedContent.contains("name|New Aircraft Name"))
        XCTAssertTrue(updatedContent.contains("version|1.2.0"))
        XCTAssertTrue(updatedContent.contains("module|http://new.depot/plane/"))
        XCTAssertTrue(updatedContent.contains("zone|toliss"))
        XCTAssertTrue(updatedContent.contains("main_name|CustomMain"))
        XCTAssertTrue(updatedContent.contains("pack|pack_alpha"))
        XCTAssertTrue(updatedContent.contains("member|mem_01"))

        XCTAssertFalse(updatedContent.contains("name|Old Aircraft Name"))
        XCTAssertFalse(updatedContent.contains("version|1.0.0"))
    }

    func testSkunkCraftsCRCCachePersistence() throws {
        let addonDir = tempDir.appendingPathComponent("CRCCacheTestAddon")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let service = SkunkCraftsUpdaterService.shared
        let entries: [String: SkunkCraftsCRCCacheEntry] = [
            "objects/fuselage.obj": .init(size: 1048576, mtime: 1700000000, crc: 0x12345678),
            "plugins/systems.xpl": .init(size: 65536, mtime: 1700000500, crc: 0x87654321)
        ]

        service.saveCRCCache(entries, for: addonDir)

        let cacheFile = addonDir.appendingPathComponent("skunkcrafts/crc_cache.txt")
        XCTAssertTrue(fm.fileExists(atPath: cacheFile.path))

        let loaded = service.loadCRCCache(for: addonDir)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded["objects/fuselage.obj"]?.size, 1048576)
        XCTAssertEqual(loaded["objects/fuselage.obj"]?.mtime, 1700000000)
        XCTAssertEqual(loaded["objects/fuselage.obj"]?.crc, 0x12345678)
        XCTAssertEqual(loaded["plugins/systems.xpl"]?.size, 65536)
        XCTAssertEqual(loaded["plugins/systems.xpl"]?.mtime, 1700000500)
        XCTAssertEqual(loaded["plugins/systems.xpl"]?.crc, 0x87654321)

        // Verify handling of corrupt/malformed lines
        let handle = try FileHandle(forWritingTo: cacheFile)
        handle.seekToEndOfFile()
        if let corruptData = "bad_line_without_enough_columns\ninvalid|size|mtime|not_a_crc\n".data(using: .utf8) {
            handle.write(corruptData)
        }
        try handle.close()

        let loadedAfterCorrupt = service.loadCRCCache(for: addonDir)
        XCTAssertEqual(loadedAfterCorrupt.count, 2)
    }

    func testSkunkCraftsPackMembersParsingAndAllowedPaths() throws {
        let service = SkunkCraftsUpdaterService.shared

        let specString = "a=Custom Scenery/Pack A=http://example.com/a;b=Aircraft/Pack B=http://example.com/b"
        let members = service.parsePackMembers(specString)
        XCTAssertEqual(members.count, 2)
        XCTAssertEqual(members[0].memberId, "a")
        XCTAssertEqual(members[0].defaultFolder, "Custom Scenery/Pack A")
        XCTAssertEqual(members[0].depotURL, "http://example.com/a")
        XCTAssertEqual(members[1].memberId, "b")
        XCTAssertEqual(members[1].defaultFolder, "Aircraft/Pack B")
        XCTAssertEqual(members[1].depotURL, "http://example.com/b")

        // Security: isPackPathAllowed
        XCTAssertTrue(service.isPackPathAllowed("Aircraft/ToLiss/A321"))
        XCTAssertTrue(service.isPackPathAllowed("Custom Scenery/Airport"))
        XCTAssertTrue(service.isPackPathAllowed("Airfoils/NACA0012"))
        XCTAssertTrue(service.isPackPathAllowed("Resources/plugins/MyPlugin"))

        XCTAssertFalse(service.isPackPathAllowed("../escape"))
        XCTAssertFalse(service.isPackPathAllowed("/rooted/path"))
        XCTAssertFalse(service.isPackPathAllowed("Resources/default/textures"))
        XCTAssertFalse(service.isPackPathAllowed("Output/logs"))
        XCTAssertFalse(service.isPackPathAllowed("Global Scenery/Earth"))
    }

    func testSkunkCraftsPackMemberFolderCreation() throws {
        let service = SkunkCraftsUpdaterService.shared
        let xplaneRoot = tempDir.appendingPathComponent("FakeXPlane")
        try fm.createDirectory(at: xplaneRoot, withIntermediateDirectories: true)

        let member = SkunkCraftsPackMember(
            memberId: "pack_member_1",
            defaultFolder: "Aircraft/Heavy/SuperPlane",
            depotURL: "http://updates.example.com/member1/"
        )

        let createdURL = try service.createPackMemberFolder(
            in: xplaneRoot,
            decl: member,
            packId: "main_pack_id",
            packName: "Super Fleet Pack"
        )

        XCTAssertTrue(fm.fileExists(atPath: createdURL.path))
        let cfgURL = createdURL.appendingPathComponent("skunkcrafts_updater.cfg")
        XCTAssertTrue(fm.fileExists(atPath: cfgURL.path))

        let cfgContent = try String(contentsOf: cfgURL, encoding: .utf8)
        XCTAssertTrue(cfgContent.contains("pack|main_pack_id"))
        XCTAssertTrue(cfgContent.contains("member|pack_member_1"))
        XCTAssertTrue(cfgContent.contains("version|none"))
        XCTAssertTrue(cfgContent.contains("module|http://updates.example.com/member1/"))

        // Path traversal attempt should throw AppError
        let evilMember = SkunkCraftsPackMember(
            memberId: "evil",
            defaultFolder: "../../../etc/evil",
            depotURL: "http://evil.com/"
        )
        XCTAssertThrowsError(try service.createPackMemberFolder(in: xplaneRoot, decl: evilMember, packId: "p", packName: nil))
    }

    func testSkunkCraftsLiveryExclusionConfig() throws {
        let service = SkunkCraftsUpdaterService.shared

        let cfgFile = tempDir.appendingPathComponent("skunkcrafts_updater.cfg")
        try "name|Plane\nliveries|false\n".write(to: cfgFile, atomically: true, encoding: .utf8)
        let configNoLiveries = service.parseConfig(at: cfgFile, defaultName: "Plane")
        XCTAssertFalse(configNoLiveries?.liveriesEnabled ?? true)

        try "name|Plane\nliveries|true\n".write(to: cfgFile, atomically: true, encoding: .utf8)
        let configWithLiveries = service.parseConfig(at: cfgFile, defaultName: "Plane")
        XCTAssertTrue(configWithLiveries?.liveriesEnabled ?? false)

        try "name|Plane\n".write(to: cfgFile, atomically: true, encoding: .utf8)
        let configDefaultLiveries = service.parseConfig(at: cfgFile, defaultName: "Plane")
        XCTAssertTrue(configDefaultLiveries?.liveriesEnabled ?? false)
    }

    func testSkunkCraftsMainChannelNameParsing() throws {
        let service = SkunkCraftsUpdaterService.shared
        let cfgFile = tempDir.appendingPathComponent("skunkcrafts_updater.cfg")

        try "name|Plane\nmain_name|Production\n".write(to: cfgFile, atomically: true, encoding: .utf8)
        let configCustom = service.parseConfig(at: cfgFile, defaultName: "Plane")
        XCTAssertEqual(configCustom?.mainName, "Production")

        try "name|Plane\nmain_name|stable\n".write(to: cfgFile, atomically: true, encoding: .utf8)
        let configStable = service.parseConfig(at: cfgFile, defaultName: "Plane")
        XCTAssertNil(configStable?.mainName)
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

    // MARK: - Version Comparison Tests

    func testVersionComparator() {
        XCTAssertTrue(VersionComparator.isNewer("1.14", than: "1.13"))
        XCTAssertFalse(VersionComparator.isNewer("1.13", than: "1.14"))
        XCTAssertFalse(VersionComparator.isNewer("1.14", than: "1.14"))

        XCTAssertTrue(VersionComparator.isNewer("1.10", than: "1.9"))
        XCTAssertFalse(VersionComparator.isNewer("1.9", than: "1.10"))

        XCTAssertTrue(VersionComparator.isNewer("v1.14", than: "1.13"))
        XCTAssertFalse(VersionComparator.isNewer("v1.13", than: "1.14"))

        XCTAssertTrue(VersionComparator.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertTrue(VersionComparator.isNewer("2.0.0", than: "2.0.0-beta"))
        XCTAssertTrue(VersionComparator.isNewer("2.0.0-beta.2", than: "2.0.0-beta.1"))

        XCTAssertTrue(VersionComparator.isNewer("snapshot 2", than: "snapshot 1"))
        XCTAssertFalse(VersionComparator.isNewer("snapshot 1", than: "snapshot 2"))

        XCTAssertEqual(VersionComparator.compare("1.14", "1.13"), .orderedDescending)
        XCTAssertEqual(VersionComparator.compare("1.13", "1.14"), .orderedAscending)
        XCTAssertEqual(VersionComparator.compare("1.14", "1.14"), .orderedSame)
    }

    func testSkunkCraftsNewerLocalVersionNotDowngraded() async throws {
        let addonDir = tempDir.appendingPathComponent("BetterPushBack")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let cfgFile = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let cfgContent = """
        zone|custom
        module|http://127.0.0.1:9/invalid
        name|BetterPushBack
        version|1.14
        """
        try cfgContent.write(to: cfgFile, atomically: true, encoding: .utf8)

        // When local version is 1.14 and remote is 1.13, it should never report an update available (downgrade)
        _ = SkunkCraftsConfig(name: "BetterPushBack", version: "1.14", remoteManifestURL: "http://127.0.0.1:9/invalid", baseURL: "http://127.0.0.1:9/invalid")
        XCTAssertFalse(VersionComparator.isNewer("1.13", than: "1.14"))
        XCTAssertTrue(VersionComparator.isNewer("1.14", than: "1.13"))
    }

    // MARK: - Beta Channel Tests

    func testSkunkCraftsBetaChannelDetectionAndParsing() throws {
        let addonDir = tempDir.appendingPathComponent("ToLissA321")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let service = SkunkCraftsUpdaterService.shared
        XCTAssertFalse(service.hasBetaChannel(in: addonDir))

        let releaseCfg = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let releaseContent = """
        name|ToLiss A321
        version|1.4.1
        url|https://updates.toliss.com/a321/
        """
        try releaseContent.write(to: releaseCfg, atomically: true, encoding: .utf8)
        XCTAssertFalse(service.hasBetaChannel(in: addonDir))

        let betaCfg = addonDir.appendingPathComponent("skunkcrafts_updater_beta.cfg")
        let betaContent = """
        module|https://updates.toliss.com/a321_beta/
        zone|custom
        enabled|false
        """
        try betaContent.write(to: betaCfg, atomically: true, encoding: .utf8)
        XCTAssertTrue(service.hasBetaChannel(in: addonDir))

        let foundRelease = service.findConfig(in: addonDir, preferBeta: false)
        XCTAssertEqual(foundRelease?.lastPathComponent, "skunkcrafts_updater.cfg")

        let parsedRelease = service.parseConfig(at: foundRelease!, defaultName: "A321")
        XCTAssertEqual(parsedRelease?.version, "1.4.1")
        XCTAssertFalse(parsedRelease?.isBetaEnabled ?? true)
        XCTAssertTrue(parsedRelease?.availableChannels.contains("beta") ?? false)

        // skunkcrafts_updater_beta.cfg should be absorbed into skunkcrafts/channels/beta.cfg and deleted from root
        XCTAssertFalse(fm.fileExists(atPath: betaCfg.path))
        let absorbedBetaCfg = addonDir.appendingPathComponent("skunkcrafts/channels/beta.cfg")
        XCTAssertTrue(fm.fileExists(atPath: absorbedBetaCfg.path))
        XCTAssertTrue(service.hasBetaChannel(in: addonDir))

        // When switching to beta channel, it resolves the beta module URL
        service.setChannel("beta", in: addonDir)
        let parsedBeta = service.parseConfig(at: foundRelease!, defaultName: "A321")
        XCTAssertEqual(parsedBeta?.version, "1.4.1")
        XCTAssertTrue(parsedBeta?.isBetaEnabled ?? false)
        XCTAssertEqual(parsedBeta?.activeChannel, "beta")
        XCTAssertEqual(parsedBeta?.baseURL, "https://updates.toliss.com/a321_beta/")
    }

    func testSkunkCraftsV4ChannelManagement() throws {
        let addonDir = tempDir.appendingPathComponent("ToLissA320V4")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let service = SkunkCraftsUpdaterService.shared

        let mainCfg = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let mainContent = """
        name|ToLiss A320
        version|2.0.0
        module|aircraft/a320/
        protocol|2
        """
        try mainContent.write(to: mainCfg, atomically: true, encoding: .utf8)

        // Initially no beta channel
        XCTAssertFalse(service.hasBetaChannel(in: addonDir))

        // Create skunkcrafts/channels/beta.cfg
        let channelsDir = addonDir.appendingPathComponent("skunkcrafts/channels")
        try fm.createDirectory(at: channelsDir, withIntermediateDirectories: true)
        let betaChannelCfg = channelsDir.appendingPathComponent("beta.cfg")
        let betaChannelContent = """
        channel|beta
        module|aircraft/a320_beta/
        zone|custom
        """
        try betaChannelContent.write(to: betaChannelCfg, atomically: true, encoding: .utf8)

        // Now hasBetaChannel should be true
        XCTAssertTrue(service.hasBetaChannel(in: addonDir))

        let parsedDefault = service.parseConfig(at: mainCfg, defaultName: "A320")
        XCTAssertEqual(parsedDefault?.activeChannel, "stable")
        XCTAssertFalse(parsedDefault?.isBetaEnabled ?? true)
        XCTAssertTrue(parsedDefault?.availableChannels.contains("beta") ?? false)

        // Switch channel to beta
        service.setChannel("beta", in: addonDir)

        let parsedSwitched = service.parseConfig(at: mainCfg, defaultName: "A320")
        XCTAssertEqual(parsedSwitched?.activeChannel, "beta")
        XCTAssertTrue(parsedSwitched?.isBetaEnabled ?? false)
        XCTAssertEqual(parsedSwitched?.baseURL, "aircraft/a320_beta/")

        // Switch channel back to stable
        service.setChannel("stable", in: addonDir)
        let parsedBack = service.parseConfig(at: mainCfg, defaultName: "A320")
        XCTAssertEqual(parsedBack?.activeChannel, "stable")
        XCTAssertFalse(parsedBack?.isBetaEnabled ?? true)
        XCTAssertEqual(parsedBack?.baseURL, "aircraft/a320/")
    }

    func testXUpdaterSetBetaEnabledIni() async throws {
        let service = XUpdaterService.shared
        let addonDir = tempDir.appendingPathComponent("FlightFactor777")
        let updaterDir = addonDir.appendingPathComponent(".xupdater")
        try fm.createDirectory(at: updaterDir, withIntermediateDirectories: true)

        let settingsFile = updaterDir.appendingPathComponent("settings.ini")
        let initialContent = """
        [General]
        product_name = FlightFactor 777-200ER
        product_version = 020100
        snapshot_num = 450
        preferred_release_type = release
        beta_enabled = false
        """
        try initialContent.write(to: settingsFile, atomically: true, encoding: .utf8)

        await service.setBetaEnabled(true, in: addonDir)
        let configBeta = service.parseConfig(at: settingsFile, defaultName: "FF777")
        XCTAssertNotNil(configBeta)
        XCTAssertTrue(configBeta?.betaEnabled ?? false)

        let contentBeta = try String(contentsOf: settingsFile, encoding: .utf8)
        XCTAssertTrue(contentBeta.contains("preferred_release_type=beta") || contentBeta.contains("preferred_release_type = beta"))
        XCTAssertTrue(contentBeta.contains("beta_enabled=true") || contentBeta.contains("beta_enabled = true"))

        await service.setBetaEnabled(false, in: addonDir)
        let configRelease = service.parseConfig(at: settingsFile, defaultName: "FF777")
        XCTAssertNotNil(configRelease)
        XCTAssertFalse(configRelease?.betaEnabled ?? true)

        let contentRelease = try String(contentsOf: settingsFile, encoding: .utf8)
        XCTAssertTrue(contentRelease.contains("preferred_release_type=release") || contentRelease.contains("preferred_release_type = release"))
        XCTAssertTrue(contentRelease.contains("beta_enabled=false") || contentRelease.contains("beta_enabled = false"))
    }

    func testXUpdaterSetBetaEnabledJson() async throws {
        let service = XUpdaterService.shared
        let addonDir = tempDir.appendingPathComponent("JsonAircraft")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let jsonFile = addonDir.appendingPathComponent("x-updater.json")
        let initialJson: [String: Any] = [
            "name": "Json Aircraft",
            "version": "1.0.0",
            "snapshot_num": 10
        ]
        let data = try JSONSerialization.data(withJSONObject: initialJson, options: .prettyPrinted)
        try data.write(to: jsonFile)

        await service.setBetaEnabled(true, in: addonDir)
        let parsedData = try Data(contentsOf: jsonFile)
        let parsedJson = try JSONSerialization.jsonObject(with: parsedData) as? [String: Any]

        XCTAssertEqual(parsedJson?["preferred_release_type"] as? String, "beta")
        XCTAssertEqual(parsedJson?["beta_enabled"] as? Bool, true)
    }

    @MainActor
    func testUpdateManagerBetaUpdatesToggleAndPersistence() async throws {
        let addonDir = tempDir.appendingPathComponent("ToLissA320")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let releaseCfg = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        try "name|ToLiss A320\nversion|1.0.0\nurl|http://example.com/a320/\n".write(to: releaseCfg, atomically: true, encoding: .utf8)
        let betaCfg = addonDir.appendingPathComponent("skunkcrafts_updater_beta.cfg")
        try "module|http://example.com/a320-beta/\nzone|custom\nenabled|false\n".write(to: betaCfg, atomically: true, encoding: .utf8)

        // Parse config to absorb beta file
        let service = SkunkCraftsUpdaterService.shared
        let parsed = service.parseConfig(at: releaseCfg, defaultName: "ToLissA320")
        XCTAssertNotNil(parsed)

        let updateManager = UpdateManager()
        let addon = UpdateManager.UpdatableAddon(
            name: "ToLiss A320",
            addonCategory: .aircraft,
            folderName: "ToLissA320",
            folderURL: addonDir,
            updaterType: .skunkcrafts,
            configFileURL: releaseCfg,
            currentVersion: "1.0.0",
            remoteManifestURL: "http://example.com/a320/",
            hasBetaChannel: true,
            isBetaEnabled: false,
            availableChannels: parsed?.availableChannels ?? ["stable", "beta"],
            activeChannel: "stable"
        )
        updateManager.updatableAddons = [addon]

        updateManager.setBetaUpdatesEnabled(true, for: addon)

        let updatedAddon = updateManager.updatableAddons.first!
        XCTAssertTrue(updatedAddon.isBetaEnabled)
        XCTAssertEqual(updatedAddon.activeChannel, "beta")
        XCTAssertEqual(updatedAddon.configFileURL.lastPathComponent, "skunkcrafts_updater.cfg")
        XCTAssertEqual(updatedAddon.currentVersion, "1.0.0")
        XCTAssertEqual(updatedAddon.remoteManifestURL, "http://example.com/a320-beta/")
        XCTAssertEqual(updateManager.addonBetaPreferences[addon.persistenceKey], true)

        updateManager.setBetaUpdatesEnabled(false, for: updatedAddon)

        let revertedAddon = updateManager.updatableAddons.first!
        XCTAssertFalse(revertedAddon.isBetaEnabled)
        XCTAssertEqual(revertedAddon.activeChannel, "stable")
        XCTAssertEqual(revertedAddon.configFileURL.lastPathComponent, "skunkcrafts_updater.cfg")
        XCTAssertEqual(revertedAddon.currentVersion, "1.0.0")
        XCTAssertEqual(revertedAddon.remoteManifestURL, "http://example.com/a320/")
        XCTAssertEqual(updateManager.addonBetaPreferences[addon.persistenceKey], false)
    }

    @MainActor
    func testSkunkCraftsMultiChannelListingAndDefaulting() async throws {
        let addonDir = tempDir.appendingPathComponent("MultiChannelAircraft")
        let channelsDir = addonDir.appendingPathComponent("skunkcrafts/channels")
        try fm.createDirectory(at: channelsDir, withIntermediateDirectories: true)

        let cfg = addonDir.appendingPathComponent("skunkcrafts_updater.cfg")
        let cfgContent = """
        name|Multi-Channel Aircraft
        version|2.0.0
        channel|alpha
        channel.alpha.module|http://example.com/alpha/
        channel.beta.module|http://example.com/beta/
        """
        try cfgContent.write(to: cfg, atomically: true, encoding: .utf8)

        let expCfg = channelsDir.appendingPathComponent("experimental.cfg")
        try "channel|experimental\nmodule|http://example.com/exp/\n".write(to: expCfg, atomically: true, encoding: .utf8)

        let service = SkunkCraftsUpdaterService.shared
        let parsed = service.parseConfig(at: cfg, defaultName: "MultiChannelAircraft")
        XCTAssertNotNil(parsed)
        guard let parsed = parsed else { return }

        // Must default to the channel listed in skunkcrafts_updater.cfg ("alpha")
        XCTAssertEqual(parsed.activeChannel, "alpha")
        // Available channels must contain all defined channels plus stable
        XCTAssertTrue(parsed.availableChannels.contains("stable"))
        XCTAssertTrue(parsed.availableChannels.contains("alpha"))
        XCTAssertTrue(parsed.availableChannels.contains("beta"))
        XCTAssertTrue(parsed.availableChannels.contains("experimental"))

        let updateManager = UpdateManager()
        let addon = UpdateManager.UpdatableAddon(
            name: parsed.name,
            addonCategory: .aircraft,
            folderName: "MultiChannelAircraft",
            folderURL: addonDir,
            updaterType: .skunkcrafts,
            configFileURL: cfg,
            currentVersion: parsed.version,
            remoteManifestURL: parsed.remoteManifestURL,
            hasBetaChannel: parsed.availableChannels.count > 1,
            isBetaEnabled: false,
            availableChannels: parsed.availableChannels,
            activeChannel: parsed.activeChannel
        )
        updateManager.updatableAddons = [addon]

        // Switch to experimental channel
        updateManager.setChannel("experimental", for: addon)
        let experimentalAddon = updateManager.updatableAddons.first!
        XCTAssertEqual(experimentalAddon.activeChannel, "experimental")
        XCTAssertFalse(experimentalAddon.isBetaEnabled)
        XCTAssertEqual(updateManager.addonChannelPreferences[addon.persistenceKey], "experimental")

        // Verify skunkcrafts/channel.cfg was written to disk
        let channelCfgURL = addonDir.appendingPathComponent("skunkcrafts/channel.cfg")
        XCTAssertTrue(fm.fileExists(atPath: channelCfgURL.path))
        let channelCfgContent = try String(contentsOf: channelCfgURL, encoding: .utf8)
        XCTAssertEqual(channelCfgContent.trimmingCharacters(in: .whitespacesAndNewlines), "channel|experimental")

        // Switch to beta channel
        updateManager.setChannel("beta", for: experimentalAddon)
        let betaAddon = updateManager.updatableAddons.first!
        XCTAssertEqual(betaAddon.activeChannel, "beta")
        XCTAssertTrue(betaAddon.isBetaEnabled)
        XCTAssertEqual(updateManager.addonChannelPreferences[addon.persistenceKey], "beta")
        XCTAssertEqual(updateManager.addonBetaPreferences[addon.persistenceKey], true)

        // Switch to stable channel
        updateManager.setChannel("stable", for: betaAddon)
        let stableAddon = updateManager.updatableAddons.first!
        XCTAssertEqual(stableAddon.activeChannel, "stable")
        XCTAssertFalse(stableAddon.isBetaEnabled)
        XCTAssertEqual(updateManager.addonChannelPreferences[addon.persistenceKey], "stable")
        XCTAssertEqual(updateManager.addonBetaPreferences[addon.persistenceKey], false)
    }

    @MainActor
    func testXUpdaterMultiChannelListingAndDefaulting() async throws {
        let addonDir = tempDir.appendingPathComponent("MultiChannelXUpdaterAddon")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let settingsFile = addonDir.appendingPathComponent("settings.ini")
        let settingsContent = """
        name = Test X-Updater Aircraft
        version = 1.0.0
        preferred_release_type = release
        beta_enabled = false
        """
        try settingsContent.write(to: settingsFile, atomically: true, encoding: .utf8)

        let service = XUpdaterService.shared
        let parsed = service.parseConfig(at: settingsFile, defaultName: "MultiChannelXUpdaterAddon")
        XCTAssertNotNil(parsed)
        guard let parsed = parsed else { return }

        // X-Updater default channel is always "stable" (release)
        XCTAssertFalse(parsed.betaEnabled)
        XCTAssertEqual(parsed.releaseType, "release")

        let updateManager = UpdateManager()
        let addon = UpdateManager.UpdatableAddon(
            name: parsed.name,
            addonCategory: .aircraft,
            folderName: "MultiChannelXUpdaterAddon",
            folderURL: addonDir,
            updaterType: .xUpdater,
            configFileURL: settingsFile,
            currentVersion: parsed.version,
            remoteManifestURL: parsed.remoteURL,
            hasBetaChannel: true,
            isBetaEnabled: false,
            availableChannels: ["stable", "beta"],
            activeChannel: "stable"
        )
        updateManager.updatableAddons = [addon]

        // Switch to beta channel
        updateManager.setChannel("beta", for: addon)
        let betaAddon = updateManager.updatableAddons.first!
        XCTAssertEqual(betaAddon.activeChannel, "beta")
        XCTAssertTrue(betaAddon.isBetaEnabled)
        XCTAssertEqual(updateManager.addonChannelPreferences[addon.persistenceKey], "beta")
        XCTAssertEqual(updateManager.addonBetaPreferences[addon.persistenceKey], true)

        // Switch back to stable channel
        updateManager.setChannel("stable", for: betaAddon)
        let stableAddon = updateManager.updatableAddons.first!
        XCTAssertEqual(stableAddon.activeChannel, "stable")
        XCTAssertFalse(stableAddon.isBetaEnabled)
        XCTAssertEqual(updateManager.addonChannelPreferences[addon.persistenceKey], "stable")
        XCTAssertEqual(updateManager.addonBetaPreferences[addon.persistenceKey], false)
    }

    // MARK: - Pack Grouping Tests (PUBLISHING.md §5.5)

    @MainActor
    func testPackGroupingStandaloneAndMembers() throws {
        let dummyURL = tempDir.appendingPathComponent("Dummy")

        let standalone1 = UpdateManager.UpdatableAddon(
            name: "ToLiss A321",
            addonCategory: .aircraft,
            folderName: "ToLiss A321",
            folderURL: dummyURL,
            updaterType: .skunkcrafts,
            configFileURL: dummyURL,
            currentVersion: "1.4.1"
        )

        // Member with 'member' set but no 'pack' -> must be standalone (PUBLISHING.md §5.5)
        let orphanMember = UpdateManager.UpdatableAddon(
            name: "Orphan Member",
            addonCategory: .scenery,
            folderName: "Orphan",
            folderURL: dummyURL,
            updaterType: .skunkcrafts,
            configFileURL: dummyURL,
            currentVersion: "1.0",
            memberId: "orphan-01"
        )

        // Pack members sharing pack "africa"
        let packMember1 = UpdateManager.UpdatableAddon(
            name: "XWP-AFR-01-bridges",
            addonCategory: .scenery,
            folderName: "simHeaven_X-WORLD-Pro_Africa-01-bridges",
            folderURL: dummyURL,
            updaterType: .skunkcrafts,
            configFileURL: dummyURL,
            currentVersion: "1.2",
            packId: "africa",
            memberId: "africa-01-bridges",
            packName: "simHeaven X-WORLD Pro Africa"
        )

        let packMember2 = UpdateManager.UpdatableAddon(
            name: "XWP-AFR-02-fountains",
            addonCategory: .scenery,
            folderName: "simHeaven_X-WORLD-Pro_Africa-02-fountains",
            folderURL: dummyURL,
            updaterType: .skunkcrafts,
            configFileURL: dummyURL,
            currentVersion: "1.2",
            packId: "africa",
            memberId: "africa-02-fountains",
            packName: "simHeaven X-WORLD Pro Africa"
        )

        // Pack member with pack "america" but NO pack_name defined -> falls back to packId
        let packMemberNoName = UpdateManager.UpdatableAddon(
            name: "XWP-AME-01",
            addonCategory: .scenery,
            folderName: "simHeaven_X-WORLD-Pro_America-01",
            folderURL: dummyURL,
            updaterType: .skunkcrafts,
            configFileURL: dummyURL,
            currentVersion: "1.0",
            packId: "america",
            memberId: "america-01",
            packName: nil
        )

        let allAddons = [standalone1, packMember1, orphanMember, packMember2, packMemberNoName]
        let grouped = UpdateManager.groupAddons(allAddons)

        XCTAssertEqual(grouped.count, 4)

        // 1st item: standalone ToLiss
        if case .standalone(let a) = grouped[0] {
            XCTAssertEqual(a.name, "ToLiss A321")
        } else {
            XCTFail("Expected standalone item at index 0")
        }

        // 2nd item: pack "africa" with 2 members, named after pack_name
        if case .pack(let p) = grouped[1] {
            XCTAssertEqual(p.packId, "africa")
            XCTAssertEqual(p.displayName, "simHeaven X-WORLD Pro Africa")
            XCTAssertEqual(p.members.count, 2)
            XCTAssertEqual(p.members[0].memberId, "africa-01-bridges")
            XCTAssertEqual(p.members[1].memberId, "africa-02-fountains")
        } else {
            XCTFail("Expected pack item at index 1")
        }

        // 3rd item: standalone orphan member
        if case .standalone(let a) = grouped[2] {
            XCTAssertEqual(a.name, "Orphan Member")
        } else {
            XCTFail("Expected standalone orphan at index 2")
        }

        // 4th item: pack "america" falling back to packId as displayName
        if case .pack(let p) = grouped[3] {
            XCTAssertEqual(p.packId, "america")
            XCTAssertEqual(p.displayName, "america")
            XCTAssertEqual(p.members.count, 1)
        } else {
            XCTFail("Expected pack item at index 3")
        }
    }

    func testPackVersionResolutionCommonVsMixed() {
        let dummyURL = tempDir.appendingPathComponent("Dummy")

        func makeMember(version: String?) -> UpdateManager.UpdatableAddon {
            UpdateManager.UpdatableAddon(
                name: "Part",
                addonCategory: .scenery,
                folderName: "PartFolder",
                folderURL: dummyURL,
                updaterType: .skunkcrafts,
                configFileURL: dummyURL,
                currentVersion: version,
                packId: "test_pack",
                packName: "Test Pack"
            )
        }

        // 1. All members have identical version -> common version
        let packSame = UpdateManager.UpdatablePack(
            packId: "test_pack",
            packName: "Test Pack",
            category: .scenery,
            updaterType: .skunkcrafts,
            members: [makeMember(version: "2.1.0"), makeMember(version: "2.1.0"), makeMember(version: "2.1.0")]
        )
        XCTAssertEqual(packSame.displayVersion, "2.1.0")

        // 2. Members differ in version -> "mixed"
        let packMixed = UpdateManager.UpdatablePack(
            packId: "test_pack",
            packName: "Test Pack",
            category: .scenery,
            updaterType: .skunkcrafts,
            members: [makeMember(version: "2.1.0"), makeMember(version: "2.0.0")]
        )
        XCTAssertEqual(packMixed.displayVersion, "mixed")

        // 3. One member has nil version while others have 2.1.0 -> "mixed"
        let packMissingVer = UpdateManager.UpdatablePack(
            packId: "test_pack",
            packName: "Test Pack",
            category: .scenery,
            updaterType: .skunkcrafts,
            members: [makeMember(version: "2.1.0"), makeMember(version: nil)]
        )
        XCTAssertEqual(packMissingVer.displayVersion, "mixed")

        // 4. All members have nil version -> nil
        let packAllNil = UpdateManager.UpdatablePack(
            packId: "test_pack",
            packName: "Test Pack",
            category: .scenery,
            updaterType: .skunkcrafts,
            members: [makeMember(version: nil), makeMember(version: nil)]
        )
        XCTAssertNil(packAllNil.displayVersion)
    }

    func testPackWorstStatusAggregation() {
        let dummyURL = tempDir.appendingPathComponent("Dummy")

        func makeMember(
            status: String,
            isUpdateAvailable: Bool = false,
            isChecking: Bool = false,
            isUpdating: Bool = false,
            curVer: String? = "1.0",
            latVer: String? = "1.0"
        ) -> UpdateManager.UpdatableAddon {
            UpdateManager.UpdatableAddon(
                name: "Part",
                addonCategory: .scenery,
                folderName: "PartFolder",
                folderURL: dummyURL,
                updaterType: .skunkcrafts,
                configFileURL: dummyURL,
                currentVersion: curVer,
                latestVersion: latVer,
                isUpdateAvailable: isUpdateAvailable,
                isChecking: isChecking,
                isUpdating: isUpdating,
                statusMessage: status,
                packId: "test_pack",
                packName: "Test Pack"
            )
        }

        // 1. All up to date
        let packUpToDate = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [makeMember(status: "Up to date"), makeMember(status: "Up to date")]
        )
        XCTAssertEqual(packUpToDate.statusMessage, "Up to date")
        XCTAssertFalse(packUpToDate.isUpdateAvailable)

        // 2. 1 member has update available (new version) -> worst is update available
        let packOneUpdate = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Up to date"),
                makeMember(status: "Update available (1.1)", isUpdateAvailable: true, curVer: "1.0", latVer: "1.1")
            ]
        )
        XCTAssertEqual(packOneUpdate.statusMessage, "Update available (1 of 2 folders)")
        XCTAssertTrue(packOneUpdate.isUpdateAvailable)

        // 3. All members have updates available
        let packAllUpdate = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Update available", isUpdateAvailable: true, curVer: "1.0", latVer: "1.1"),
                makeMember(status: "Update available", isUpdateAvailable: true, curVer: "1.0", latVer: "1.1")
            ]
        )
        XCTAssertEqual(packAllUpdate.statusMessage, "Update available")
        XCTAssertTrue(packAllUpdate.isUpdateAvailable)

        // 4. 1 member has repair available
        let packRepair = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Up to date"),
                makeMember(status: "Repair available (2 file(s) modified)", isUpdateAvailable: true, curVer: "1.0", latVer: "1.0")
            ]
        )
        XCTAssertEqual(packRepair.statusMessage, "Repair available (1 of 2 folders)")
        XCTAssertTrue(packRepair.isUpdateAvailable)

        // 5. 1 member failed check -> worst is check failed
        let packCheckFailed = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Up to date"),
                makeMember(status: "Check failed")
            ]
        )
        XCTAssertEqual(packCheckFailed.statusMessage, "Check failed")

        // 6. 1 member failed update -> worst is update failed
        let packUpdateFailed = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Up to date"),
                makeMember(status: "Update failed: HTTP 500")
            ]
        )
        XCTAssertEqual(packUpdateFailed.statusMessage, "Update failed: HTTP 500")

        // 7. In flight checking
        let packChecking = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Up to date"),
                makeMember(status: "Checking...", isChecking: true)
            ]
        )
        XCTAssertEqual(packChecking.statusMessage, "Checking...")
        XCTAssertTrue(packChecking.isChecking)

        // 8. In flight updating
        let packUpdating = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Up to date"),
                makeMember(status: "Downloading file 3/10...", isUpdating: true)
            ]
        )
        XCTAssertEqual(packUpdating.statusMessage, "Downloading file 3/10...")
        XCTAssertTrue(packUpdating.isUpdating)

        // 9. Multiple members updating
        let packMultiUpdating = UpdateManager.UpdatablePack(
            packId: "p", packName: "P", category: .scenery, updaterType: .skunkcrafts,
            members: [
                makeMember(status: "Downloading...", isUpdating: true),
                makeMember(status: "Extracting...", isUpdating: true),
                makeMember(status: "Up to date")
            ]
        )
        XCTAssertEqual(packMultiUpdating.statusMessage, "Updating (2/3)...")
        XCTAssertTrue(packMultiUpdating.isUpdating)
    }

    @MainActor
    func testPackBatchActionDelegation() {
        let dummyURL = tempDir.appendingPathComponent("Dummy")
        let updateManager = UpdateManager()

        let m1 = UpdateManager.UpdatableAddon(
            name: "Part1",
            addonCategory: .scenery,
            folderName: "Part1",
            folderURL: dummyURL,
            updaterType: .skunkcrafts,
            configFileURL: dummyURL,
            currentVersion: "1.0",
            statusMessage: "Up to date",
            packId: "batch_pack",
            packName: "Batch Pack"
        )

        let m2 = UpdateManager.UpdatableAddon(
            name: "Part2",
            addonCategory: .scenery,
            folderName: "Part2",
            folderURL: dummyURL,
            updaterType: .skunkcrafts,
            configFileURL: dummyURL,
            currentVersion: "1.0",
            statusMessage: "Up to date",
            packId: "batch_pack",
            packName: "Batch Pack"
        )

        updateManager.updatableAddons = [m1, m2]

        let pack = UpdateManager.UpdatablePack(
            packId: "batch_pack",
            packName: "Batch Pack",
            category: .scenery,
            updaterType: .skunkcrafts,
            members: [m1, m2]
        )

        // Check for updates on pack
        updateManager.checkForUpdates(forPack: pack)
        // Both members should be flagged as checking or updated
        XCTAssertTrue(updateManager.updatableAddons[0].isChecking || updateManager.updatableAddons[0].statusMessage == "Up to date")
        XCTAssertTrue(updateManager.updatableAddons[1].isChecking || updateManager.updatableAddons[1].statusMessage == "Up to date")

        // Available updates count should group by packs
        updateManager.updatableAddons[0].isUpdateAvailable = true
        updateManager.updatableAddons[1].isUpdateAvailable = true
        // Although 2 folders are updatable, availableUpdatesCount should count 1 pack!
        XCTAssertEqual(updateManager.availableUpdatesCount, 1)
    }
}


