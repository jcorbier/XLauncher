//
//  LicenseManagerTests.swift
//  XPlaneLauncherTests
//
//  Unit tests for XLauncher Pro node-locked licensing, hardware fingerprinting,
//  secure storage, and state management.
//

import XCTest
@testable import XPlaneLauncher

final class LicenseManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Ensure clean, isolated test environment that never touches production licenses
        LicenseStorage.fileName = "license_test.json"
        LicenseStorage.deleteLicense()
    }

    override func tearDown() {
        LicenseStorage.deleteLicense()
        LicenseStorage.fileName = "license.json"
        super.tearDown()
    }

    // MARK: - Device Fingerprint Tests

    func testDeviceFingerprintDeterministic() {
        let fp1 = DeviceFingerprint.getHashedFingerprint()
        let fp2 = DeviceFingerprint.getHashedFingerprint()

        XCTAssertFalse(fp1.isEmpty, "Fingerprint must not be empty")
        XCTAssertEqual(fp1, fp2, "Fingerprint should be deterministic across calls")
        XCTAssertEqual(fp1.count, 64, "SHA-256 hex string should be 64 characters")
    }

    func testDeviceFingerprintSaltDifferentiates() {
        let fp1 = DeviceFingerprint.getHashedFingerprint(salt: "SaltA")
        let fp2 = DeviceFingerprint.getHashedFingerprint(salt: "SaltB")

        XCTAssertNotEqual(fp1, fp2, "Different salts must produce distinct fingerprints")
    }

    func testMachineNameNotEmpty() {
        let name = DeviceFingerprint.getMachineName()
        XCTAssertFalse(name.isEmpty, "Machine name should not be empty")
    }

    // MARK: - License Record & Masking Tests

    func testLicenseRecordMaskedKey() {
        let record = LicenseRecord(
            licenseKey: "PRO-ABCD-EFGH-IJKL-MNOP",
            licenseId: "lic-12345",
            machineFingerprint: "fingerprint-123",
            machineName: "Test Mac"
        )

        XCTAssertEqual(record.maskedKey, "PRO-••••-••••-MNOP")
    }

    func testLicenseRecordShortKeyMasking() {
        let record = LicenseRecord(
            licenseKey: "1234567890",
            machineFingerprint: "fp",
            machineName: "Mac"
        )
        XCTAssertEqual(record.maskedKey, "1234-••••-7890")
    }

    func testLicenseRecordJSONCodable() throws {
        let original = LicenseRecord(
            licenseKey: "PRO-1111-2222-3333-4444",
            licenseId: "lic-99999",
            machineFingerprint: "hash-fingerprint",
            machineName: "My MacBook",
            activatedAt: Date(),
            productId: "xlauncher",
            status: "active"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LicenseRecord.self, from: encoded)

        XCTAssertEqual(decoded.licenseKey, original.licenseKey)
        XCTAssertEqual(decoded.licenseId, original.licenseId)
        XCTAssertEqual(decoded.machineFingerprint, original.machineFingerprint)
        XCTAssertEqual(decoded.machineName, original.machineName)
        XCTAssertEqual(decoded.productId, original.productId)
        XCTAssertEqual(decoded.status, original.status)
    }

    // MARK: - Persistence Tests

    func testLicenseStorageSaveAndLoad() {
        let record = LicenseRecord(
            licenseKey: "PRO-AAAA-BBBB-CCCC-DDDD",
            licenseId: "lic-test",
            machineFingerprint: DeviceFingerprint.getHashedFingerprint(),
            machineName: "Test Machine"
        )

        let saved = LicenseStorage.saveLicense(record)
        XCTAssertTrue(saved, "Saving license to storage must succeed")

        let loaded = LicenseStorage.loadLicense()
        XCTAssertNotNil(loaded, "Loading license from storage must return a record")
        XCTAssertEqual(loaded?.licenseKey, "PRO-AAAA-BBBB-CCCC-DDDD")
        XCTAssertEqual(loaded?.machineFingerprint, DeviceFingerprint.getHashedFingerprint())

        LicenseStorage.deleteLicense()
        let afterDelete = LicenseStorage.loadLicense()
        XCTAssertNil(afterDelete, "Loading after delete must return nil")
    }

    // MARK: - LicenseManager Initialization & State Tests

    @MainActor
    func testLicenseManagerInitializesUnlicensed() {
        let manager = LicenseManager()
        manager.initialize(skipNetwork: true)

        XCTAssertFalse(manager.isPro, "Manager should be unlicensed when no persistent record exists")
        XCTAssertNil(manager.licenseRecord)
    }

    @MainActor
    func testLicenseManagerRestoresValidLicense() {
        let currentFP = DeviceFingerprint.getHashedFingerprint()
        let record = LicenseRecord(
            licenseKey: "PRO-TEST-VALID-KEY",
            licenseId: "lic-valid",
            machineFingerprint: currentFP,
            machineName: "Valid Mac"
        )
        LicenseStorage.saveLicense(record)

        let manager = LicenseManager()
        manager.initialize(skipNetwork: true)

        XCTAssertTrue(manager.isPro, "Manager should restore Pro when matching fingerprint exists")
        XCTAssertEqual(manager.licenseRecord?.licenseKey, "PRO-TEST-VALID-KEY")
    }

    @MainActor
    func testLicenseManagerRejectsMismatchedFingerprint() {
        let foreignRecord = LicenseRecord(
            licenseKey: "PRO-FOREIGN-KEY",
            licenseId: "lic-foreign",
            machineFingerprint: "foreign-machine-uuid-hash",
            machineName: "Different Mac"
        )
        LicenseStorage.saveLicense(foreignRecord)

        let manager = LicenseManager()
        manager.initialize(skipNetwork: true)

        XCTAssertFalse(manager.isPro, "Manager must reject license from a different machine")
        XCTAssertNil(manager.licenseRecord)
    }

    @MainActor
    func testLicenseManagerDeactivateWipesState() async throws {
        let currentFP = DeviceFingerprint.getHashedFingerprint()
        let record = LicenseRecord(
            licenseKey: "PRO-TO-DEACTIVATE",
            licenseId: "lic-deact",
            machineFingerprint: currentFP,
            machineName: "Mac"
        )
        LicenseStorage.saveLicense(record)

        let manager = LicenseManager()
        manager.initialize(skipNetwork: true)
        XCTAssertTrue(manager.isPro)

        try await manager.deactivateLicense()
        XCTAssertFalse(manager.isPro)
        XCTAssertNil(manager.licenseRecord)
        XCTAssertNil(LicenseStorage.loadLicense())
    }

    // MARK: - Product Tier Model Tests

    func testProductTierFormatting() {
        let tier = ProductTierInfo(
            id: "xlauncher",
            name: "XLauncher Pro",
            description: "Lifetime License",
            priceCents: 500,
            currency: "eur",
            maxMachines: 3
        )

        XCTAssertTrue(tier.formattedPrice.contains("5"), "Formatted price should display 5")
        XCTAssertEqual(tier.maxMachines, 3)
    }

    // MARK: - Offline Resilience Tests

    @MainActor
    func testOfflineResilienceLeavesLicenseIntactOnNetworkError() async {
        let currentFP = DeviceFingerprint.getHashedFingerprint()
        let record = LicenseRecord(
            licenseKey: "PRO-OFFLINE-TEST",
            licenseId: "lic-offline",
            machineFingerprint: currentFP,
            machineName: "Mac"
        )
        LicenseStorage.saveLicense(record)

        // Point to an unreachable port to simulate completely offline environment
        let manager = LicenseManager(proxyBaseURL: URL(string: "http://127.0.0.1:59999")!)
        manager.initialize(skipNetwork: true)
        XCTAssertTrue(manager.isPro, "Must start active offline")

        await manager.validateOnline()
        XCTAssertTrue(manager.isPro, "Must remain active when offline/network failure occurs")
        XCTAssertNotNil(LicenseStorage.loadLicense())
    }
}
