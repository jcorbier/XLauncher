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

import Foundation
import XLauncherPluginKit

public final class HostPluginLogger: PluginLogger, Sendable {
    public let pluginId: String

    public init(pluginId: String) {
        self.pluginId = pluginId
    }

    public func log(_ message: String, level: PluginLogLevel) {
        let mappedLevel: LogLevel
        switch level {
        case .debug: mappedLevel = .debug
        case .info: mappedLevel = .info
        case .warning: mappedLevel = .warn
        case .error: mappedLevel = .error
        }
        let msg = "[\(pluginId)] \(message)"
        Task { @MainActor in
            ConsoleLogger.shared.log(msg, category: .system, level: mappedLevel)
        }
    }
}

public final class HostPluginLicenseVerifier: PluginLicenseVerifier, Sendable {
    public init() {}

    public func isFeatureUnlocked(featureId: String) async -> Bool {
        await MainActor.run {
            guard LicenseManager.shared.isPro else { return false }
            if let record = LicenseManager.shared.licenseRecord, record.status == "expired" || record.isExpired {
                return false
            }
            return true
        }
    }

    public func activeLicenseKey() async -> String? {
        await MainActor.run {
            guard LicenseManager.shared.isPro else { return nil }
            if let record = LicenseManager.shared.licenseRecord, record.status == "expired" || record.isExpired {
                return nil
            }
            if let cached = LicenseStorage.loadLicense(), cached.status == "expired" || cached.isExpired {
                return nil
            }
            return LicenseManager.shared.licenseRecord?.licenseKey ?? LicenseStorage.loadLicense()?.licenseKey
        }
    }

    public func machineFingerprint() async -> String {
        DeviceFingerprint.getHashedFingerprint()
    }
}

final class HostPluginProfileProvider: PluginProfileProvider, @unchecked Sendable {
    private weak var pluginManager: PluginManager?
    private weak var pluginRegistry: AppPluginRegistry?

    init(pluginManager: PluginManager, pluginRegistry: AppPluginRegistry) {
        self.pluginManager = pluginManager
        self.pluginRegistry = pluginRegistry
    }

    public func availableProfiles() async -> [PluginProfileSummary] {
        await MainActor.run {
            guard let pm = pluginManager else { return [] }
            return pm.profiles.map { profile in
                PluginProfileSummary(
                    id: profile.id,
                    name: profile.name,
                    aircraftCount: profile.aircraftFolderNames.count,
                    totalAddonsCount: profile.aircraftFolderNames.count +
                        profile.pluginFolderNames.count +
                        profile.sceneryFolderNames.count +
                        profile.luaScriptFolderNames.count
                )
            }
        }
    }

    public func activeProfileId() async -> UUID? {
        await MainActor.run {
            pluginManager?.selectedProfileId
        }
    }

    public func selectProfile(id: UUID?) async throws {
        await MainActor.run {
            guard let pm = pluginManager else { return }
            pm.selectedProfileId = id
        }

        let (url, activeNames, profName) = await MainActor.run {
            guard let pm = pluginManager else { return (nil as URL?, nil as [String]?, nil as String?) }
            let names = pm.aircraft.filter { $0.isEnabled }.map { $0.folderName }
            return (pm.xPlanePath, names, pm.selectedProfile?.name)
        }

        if let reg = await MainActor.run(body: { pluginRegistry }) {
            await reg.updatePluginContexts(
                xPlaneURL: url,
                activatedAircraftNames: activeNames,
                activeProfile: profName
            )
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .pluginActiveProfileDidChange, object: id)
        }
    }
}

