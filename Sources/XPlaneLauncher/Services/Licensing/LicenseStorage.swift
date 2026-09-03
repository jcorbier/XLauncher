//
//  LicenseStorage.swift
//  XPlaneLauncher
//
//  Persistent storage for the active license certificate in Application Support.
//

import Foundation

public enum LicenseStorage {
    nonisolated(unsafe) public static var fileName = "license.json"

    /// Destination file URL for storing the active license in Application Support.
    public static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("XPlaneLauncher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    /// Saves the active LicenseRecord to Application Support.
    @discardableResult
    public static func saveLicense(_ record: LicenseRecord) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else {
            return false
        }

        do {
            try data.write(to: storageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Loads the active LicenseRecord from Application Support.
    public static func loadLicense() -> LicenseRecord? {
        guard let data = try? Data(contentsOf: storageURL),
              let record = try? JSONDecoder().decode(LicenseRecord.self, from: data) else {
            return nil
        }
        return record
    }

    /// Deletes the license record from Application Support.
    public static func deleteLicense() {
        try? FileManager.default.removeItem(at: storageURL)
    }
}
