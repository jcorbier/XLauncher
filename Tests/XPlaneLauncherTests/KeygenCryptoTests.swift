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
        let pubKey = KeygenCrypto.loadPublicKey()
        XCTAssertNotNil(pubKey, "Embedded Keygen public key must be valid Ed25519 key")
        XCTAssertEqual(pubKey?.rawRepresentation.count, 32)
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
}
