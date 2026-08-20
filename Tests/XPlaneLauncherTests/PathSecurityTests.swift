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

final class PathSecurityTests: XCTestCase {

    var tempSandboxDir: URL!

    override func setUp() {
        super.setUp()
        tempSandboxDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XLauncher_TestSandbox_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempSandboxDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempSandboxDir)
        super.tearDown()
    }

    // MARK: - Component Sanitization

    func testSanitizeValidPathComponents() throws {
        XCTAssertEqual(try PathSecurity.sanitizePathComponent("MyAddon"), "MyAddon")
        XCTAssertEqual(try PathSecurity.sanitizePathComponent("  Toliss-A321  "), "Toliss-A321")
        XCTAssertEqual(try PathSecurity.sanitizePathComponent("Custom_Scenery_1"), "Custom_Scenery_1")
    }

    func testSanitizeInvalidPathComponents() {
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent(""))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("   "))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("."))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent(".."))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("folder/subfolder"))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("folder\\subfolder"))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("../outside"))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("addon\0name"))
    }

    // MARK: - Subpath Validation & Containment

    func testValidateSubpathValid() throws {
        let validRelative = "subfolder/nested/file.txt"
        let resolved = try PathSecurity.validateSubpath(relativePath: validRelative, within: tempSandboxDir)
        XCTAssertTrue(PathSecurity.isStrictlyContained(url: resolved, within: tempSandboxDir))
        XCTAssertEqual(resolved.path, tempSandboxDir.appendingPathComponent("subfolder/nested/file.txt").path)
    }

    func testValidateSubpathRejectsTraversalAttempts() {
        let maliciousPaths = [
            "../secret.txt",
            "../../../../etc/passwd",
            "subfolder/../../secret.txt",
            "/absolute/path/file.txt",
            "~/.ssh/id_rsa",
            "foo/bar/../..",
            "..",
            "C:\\Windows\\System32",
            "subfolder/../../../outside.txt"
        ]

        for path in maliciousPaths {
            XCTAssertThrowsError(try PathSecurity.validateSubpath(relativePath: path, within: tempSandboxDir), "Should have rejected malicious path: \(path)")
        }
    }

    func testIsStrictlyContainedBoundaryCheck() {
        let root = URL(fileURLWithPath: "/Users/test/Sandbox")
        let legitimateChild = URL(fileURLWithPath: "/Users/test/Sandbox/Aircraft/B737")
        let similarPrefixEscape = URL(fileURLWithPath: "/Users/test/Sandbox_Evil/Aircraft")
        let rootItself = URL(fileURLWithPath: "/Users/test/Sandbox")
        let parentEscape = URL(fileURLWithPath: "/Users/test")

        XCTAssertTrue(PathSecurity.isStrictlyContained(url: rootItself, within: root))
        XCTAssertTrue(PathSecurity.isStrictlyContained(url: legitimateChild, within: root))
        XCTAssertFalse(PathSecurity.isStrictlyContained(url: similarPrefixEscape, within: root))
        XCTAssertFalse(PathSecurity.isStrictlyContained(url: parentEscape, within: root))
    }

    // MARK: - Symlink Location Validation

    func testValidateSymlinkLocation() throws {
        let validLink = tempSandboxDir.appendingPathComponent("ValidPlugin")
        XCTAssertNoThrow(try PathSecurity.validateSymlinkLocation(linkURL: validLink, within: tempSandboxDir))

        let invalidLinkEscape = tempSandboxDir.deletingLastPathComponent().appendingPathComponent("EscapeLink")
        XCTAssertThrowsError(try PathSecurity.validateSymlinkLocation(linkURL: invalidLinkEscape, within: tempSandboxDir))
    }

    // MARK: - Addon Installer & Updaters Scenarios

    func testAddonInstallerPackageValidation() {
        let cleanName = try? PathSecurity.sanitizePathComponent("My Aircraft (v1.0)")
        XCTAssertEqual(cleanName, "My Aircraft (v1.0)")

        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("../My Aircraft"))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("My/Aircraft"))
        XCTAssertThrowsError(try PathSecurity.sanitizePathComponent("My\\Aircraft"))
    }

    func testUpdaterManifestPathValidation() throws {
        let addonRoot = tempSandboxDir.appendingPathComponent("AddonFolder")
        try FileManager.default.createDirectory(at: addonRoot, withIntermediateDirectories: true)

        let legitimateFile = "plugins/mac_x64/plugin.xpl"
        let resolved = try PathSecurity.validateSubpath(relativePath: legitimateFile, within: addonRoot)
        XCTAssertTrue(PathSecurity.isStrictlyContained(url: resolved, within: addonRoot))

        let maliciousManifestEntry = "../../Library/LaunchAgents/malicious.plist"
        XCTAssertThrowsError(try PathSecurity.validateSubpath(relativePath: maliciousManifestEntry, within: addonRoot))
    }

    func testValidateSubpathAllowsExistingSymlinkLeaf() throws {
        // Create an external target directory
        let externalTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent("XLauncher_ExternalTarget_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: externalTarget, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalTarget) }

        // Create a symlink inside the sandbox pointing to the external target
        let linkURL = tempSandboxDir.appendingPathComponent("C172 NG DIGITAL")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalTarget)

        // Validating the subpath of this existing symlink within tempSandboxDir must succeed
        XCTAssertNoThrow(try PathSecurity.validateSubpath(relativePath: "C172 NG DIGITAL", within: tempSandboxDir))
    }
}
