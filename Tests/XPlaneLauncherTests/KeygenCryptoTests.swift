//
//  KeygenCryptoTests.swift
//  XPlaneLauncherTests
//
//  Unit tests for native Ed25519 cryptographic license verification,
//  Keygen signed keys, license file certificates, and tamper resistance.
//

import XCTest
import CryptoKit
@testable import XPlaneLauncher

final class KeygenCryptoTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LicenseStorage.fileName = "license_test.json"
        LicenseStorage.deleteLicense()
    }

    override func tearDown() {
        LicenseStorage.deleteLicense()
        LicenseStorage.fileName = "license.json"
        super.tearDown()
    }

    // MARK: - Hex & Key Conversion Tests

    func testHexToDataConversion() {
        let hex = "9e5e772db02b01a5fb823d8bab781056f794a4c9a0681f180d2b2be4efa4d254"
        let data = KeygenCrypto.hexToData(hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 32)

        // Invalid length
        XCTAssertNil(KeygenCrypto.hexToData("1234"))
        // Invalid hex characters
        XCTAssertNil(KeygenCrypto.hexToData(String(repeating: "z", count: 64)))
    }

    func testLoadEmbeddedPublicKey() {
        let cyberpatateKey = KeygenCrypto.loadPublicKey(hex: KeygenCrypto.cyberpatatePublicKeyHex)
        XCTAssertNotNil(cyberpatateKey, "CyberPatate public key must be valid Ed25519 key")
        XCTAssertEqual(cyberpatateKey?.rawRepresentation.count, 32)

        let legacyKey = KeygenCrypto.loadPublicKey(hex: KeygenCrypto.legacyKeygenPublicKeyHex)
        XCTAssertNotNil(legacyKey, "Legacy Keygen public key must be valid Ed25519 key")
        XCTAssertEqual(legacyKey?.rawRepresentation.count, 32)

        let defaultKey = KeygenCrypto.loadPublicKey()
        XCTAssertNotNil(defaultKey, "Default public key must load successfully")
        XCTAssertEqual(defaultKey?.rawRepresentation.count, 32)
    }

    // MARK: - Base64URL Tests

    func testBase64URLRoundTrip() {
        let sampleData = "XLauncher Pro 2.0 Testing with URL-safe chars +/==?".data(using: .utf8)!
        let encoded = KeygenCrypto.base64URLEncode(sampleData)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))

        let decoded = KeygenCrypto.base64URLDecode(encoded)
        XCTAssertEqual(decoded, sampleData)
    }

    // MARK: - Signed License Key Tests

    func testVerifySignedKeySuccess() throws {
        // Generate ephemeral key pair
        let privateKey = Curve25519.Signing.PrivateKey()
        let pubKeyHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()

        let payloadJSON = """
        {"id":"lic_pro_test_123","created":"2026-09-01T00:00:00Z","expiry":null}
        """
        let payloadData = payloadJSON.data(using: .utf8)!
        let encodedPayload = KeygenCrypto.base64URLEncode(payloadData)
        let signingDataString = "key/\(encodedPayload)"

        let signature = try privateKey.signature(for: Data(signingDataString.utf8))
        let encodedSig = KeygenCrypto.base64URLEncode(signature)

        let signedKey = "key/\(encodedPayload).\(encodedSig)"

        let result = KeygenCrypto.verifySignedKey(signedKey, publicKeyHex: pubKeyHex)
        XCTAssertTrue(result.isValid, "Valid signature must verify successfully")
        XCTAssertEqual(result.licenseId, "lic_pro_test_123")
        XCTAssertNil(result.errorMessage)
    }

    func testVerifySignedKeyTamperedPayloadFails() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pubKeyHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()

        let payload = "{\"id\":\"original_id\"}"
        let encodedPayload = KeygenCrypto.base64URLEncode(payload.data(using: .utf8)!)
        let signingDataString = "key/\(encodedPayload)"

        let signature = try privateKey.signature(for: Data(signingDataString.utf8))
        let encodedSig = KeygenCrypto.base64URLEncode(signature)

        // Alter payload
        let tamperedPayload = "{\"id\":\"hacked_pro_id\"}"
        let encodedTampered = KeygenCrypto.base64URLEncode(tamperedPayload.data(using: .utf8)!)
        let tamperedKey = "key/\(encodedTampered).\(encodedSig)"

        let result = KeygenCrypto.verifySignedKey(tamperedKey, publicKeyHex: pubKeyHex)
        XCTAssertFalse(result.isValid, "Tampered payload must fail cryptographic verification")
    }

    func testVerifySignedKeyTamperedSignatureFails() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pubKeyHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()

        let payload = "{\"id\":\"lic_123\"}"
        let encodedPayload = KeygenCrypto.base64URLEncode(payload.data(using: .utf8)!)
        let signingDataString = "key/\(encodedPayload)"

        var signature = try privateKey.signature(for: Data(signingDataString.utf8))
        // Mutate signature byte
        signature[0] ^= 0xFF
        let encodedCorruptedSig = KeygenCrypto.base64URLEncode(signature)

        let invalidKey = "key/\(encodedPayload).\(encodedCorruptedSig)"
        let result = KeygenCrypto.verifySignedKey(invalidKey, publicKeyHex: pubKeyHex)
        XCTAssertFalse(result.isValid, "Corrupted signature must fail verification")
    }

    func testVerifySignedKeyExpiredFails() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pubKeyHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()

        let payload = """
        {"id":"lic_expired","expiry":"2020-01-01T00:00:00Z"}
        """
        let encodedPayload = KeygenCrypto.base64URLEncode(payload.data(using: .utf8)!)
        let signingDataString = "key/\(encodedPayload)"

        let signature = try privateKey.signature(for: Data(signingDataString.utf8))
        let encodedSig = KeygenCrypto.base64URLEncode(signature)

        let expiredKey = "key/\(encodedPayload).\(encodedSig)"
        let result = KeygenCrypto.verifySignedKey(expiredKey, publicKeyHex: pubKeyHex)
        XCTAssertFalse(result.isValid, "Expired certificate must not pass verification")
        XCTAssertTrue(result.errorMessage?.contains("expired") == true)
    }

    // MARK: - License File (.lic) Certificate Tests

    func testVerifyLicenseFileSuccess() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pubKeyHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()

        let ciphertext = "fake_ciphertext_123"
        let signingPayload = "license/\(ciphertext)"

        let signature = try privateKey.signature(for: Data(signingPayload.utf8))
        let sigBase64 = signature.base64EncodedString()

        let envelope: [String: Any] = [
            "enc": ciphertext,
            "sig": sigBase64,
            "alg": "aes-256-gcm+ed25519"
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        let envelopeBase64 = envelopeData.base64EncodedString()

        let licFileContent = """
        -----BEGIN LICENSE FILE-----
        \(envelopeBase64)
        -----END LICENSE FILE-----
        """

        let result = KeygenCrypto.verifyLicenseFile(licFileContent, publicKeyHex: pubKeyHex)
        XCTAssertTrue(result.isValid, "License file with valid signature must succeed")
        XCTAssertEqual(result.payload, ciphertext)
    }

    // MARK: - LicenseManager Offline Tamper Detection

    @MainActor
    func testLicenseManagerRejectsForgedCryptoKeyOffline() {
        let manager = LicenseManager()

        // Create forged signed key with garbage signature
        let forgedKey = "key/eyJpZCI6ImZvcmdlZCJ9.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        let record = LicenseRecord(
            licenseKey: forgedKey,
            licenseId: "forged-id",
            machineFingerprint: DeviceFingerprint.getHashedFingerprint(),
            machineName: "Test Mac",
            status: "active"
        )

        LicenseStorage.saveLicense(record)

        // Run offline initialization
        manager.initialize(skipNetwork: true)

        XCTAssertFalse(manager.isPro, "Manager must reject forged cryptographic license")
        XCTAssertNil(manager.licenseRecord)
        XCTAssertNil(LicenseStorage.loadLicense(), "Forged license should be wiped from storage")
    }

    // MARK: - CyberPatate Native Licensing & Node Locking Tests

    func testVerifyCyberPatateSignedKeyWithMachineBindingSucceeds() throws {
        let cyberpatatePrivHex = "17226da897e61859d314a059c473d0415a0ea60e45fbb1dd59e4649647763334"
        let privData = KeygenCrypto.hexToData(cyberpatatePrivHex)!
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privData)

        let machineFP = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let payloadJSON = """
        {"account":{"id":"cyberpatate"},"product":{"id":"xlauncher"},"policy":{"id":"pro-lifetime"},"license":{"id":"lic_cb_123","created":"2026-10-08T12:00:00Z","expiry":null},"machine":{"id":"\(machineFP)"}}
        """
        let payloadBase64 = KeygenCrypto.base64URLEncode(payloadJSON.data(using: .utf8)!)
        let signingData = "key/\(payloadBase64)"
        let sig = try privateKey.signature(for: Data(signingData.utf8))
        let sigBase64 = KeygenCrypto.base64URLEncode(sig)
        let signedKey = "\(signingData).\(sigBase64)"

        // Verifying with default trusted keys (CyberPatate primary) and matching fingerprint
        let result = KeygenCrypto.verifySignedKey(signedKey, expectedFingerprint: machineFP)
        XCTAssertTrue(result.isValid, "Valid CyberPatate signed key matching machine must succeed")
        XCTAssertEqual(result.licenseId, "lic_cb_123")
        XCTAssertEqual(result.machineFingerprint, machineFP)
    }

    func testVerifyCyberPatateSignedKeyWithMismatchedMachineFails() throws {
        let cyberpatatePrivHex = "17226da897e61859d314a059c473d0415a0ea60e45fbb1dd59e4649647763334"
        let privData = KeygenCrypto.hexToData(cyberpatatePrivHex)!
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privData)

        let payloadJSON = """
        {"account":{"id":"cyberpatate"},"product":{"id":"xlauncher"},"license":{"id":"lic_cb_456"},"machine":{"id":"machine-mac-original"}}
        """
        let payloadBase64 = KeygenCrypto.base64URLEncode(payloadJSON.data(using: .utf8)!)
        let signingData = "key/\(payloadBase64)"
        let sig = try privateKey.signature(for: Data(signingData.utf8))
        let sigBase64 = KeygenCrypto.base64URLEncode(sig)
        let signedKey = "\(signingData).\(sigBase64)"

        // Verifying with DIFFERENT expected machine
        let result = KeygenCrypto.verifySignedKey(signedKey, expectedFingerprint: "machine-mac-pirate")
        XCTAssertFalse(result.isValid, "Mismatched machine fingerprint must fail cryptographic validation")
        XCTAssertTrue(result.errorMessage?.contains("bound to another machine") == true)
    }

    func testVerifyLegacyKeygenKeyStillSucceedsWithMultiKeyTrust() {
        let genuineKeygenKey = "key/eyJhY2NvdW50Ijp7ImlkIjoiMDVlZjlhNDQtZDYwNi00MzBlLWEyN2QtMWRhYjQ2NjI2NmE5In0sInByb2R1Y3QiOnsiaWQiOiI4NmZkMmI5ZS0zMjIzLTQ0MzgtODMwOC1mZDA3NDM0NTJmNzAifSwicG9saWN5Ijp7ImlkIjoiY2Y3YTk1MDQtYTE3OC00ZWZhLTlkMWEtMzE5OWYwYjNjMjYwIiwiZHVyYXRpb24iOm51bGx9LCJ1c2VyIjpudWxsLCJsaWNlbnNlIjp7ImlkIjoiNDNkODU0YzktMmFlNi00YWQwLTk1ZjYtNzg2MjNmNTcxZTlmIiwiY3JlYXRlZCI6IjIwMjYtMDktMDNUMTU6NTQ6NTMuMDAzWiIsImV4cGlyeSI6bnVsbH19.ou0CM1WEQiwT4cxNeSK84jzvTlKmfPwtaxnhHNtwgraQXZsfPPVQOpgZUXcvrp6IknGAp5i-YonKtO2PIiX0Ag=="

        // Verifying with default trusted keys (must fallback and match legacy Keygen key)
        let result = KeygenCrypto.verifySignedKey(genuineKeygenKey)
        XCTAssertTrue(result.isValid, "Legacy Keygen key must be validated via multi-key fallback")
        XCTAssertEqual(result.licenseId, "43d854c9-2ae6-4ad0-95f6-78623f571e9f")
    }

    @MainActor
    func testLicenseManagerRejectsTamperedMachineFingerprintOffline() throws {
        let cyberpatatePrivHex = "17226da897e61859d314a059c473d0415a0ea60e45fbb1dd59e4649647763334"
        let privData = KeygenCrypto.hexToData(cyberpatatePrivHex)!
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privData)

        // License was generated and signed for "original-mac-fp"
        let payloadJSON = """
        {"account":{"id":"cyberpatate"},"product":{"id":"xlauncher"},"license":{"id":"lic_anti_tamper"},"machine":{"id":"original-mac-fp"}}
        """
        let payloadBase64 = KeygenCrypto.base64URLEncode(payloadJSON.data(using: .utf8)!)
        let signingData = "key/\(payloadBase64)"
        let sig = try privateKey.signature(for: Data(signingData.utf8))
        let sigBase64 = KeygenCrypto.base64URLEncode(sig)
        let signedKey = "\(signingData).\(sigBase64)"

        // Rogue user attempts to alter cached.machineFingerprint in license.json to match local fingerprint
        let localFP = DeviceFingerprint.getHashedFingerprint()
        let tamperedRecord = LicenseRecord(
            licenseKey: signedKey,
            licenseId: "lic_anti_tamper",
            machineFingerprint: localFP, // Changed in license.json
            machineName: "My Mac",
            status: "active"
        )
        LicenseStorage.saveLicense(tamperedRecord)

        let manager = LicenseManager()
        manager.initialize(skipNetwork: true)

        // Offline verification detects signed payload bound to "original-mac-fp" != localFP
        XCTAssertFalse(manager.isPro, "Manager must reject license when cached fingerprint does not match payload")
        XCTAssertNil(manager.licenseRecord)
        XCTAssertNil(LicenseStorage.loadLicense(), "Tampered license must be removed")
    }
}
