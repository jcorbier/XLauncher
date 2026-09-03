//
//  DeviceFingerprint.swift
//  XPlaneLauncher
//
//  Hardware fingerprinting for node-locked licensing.
//

import Foundation
import IOKit
import CryptoKit

public struct DeviceFingerprint: Sendable {
    /// Retrieve the stable hardware UUID of this Mac via IOKit (`IOPlatformExpertDevice`).
    public static func getMachineUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let uuidAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }

        let trimmed = uuidAsCFString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Generates a deterministic SHA256 hashed machine fingerprint with application salt.
    public static func getHashedFingerprint(salt: String = "XLauncherProSalt") -> String {
        let rawUUID = getMachineUUID() ?? fallbackIdentifier()
        let combined = "\(rawUUID):\(salt)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    /// User-friendly computer name for display on the licensing dashboard (e.g. "Jean's MacBook Pro").
    public static func getMachineName() -> String {
        if let hostName = Host.current().localizedName, !hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Mac"
    }

    /// Fallback machine identifier if IOKit access fails (e.g. sandboxed test environment).
    private static func fallbackIdentifier() -> String {
        let key = "com.xlauncher.device.fallbackUUID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: key)
        return newUUID
    }
}
