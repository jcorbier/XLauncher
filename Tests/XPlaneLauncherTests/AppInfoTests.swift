//
//  AppInfoTests.swift
//  XPlaneLauncherTests
//

import XCTest
@testable import XPlaneLauncher

final class AppInfoTests: XCTestCase {
    func testDocumentationURLForStableReleases() {
        XCTAssertEqual(
            AppInfo.documentationURL(for: "1.0.0").absoluteString,
            "https://xlauncher.readthedocs.io/en/v1.0.0/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "v0.7.0").absoluteString,
            "https://xlauncher.readthedocs.io/en/v0.7.0/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "0.6.3").absoluteString,
            "https://xlauncher.readthedocs.io/en/v0.6.3/"
        )
    }

    func testDocumentationURLForPrereleases() {
        XCTAssertEqual(
            AppInfo.documentationURL(for: "1.0.0-rc1").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "v1.0.0-rc.1").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "1.2.0-beta.1").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "v2.0.0-alpha").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
    }

    func testDocumentationURLForDevelopmentAndInvalid() {
        XCTAssertEqual(
            AppInfo.documentationURL(for: "").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "0.0.0").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "dev").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "1.0.0-dev").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
        XCTAssertEqual(
            AppInfo.documentationURL(for: "draft").absoluteString,
            "https://xlauncher.readthedocs.io/en/latest/"
        )
    }

    func testSemanticVersionIsPrerelease() {
        let stable = SemanticVersion(string: "1.0.0")
        XCTAssertEqual(stable?.isPrerelease, false)

        let rc = SemanticVersion(string: "1.0.0-rc1")
        XCTAssertEqual(rc?.isPrerelease, true)

        let beta = SemanticVersion(string: "v1.2.0-beta.2")
        XCTAssertEqual(beta?.isPrerelease, true)
    }
}
