//
//  LicenseModels.swift
//  XPlaneLauncher
//
//  Data structures for node-locked XLauncher Pro licensing.
//

import Foundation

/// Stored certificate representing an activated node-locked license on this machine.
public struct LicenseRecord: Codable, Equatable, Sendable {
    public let licenseKey: String
    public let licenseId: String?
    public let machineFingerprint: String
    public let machineName: String
    public let activatedAt: Date
    public let productId: String
    public let status: String

    public init(
        licenseKey: String,
        licenseId: String? = nil,
        machineFingerprint: String,
        machineName: String,
        activatedAt: Date = Date(),
        productId: String = "xlauncher",
        status: String = "active"
    ) {
        self.licenseKey = licenseKey
        self.licenseId = licenseId
        self.machineFingerprint = machineFingerprint
        self.machineName = machineName
        self.activatedAt = activatedAt
        self.productId = productId
        self.status = status
    }

    /// Masked license key for secure UI presentation (e.g. `PRO-••••-••••-WXYZ` or `Ed25519 Certificate (••••5lAQ==)`).
    public var maskedKey: String {
        if licenseKey.hasPrefix("key/") {
            let suffix = licenseKey.suffix(6)
            return "Ed25519 Certificate (••••\(suffix))"
        }
        if licenseKey.contains("BEGIN LICENSE FILE") || licenseKey.contains("BEGIN MACHINE FILE") {
            return "Ed25519 License File (.lic)"
        }
        let parts = licenseKey.split(separator: "-")
        if parts.count >= 4 {
            let first = parts[0]
            let last = parts[parts.count - 1]
            return "\(first)-••••-••••-\(last)"
        } else if licenseKey.count > 8 {
            let prefix = licenseKey.prefix(4)
            let suffix = licenseKey.suffix(4)
            return "\(prefix)-••••-\(suffix)"
        }
        return "••••••••••••"
    }

    /// Whether this license record represents a trial license.
    public var isTrial: Bool {
        status == "trial" || expiryDate != nil
    }

    /// Expiry date parsed from the cryptographic license key payload, if any.
    public var expiryDate: Date? {
        KeygenCrypto.extractExpiryDate(from: licenseKey)
    }

    /// Remaining days before trial expiration (rounded up to nearest day), or nil if lifetime.
    public var daysRemaining: Int? {
        guard let expiry = expiryDate else { return nil }
        let remainingSeconds = expiry.timeIntervalSince(Date())
        guard remainingSeconds > 0 else { return 0 }
        return Int(ceil(remainingSeconds / 86400.0))
    }

    /// Whether this trial license has expired.
    public var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return Date() > expiry
    }
}

// MARK: - API Payloads

public struct StartTrialRequest: Codable, Sendable {
    public let machineId: String
    public let machineName: String

    public init(machineId: String, machineName: String) {
        self.machineId = machineId
        self.machineName = machineName
    }
}

public struct StartTrialResponse: Codable, Sendable {
    public let status: String
    public let licenseKey: String
    public let licenseId: String?
    public let expiresAt: String?

    public init(
        status: String = "active",
        licenseKey: String,
        licenseId: String? = nil,
        expiresAt: String? = nil
    ) {
        self.status = status
        self.licenseKey = licenseKey
        self.licenseId = licenseId
        self.expiresAt = expiresAt
    }
}

public struct CreateCheckoutRequest: Codable, Sendable {
    public let machineId: String
    public let machineName: String

    public init(machineId: String, machineName: String) {
        self.machineId = machineId
        self.machineName = machineName
    }
}

public struct CreateCheckoutResponse: Codable, Sendable {
    public let checkoutUrl: String
    public let sessionId: String
}

public struct SessionStatusResponse: Codable, Sendable {
    public let status: String
    public let productId: String?
    public let licenseKey: String?
    public let licenseId: String?
}

public struct ActivateLicenseRequest: Codable, Sendable {
    public let licenseKey: String
    public let machineId: String
    public let machineName: String?

    public init(licenseKey: String, machineId: String, machineName: String?) {
        self.licenseKey = licenseKey
        self.machineId = machineId
        self.machineName = machineName
    }
}

public struct DeactivateLicenseRequest: Codable, Sendable {
    public let licenseKey: String
    public let machineId: String

    public init(licenseKey: String, machineId: String) {
        self.licenseKey = licenseKey
        self.machineId = machineId
    }
}

public struct ValidateLicenseRequest: Codable, Sendable {
    public let licenseKey: String
    public let machineId: String

    public init(licenseKey: String, machineId: String) {
        self.licenseKey = licenseKey
        self.machineId = machineId
    }
}

public struct LicenseActionResponse: Codable, Sendable {
    public let status: String
    public let licenseKey: String?
    public let licenseId: String?
    public let valid: Bool?
    public let message: String?
}

public struct APIErrorResponse: Codable, Sendable {
    public let error: String
}

public struct ProductTierInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let priceCents: Int
    public let currency: String
    public let maxMachines: Int

    public var formattedPrice: String {
        let amount = Double(priceCents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}
