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
import SwiftUI
import XLauncherPluginKit
@testable import XPlaneLauncher

// MARK: - Mock Plugin for Testing

private final class MockWeatherPlugin: XLauncherPlugin, @unchecked Sendable {
    static let descriptor = PluginDescriptor(
        id: "com.test.weather",
        name: "Test Weather Plugin",
        version: "1.2.0"
    )

    var initialized = false
    var started = false
    var stopped = false
    var receivedContext: PluginContext?

    init() {}

    func initialize(context: PluginContext) async throws {
        self.initialized = true
        self.receivedContext = context
    }

    func start() async throws {
        self.started = true
    }

    func stop() async {
        self.stopped = true
    }

    var sidebarItems: [PluginSidebarItem] {
        [
            PluginSidebarItem(
                id: "com.test.weather.radar",
                title: "Live Radar",
                systemImage: "cloud.rain.fill",
                section: .tools,
                priority: 10,
                badgeText: { "LIVE" },
                viewBuilder: {
                    AnyView(Text("Mock Live Radar View"))
                }
            )
        ]
    }

    var settingsPanes: [PluginSettingsPane] {
        [
            PluginSettingsPane(
                id: "com.test.weather.settings",
                title: "Weather Radar Options",
                systemImage: "cloud.sun",
                priority: 20,
                viewBuilder: {
                    AnyView(Text("Mock Settings Content"))
                }
            )
        ]
    }

    var launchActionOverride: LaunchActionOverride? {
        LaunchActionOverride(
            title: "Start Flight With Weather",
            iconName: "cloud.fill",
            action: {}
        )
    }

    func capability<T>(_ capabilityType: T.Type) -> T? {
        if capabilityType == TelemetryProvider.self {
            return MockTelemetryProvider() as? T
        }
        return nil
    }
}

private final class MockTelemetryProvider: TelemetryProvider, @unchecked Sendable {
    func startTracking(host: String, port: Int) async throws {}
    func stopTracking() {}
    func currentSnapshot() -> FlightTelemetrySnapshot? {
        FlightTelemetrySnapshot(latitude: 47.5, longitude: -122.3)
    }
    func telemetryStream() -> AsyncStream<FlightTelemetrySnapshot> {
        AsyncStream { continuation in
            continuation.yield(FlightTelemetrySnapshot(latitude: 47.5, longitude: -122.3))
            continuation.finish()
        }
    }
}

// MARK: - Unit Tests

@MainActor
final class AppPluginRegistryTests: XCTestCase {

    func testRegisterPluginLifecycleAndContributions() async throws {
        let registry = AppPluginRegistry()
        let plugin = MockWeatherPlugin()

        try await registry.registerPlugin(plugin)

        XCTAssertTrue(plugin.initialized)
        XCTAssertTrue(plugin.started)
        XCTAssertEqual(registry.loadedPlugins.count, 1)

        // Verify sidebar items
        XCTAssertEqual(registry.sidebarItems.count, 1)
        let sidebarItem = registry.sidebarItems.first
        XCTAssertEqual(sidebarItem?.id, "com.test.weather.radar")
        XCTAssertEqual(sidebarItem?.title, "Live Radar")
        XCTAssertEqual(sidebarItem?.systemImage, "cloud.rain.fill")
        XCTAssertEqual(sidebarItem?.section, .tools)
        XCTAssertEqual(sidebarItem?.badgeText?(), "LIVE")

        // Verify settings panes
        XCTAssertEqual(registry.settingsPanes.count, 1)
        let settingsPane = registry.settingsPanes.first
        XCTAssertEqual(settingsPane?.id, "com.test.weather.settings")
        XCTAssertEqual(settingsPane?.title, "Weather Radar Options")

        // Verify launch override
        XCTAssertNotNil(registry.launchActionOverride)
        XCTAssertEqual(registry.launchActionOverride?.title, "Start Flight With Weather")
        XCTAssertEqual(registry.launchActionOverride?.iconName, "cloud.fill")

        // Verify capability interrogation
        let telemetry = registry.firstCapability(TelemetryProvider.self)
        XCTAssertNotNil(telemetry)
        XCTAssertEqual(telemetry?.currentSnapshot()?.latitude, 47.5)

        // Verify stopAll
        await registry.stopAll()
        XCTAssertTrue(plugin.stopped)
        XCTAssertEqual(registry.loadedPlugins.count, 0)
        XCTAssertEqual(registry.sidebarItems.count, 0)
        XCTAssertEqual(registry.settingsPanes.count, 0)
        XCTAssertNil(registry.launchActionOverride)
    }

    func testCandidateURLsResolution() {
        let registry = AppPluginRegistry()
        let urls = registry.resolveCandidateURLs()
        // Verify resolveCandidateURLs executes safely
        XCTAssertNotNil(urls)

        // Verify that custom/env candidate paths are properly discovered when present on disk
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("XLauncherTestPlugin_\(UUID().uuidString)")
        let mockBundle = tempDir.appendingPathComponent("MockCandidate.bundle")
        try? FileManager.default.createDirectory(at: mockBundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        setenv("XLAUNCHER_PLUGIN_PATH", mockBundle.path, 1)
        defer { unsetenv("XLAUNCHER_PLUGIN_PATH") }

        let resolvedWithEnv = registry.resolveCandidateURLs()
        XCTAssertTrue(resolvedWithEnv.contains(mockBundle.standardizedFileURL))
    }

    func testDiscoverAndLoadBundlePlugins() async throws {
        let registry = AppPluginRegistry()
        let bundleURL = URL(fileURLWithPath: "../XLauncherPro/build/XLauncherPro.bundle").standardizedFileURL
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            return
        }

        LicenseStorage.fileName = "test_empty_license_\(UUID().uuidString).json"
        defer {
            LicenseStorage.deleteLicense()
            LicenseStorage.fileName = "license.json"
        }

        // 1. Initially without license, plugin loads but MUST NOT contribute any views
        await registry.discoverAndLoadPlugins(customURLs: [bundleURL])
        XCTAssertGreaterThanOrEqual(registry.loadedPlugins.count, 1)

        let liveItemWithoutLicense = registry.sidebarItems.first(where: { $0.id == "com.jcorbier.XLauncherPro.live" })
        XCTAssertNil(liveItemWithoutLicense, "Pro plugin must not contribute sidebar views without an active license")
        XCTAssertTrue(registry.settingsPanes.filter({ $0.id == "com.jcorbier.XLauncherPro.settings" }).isEmpty)

        // 2. Simulate valid license authorization
        let genuineKey = "key/eyJhY2NvdW50Ijp7ImlkIjoiMDVlZjlhNDQtZDYwNi00MzBlLWEyN2QtMWRhYjQ2NjI2NmE5In0sInByb2R1Y3QiOnsiaWQiOiI4NmZkMmI5ZS0zMjIzLTQ0MzgtODMwOC1mZDA3NDM0NTJmNzAifSwicG9saWN5Ijp7ImlkIjoiY2Y3YTk1MDQtYTE3OC00ZWZhLTlkMWEtMzE5OWYwYjNjMjYwIiwiZHVyYXRpb24iOm51bGx9LCJ1c2VyIjpudWxsLCJsaWNlbnNlIjp7ImlkIjoiNDNkODU0YzktMmFlNi00YWQwLTk1ZjYtNzg2MjNmNTcxZTlmIiwiY3JlYXRlZCI6IjIwMjYtMDktMDNUMTU6NTQ6NTMuMDAzWiIsImV4cGlyeSI6bnVsbH19.ou0CM1WEQiwT4cxNeSK84jzvTlKmfPwtaxnhHNtwgraQXZsfPPVQOpgZUXcvrp6IknGAp5i-YonKtO2PIiX0Ag=="
        let fingerprint = "7980569c7054e9ffbb04258eaf5caa10286056ff5ad6a66f6ef0653eb5138991"

        struct TestVerifier: PluginLicenseVerifier {
            let key: String
            let fingerprint: String
            func isFeatureUnlocked(featureId: String) async -> Bool { true }
            func activeLicenseKey() async -> String? { key }
            func machineFingerprint() async -> String { fingerprint }
        }

        if let plugin = registry.loadedPlugins.first {
            let ctx = PluginContext(
                hostVersion: "1.0.0",
                xPlaneURL: nil,
                storageDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
                logger: HostPluginLogger(pluginId: type(of: plugin).descriptor.id),
                licenseVerifier: TestVerifier(key: genuineKey, fingerprint: fingerprint)
            )
            try await plugin.initialize(context: ctx)
            registry.refreshContributions()

            let mapItemWithLicense = registry.sidebarItems.first(where: { $0.id == "com.jcorbier.XLauncherPro.map" })
            XCTAssertNotNil(mapItemWithLicense, "Pro plugin must contribute sidebar views when license is valid")
            XCTAssertEqual(mapItemWithLicense?.title, "Map")
            XCTAssertEqual(mapItemWithLicense?.section, .flight)
            XCTAssertNotNil(mapItemWithLicense?.viewBuilder())

            let proSettings = registry.settingsPanes.first(where: { $0.id == "com.jcorbier.XLauncherPro.settings" })
            XCTAssertNotNil(proSettings, "Pro plugin must contribute settings pane when license is valid")
        }
    }
}
