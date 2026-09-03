//
//  KeygenCrypto.swift
//  XPlaneLauncher
//
//  Native offline cryptographic license verification using Apple CryptoKit (Ed25519)
//  and the Keygen account public key.
//

import Foundation
import CryptoKit

public struct KeygenVerificationResult: Sendable {
    public let isValid: Bool
    public let payload: String?
    public let licenseId: String?
    public let expiryDate: Date?
    public let errorMessage: String?

    public init(
        isValid: Bool,
        payload: String? = nil,
        licenseId: String? = nil,
        expiryDate: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.isValid = isValid
        self.payload = payload
        self.licenseId = licenseId
        self.expiryDate = expiryDate
        self.errorMessage = errorMessage
    }

    public static func failure(_ message: String) -> KeygenVerificationResult {
        KeygenVerificationResult(isValid: false, errorMessage: message)
    }

    public static func success(payload: String? = nil, licenseId: String? = nil, expiryDate: Date? = nil) -> KeygenVerificationResult {
        KeygenVerificationResult(isValid: true, payload: payload, licenseId: licenseId, expiryDate: expiryDate)
    }
}

public enum KeygenCrypto {
    /// Default Keygen account Ed25519 public key (hexadecimal).
    public static let defaultPublicKeyHex = "9e5e772db02b01a5fb823d8bab781056f794a4c9a0681f180d2b2be4efa4d254"

    // MARK: - Key Conversion

    /// Converts a 64-character hex string into 32 raw bytes.
    public static func hexToData(_ hex: String) -> Data? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 64 else { return nil }

        var data = Data(capacity: 32)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteStr = cleaned[index..<nextIndex]
            guard let byte = UInt8(byteStr, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    /// Loads an Ed25519 public key from a 64-char hex string.
    public static func loadPublicKey(hex: String = defaultPublicKeyHex) -> Curve25519.Signing.PublicKey? {
        guard let data = hexToData(hex) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: data)
    }

    // MARK: - Base64URL Helpers (RFC 4648)

    public static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    public static func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    // MARK: - Verification

    /// Verifies a Keygen license key formatted as `key/{BASE64URL_DATA}.{BASE64URL_SIGNATURE}`.
    public static func verifySignedKey(
        _ key: String,
        publicKeyHex: String = defaultPublicKeyHex
    ) -> KeygenVerificationResult {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("key/") else {
            return .failure("Key does not have the required 'key/' prefix")
        }

        let parts = trimmed.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return .failure("Signed key format is invalid: expected key/{DATA}.{SIG}")
        }

        let signingDataString = String(parts[0]) // e.g. "key/eyJpZCI6..."
        let encodedSignature = String(parts[1])

        guard let signatureData = base64URLDecode(encodedSignature) else {
            return .failure("Signature is not valid Base64URL")
        }
        guard signatureData.count == 64 else {
            return .failure("Ed25519 signature must be exactly 64 bytes (got \(signatureData.count))")
        }

        guard let publicKey = loadPublicKey(hex: publicKeyHex) else {
            return .failure("Failed to initialize Ed25519 public key")
        }

        let signingBytes = Data(signingDataString.utf8)
        let isValid = publicKey.isValidSignature(signatureData, for: signingBytes)
        guard isValid else {
            return .failure("Cryptographic signature verification failed: invalid signature for key")
        }

        // Signature is verified! Now extract and parse the payload
        let dataPart = signingDataString.dropFirst(4) // drop "key/"
        var payloadString: String? = nil
        var extractedLicenseId: String? = nil
        var extractedExpiryDate: Date? = nil

        if let decodedData = base64URLDecode(String(dataPart)),
           let utf8 = String(data: decodedData, encoding: .utf8) {
            payloadString = utf8

            // Attempt to parse JSON dataset if present
            if let json = try? JSONSerialization.jsonObject(with: decodedData) as? [String: Any] {
                if let id = json["id"] as? String {
                    extractedLicenseId = id
                } else if let id = json["licenseId"] as? String {
                    extractedLicenseId = id
                }

                if let expiryString = json["expiry"] as? String ?? json["expiresAt"] as? String {
                    let isoFormatter = ISO8601DateFormatter()
                    if let date = isoFormatter.date(from: expiryString) {
                        extractedExpiryDate = date
                        if date < Date() {
                            return .failure("License certificate has expired on \(expiryString)")
                        }
                    }
                }
            }
        }

        return .success(
            payload: payloadString,
            licenseId: extractedLicenseId,
            expiryDate: extractedExpiryDate
        )
    }

    /// Verifies a Keygen license or machine file certificate (.lic).
    /// Supports `-----BEGIN LICENSE FILE-----` and `-----BEGIN MACHINE FILE-----` formats.
    public static func verifyLicenseFile(
        _ content: String,
        publicKeyHex: String = defaultPublicKeyHex
    ) -> KeygenVerificationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        let isMachineFile = trimmed.contains("BEGIN MACHINE FILE")
        let isLicenseFile = trimmed.contains("BEGIN LICENSE FILE")

        guard isMachineFile || isLicenseFile else {
            return .failure("File does not contain valid Keygen certificate headers")
        }

        let header = isMachineFile ? "-----BEGIN MACHINE FILE-----" : "-----BEGIN LICENSE FILE-----"
        let footer = isMachineFile ? "-----END MACHINE FILE-----" : "-----END LICENSE FILE-----"

        guard let startRange = trimmed.range(of: header),
              let endRange = trimmed.range(of: footer, range: startRange.upperBound..<trimmed.endIndex) else {
            return .failure("Malformed certificate: missing or mismatched header/footer")
        }

        let body = trimmed[startRange.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rawJSONData = Data(base64Encoded: body) ?? base64URLDecode(body) else {
            return .failure("Failed to Base64 decode certificate body")
        }

        guard let json = try? JSONSerialization.jsonObject(with: rawJSONData) as? [String: Any] else {
            return .failure("Certificate body is not valid JSON")
        }

        guard let sigString = json["sig"] as? String else {
            return .failure("Certificate is missing cryptographic signature ('sig')")
        }

        guard let signatureData = Data(base64Encoded: sigString) ?? base64URLDecode(sigString),
              signatureData.count == 64 else {
            return .failure("Certificate signature is invalid or not 64 bytes")
        }

        // Determine signing payload:
        // Keygen signs "license/{enc}" (or "machine/{enc}" or "license/{data}")
        let prefix = isMachineFile ? "machine/" : "license/"
        let payloadKey = json["enc"] as? String ?? json["data"] as? String
        guard let payloadValue = payloadKey else {
            return .failure("Certificate missing encrypted payload ('enc') or data ('data')")
        }

        let signingDataString = "\(prefix)\(payloadValue)"
        guard let publicKey = loadPublicKey(hex: publicKeyHex) else {
            return .failure("Failed to initialize Ed25519 public key")
        }

        let isValid = publicKey.isValidSignature(signatureData, for: Data(signingDataString.utf8))
        guard isValid else {
            return .failure("Cryptographic signature verification failed: certificate signature invalid")
        }

        return .success(payload: payloadValue)
    }

    /// Checks whether a given string is any form of cryptographically signed Keygen license or certificate.
    public static func isCryptographicLicense(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("key/") && trimmed.contains(".") {
            return true
        }
        if trimmed.contains("BEGIN LICENSE FILE") || trimmed.contains("BEGIN MACHINE FILE") {
            return true
        }
        return false
    }
}
