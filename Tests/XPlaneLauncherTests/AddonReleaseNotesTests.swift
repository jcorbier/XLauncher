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

final class AddonReleaseNotesTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = fm.temporaryDirectory.appendingPathComponent("AddonReleaseNotesTests_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testChangelogPathDetection() {
        let validPaths = [
            "changelog.txt",
            "CHANGELOG.md",
            "ChangeLog.markdown",
            "release-notes.txt",
            "RELEASE-NOTES.MD",
            "release_notes.txt",
            "releasenotes.md",
            "changes.txt",
            "whatsnew.txt",
            "history.txt",
            "news.txt",
            "doc/changelog.txt",
            ".xupdater/release-notes.txt",
            "Documentation/changes.md"
        ]

        for path in validPaths {
            XCTAssertTrue(ChangelogFinder.isChangelogPath(path), "Expected '\(path)' to be recognized as a changelog")
        }

        let invalidPaths = [
            "airplane.obj",
            "fuselage.png",
            "cockpit.dds",
            "engine.wav",
            "plugin.xpl",
            "script.lua",
            "skunkcrafts_updater.cfg",
            "x-updater.json",
            "settings.ini",
            "archive.zip",
            "plugins/SASL/changelog.txt",
            "plugins/sasl/documentation/changelog.md",
            "plugins/xlua/changes.txt"
        ]

        for path in invalidPaths {
            XCTAssertFalse(ChangelogFinder.isChangelogPath(path), "Expected '\(path)' to NOT be recognized as a changelog")
        }
    }

    func testBestChangelogMatchRanking() {
        let paths1 = [
            "objects/fuselage.obj",
            "plugins/SASL/changelog.txt",
            "doc/changelog.txt",
            "CHANGELOG.md",
            "textures/fuselage.dds"
        ]
        let best1 = ChangelogFinder.bestChangelogMatch(in: paths1)
        XCTAssertEqual(best1, "CHANGELOG.md")

        let paths2 = [
            "plugins/xlua/changelog.txt",
            "doc/release_notes.txt",
            "sub/deep/folder/changelog.txt"
        ]
        let best2 = ChangelogFinder.bestChangelogMatch(in: paths2)
        XCTAssertEqual(best2, "doc/release_notes.txt")

        let paths3 = [
            "airfoil.dat",
            "sound.wav",
            "plugins/SASL/changelog.md"
        ]
        let best3 = ChangelogFinder.bestChangelogMatch(in: paths3)
        XCTAssertNil(best3)

        let paths4 = [
            "modules/xpdf/lin/CHANGES",
            "modules/xpdf/mac/CHANGES",
            "docs/changelog777.txt",
            "Custom Avionics/changelog.txt",
            "plugins/SASL/changelog.txt"
        ]
        let best4 = ChangelogFinder.bestChangelogMatch(in: paths4)
        XCTAssertEqual(best4, "docs/changelog777.txt")
    }

    func testFindLocalChangelog() throws {
        let addonDir = tempDir.appendingPathComponent("TestAircraft")
        let docDir = addonDir.appendingPathComponent("doc")
        try fm.createDirectory(at: docDir, withIntermediateDirectories: true)

        let changelogURL = docDir.appendingPathComponent("changelog.txt")
        try "Version 1.2.0\n- Initial release".write(to: changelogURL, atomically: true, encoding: .utf8)

        let found = ChangelogFinder.findLocalChangelog(in: addonDir)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.lastPathComponent, "changelog.txt")
    }

    func testSkunkCraftsLocalFallbackFetchReleaseNotes() async throws {
        let addonDir = tempDir.appendingPathComponent("SkunkAddon")
        try fm.createDirectory(at: addonDir, withIntermediateDirectories: true)

        let changelogURL = addonDir.appendingPathComponent("changelog.md")
        let expectedText = "# Version 2.0.0\n\n- Full rewrite"
        try expectedText.write(to: changelogURL, atomically: true, encoding: .utf8)

        let config = SkunkCraftsConfig(name: "SkunkAddon", version: "2.0.0", remoteManifestURL: nil, baseURL: nil)
        let notes = try await SkunkCraftsUpdaterService.shared.fetchReleaseNotes(for: addonDir, config: config)
        XCTAssertEqual(notes, expectedText)
    }

    func testXUpdaterLocalFallbackFetchReleaseNotes() async throws {
        let addonDir = tempDir.appendingPathComponent("XUpdaterAddon")
        let updaterDir = addonDir.appendingPathComponent(".xupdater")
        try fm.createDirectory(at: updaterDir, withIntermediateDirectories: true)

        let notesURL = updaterDir.appendingPathComponent("release-notes.txt")
        let expectedText = "FlightFactor 777 v2.5.0\n- Performance improvements"
        try expectedText.write(to: notesURL, atomically: true, encoding: .utf8)

        let config = XUpdaterConfig(name: "XUpdaterAddon", version: "2.5.0", remoteURL: nil)
        let notes = try await XUpdaterService.shared.fetchReleaseNotes(for: addonDir, config: config)
        XCTAssertEqual(notes, expectedText)
    }
}
