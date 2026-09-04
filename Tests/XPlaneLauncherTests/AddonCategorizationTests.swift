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

final class AddonCategorizationTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CategorizationTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Aircraft Heuristics Tests

    func testAircraftClassificationHeuristics() {
        let service = AddonCategorizationService.shared

        // Airliners
        XCTAssertEqual(service.detectAircraftCategory(name: "Airbus A321 Neo", folderName: "ToLiss_A321", folderURL: nil), .airliner)
        XCTAssertEqual(service.detectAircraftCategory(name: "Boeing 737-800", folderName: "B738_Zibo", folderURL: nil), .airliner)
        XCTAssertEqual(service.detectAircraftCategory(name: "Embraer E195", folderName: "E195_XCrafts", folderURL: nil), .airliner)
        XCTAssertEqual(service.detectAircraftCategory(name: "Bombardier CRJ-900", folderName: "CRJ900", folderURL: nil), .airliner)

        // Helicopters
        XCTAssertEqual(service.detectAircraftCategory(name: "Bell 407", folderName: "Bell407_XP12", folderURL: nil), .helicopter)
        XCTAssertEqual(service.detectAircraftCategory(name: "Robinson R44 Raven II", folderName: "R44_Helicopter", folderURL: nil), .helicopter)
        XCTAssertEqual(service.detectAircraftCategory(name: "Eurocopter EC135", folderName: "EC135_v5", folderURL: nil), .helicopter)

        // Military
        XCTAssertEqual(service.detectAircraftCategory(name: "F-16C Fighting Falcon", folderName: "F16C", folderURL: nil), .military)
        XCTAssertEqual(service.detectAircraftCategory(name: "Eurofighter Typhoon", folderName: "Typhoon_Military", folderURL: nil), .military)
        XCTAssertEqual(service.detectAircraftCategory(name: "Lockheed C-130 Hercules", folderName: "C130_Hercules", folderURL: nil), .military)

        // General Aviation
        XCTAssertEqual(service.detectAircraftCategory(name: "Cessna 172SP Skyhawk", folderName: "Cessna_172SP", folderURL: nil), .generalAviation)
        XCTAssertEqual(service.detectAircraftCategory(name: "Piper PA-28 Archer", folderName: "PA28_Archer", folderURL: nil), .generalAviation)
        XCTAssertEqual(service.detectAircraftCategory(name: "Cirrus SR22 G6", folderName: "SR22_Entegra", folderURL: nil), .generalAviation)
    }

    // MARK: - Scenery Heuristics Tests

    func testSceneryClassificationHeuristics() throws {
        let service = AddonCategorizationService.shared

        // Airport by apt.dat
        let airportDir = tempDir.appendingPathComponent("Custom_Airport")
        let aptDir = airportDir.appendingPathComponent("Earth nav data")
        try FileManager.default.createDirectory(at: aptDir, withIntermediateDirectories: true)
        try "1100 Version".write(to: aptDir.appendingPathComponent("apt.dat"), atomically: true, encoding: .utf8)
        XCTAssertEqual(service.detectSceneryCategory(name: "Custom Airport", folderName: "Custom_Airport", folderURL: airportDir), .airport)

        // Airport by ICAO code
        XCTAssertEqual(service.detectSceneryCategory(name: "Paris CDG Airport", folderName: "LFPG_Paris_CDG", folderURL: nil), .airport)

        // Mesh / Ortho
        XCTAssertEqual(service.detectSceneryCategory(name: "Ortho Tile", folderName: "zOrtho4XP_+48+002", folderURL: nil), .meshOrtho)
        XCTAssertEqual(service.detectSceneryCategory(name: "SimHeaven X-World Europe", folderName: "simheaven_xworld_europe", folderURL: nil), .meshOrtho)

        // Library by library.txt
        let libDir = tempDir.appendingPathComponent("Custom_Lib")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        try "A\n800\nLIBRARY".write(to: libDir.appendingPathComponent("library.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(service.detectSceneryCategory(name: "Custom Lib", folderName: "Custom_Lib", folderURL: libDir), .library)

        // Landmarks
        XCTAssertEqual(service.detectSceneryCategory(name: "Paris VFR Landmarks", folderName: "Paris_Landmarks_VFR", folderURL: nil), .landmark)
    }

    // MARK: - Plugin Heuristics Tests

    func testPluginClassificationHeuristics() {
        let service = AddonCategorizationService.shared

        // Traffic
        XCTAssertEqual(service.detectPluginCategory(name: "xPilot", folderName: "xPilot"), .traffic)
        XCTAssertEqual(service.detectPluginCategory(name: "LiveTraffic", folderName: "LiveTraffic"), .traffic)

        // Weather
        XCTAssertEqual(service.detectPluginCategory(name: "ActiveSky XP", folderName: "ActiveSkyXP"), .weather)
        XCTAssertEqual(service.detectPluginCategory(name: "VisualXP Atmosphere", folderName: "VisualXP"), .weather)

        // Sound
        XCTAssertEqual(service.detectPluginCategory(name: "FMOD Sound Engine", folderName: "FMOD_Engine"), .sound)
        XCTAssertEqual(service.detectPluginCategory(name: "BSS Soundpack", folderName: "BSS_A320_Sound"), .sound)

        // Utilities
        XCTAssertEqual(service.detectPluginCategory(name: "BetterPushback", folderName: "BetterPushback"), .utilities)
        XCTAssertEqual(service.detectPluginCategory(name: "FlyWithLua", folderName: "FlyWithLua"), .utilities)
        XCTAssertEqual(service.detectPluginCategory(name: "Avitab", folderName: "avitab"), .utilities)
    }

    // MARK: - Custom Tags & Overrides Tests

    @MainActor
    func testCustomTagsAndCategoryOverrides() {
        let pm = PluginManager()
        let itemKey = "aircraft:TestCustomPlane"

        // Set custom category override & tags
        pm.setCustomCategory(AircraftCategory.military.rawValue, for: itemKey)
        pm.setTags(["Payware", "Favorite", "TopGun"], for: itemKey)

        let aircraft = PluginManager.Aircraft(
            name: "Test Custom Plane",
            isEnabled: true,
            folderName: "TestCustomPlane"
        )

        // Category should return user's custom override
        XCTAssertEqual(pm.category(for: aircraft), .military)

        // Tags should return user's tags
        let tags = pm.tags(for: itemKey)
        XCTAssertEqual(tags, ["Payware", "Favorite", "TopGun"])

        // Known tags should include these tags
        let known = pm.allKnownTags(for: "aircraft:")
        XCTAssertTrue(known.contains("Payware"))
        XCTAssertTrue(known.contains("Favorite"))
        XCTAssertTrue(known.contains("TopGun"))

        // Reset category back to auto
        pm.setCustomCategory(nil, for: itemKey)
        // With no keywords, it should fall back to generalAviation
        XCTAssertEqual(pm.category(for: aircraft), .generalAviation)
    }
}
