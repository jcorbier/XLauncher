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
import SwiftUI
import AppKit

// MARK: - Semantic Version

public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let build: String?
    public let rawString: String

    public var description: String {
        rawString
    }

    public var isDevelopment: Bool {
        (major == 0 && minor == 0 && patch == 0) ||
        rawString.localizedCaseInsensitiveContains("draft") ||
        rawString.localizedCaseInsensitiveContains("dev")
    }

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.rawString = trimmed

        var working = trimmed
        if working.hasPrefix("v") || working.hasPrefix("V") {
            working.removeFirst()
        }

        // Separate build metadata (+build)
        let buildComponents = working.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        if buildComponents.count > 1 {
            self.build = String(buildComponents[1])
            working = String(buildComponents[0])
        } else {
            self.build = nil
        }

        // Separate pre-release (-alpha.1)
        let prereleaseComponents = working.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        if prereleaseComponents.count > 1 {
            self.prerelease = String(prereleaseComponents[1])
            working = String(prereleaseComponents[0])
        } else {
            self.prerelease = nil
        }

        // Parse major.minor.patch
        let versionNumbers = working.split(separator: ".")
        guard let major = versionNumbers.indices.contains(0) ? Int(versionNumbers[0]) : nil else {
            return nil
        }
        self.major = major
        self.minor = versionNumbers.indices.contains(1) ? (Int(versionNumbers[1]) ?? 0) : 0
        self.patch = versionNumbers.indices.contains(2) ? (Int(versionNumbers[2]) ?? 0) : 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // When major.minor.patch are equal:
        // A version without a pre-release is higher precedence than one with a pre-release
        // e.g. 1.0.0 > 1.0.0-beta
        switch (lhs.prerelease, rhs.prerelease) {
        case (.none, .none):
            return false
        case (.none, .some):
            return false // lhs has no prerelease, so lhs is greater
        case (.some, .none):
            return true  // lhs has prerelease, rhs does not, so lhs is less
        case (.some(let lPre), .some(let rPre)):
            return lPre.localizedStandardCompare(rPre) == .orderedAscending
        }
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major &&
        lhs.minor == rhs.minor &&
        lhs.patch == rhs.patch &&
        lhs.prerelease == rhs.prerelease
    }
}

// MARK: - GitHub Release Models

public struct AppReleaseAsset: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

public struct AppRelease: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let publishedAt: Date?
    public let isPrerelease: Bool
    public let isDraft: Bool
    public let assets: [AppReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case isPrerelease = "prerelease"
        case isDraft = "draft"
        case assets
    }

    public var displayTitle: String {
        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return tagName
    }

    public var semVer: SemanticVersion? {
        SemanticVersion(string: tagName)
    }

    public var dmgAsset: AppReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

// MARK: - App Update Manager

@MainActor
@Observable
final class AppUpdateManager {
    private let defaults = UserDefaults.standard

    private let autoCheckKey = "AppUpdateAutoCheckOnLaunch"
    private let includePrereleasesKey = "AppUpdateIncludePrereleases"
    private let lastCheckDateKey = "AppUpdateLastCheckDate"
    private let skippedVersionKey = "AppUpdateSkippedVersion"

    var isChecking: Bool = false
    var isUpdateAvailable: Bool = false
    var latestRelease: AppRelease? = nil
    var newReleases: [AppRelease] = []
    var lastCheckDate: Date? = nil
    var lastErrorMessage: String? = nil
    var statusMessage: String = "Not checked yet"

    var automaticallyCheckOnLaunch: Bool {
        didSet {
            defaults.set(automaticallyCheckOnLaunch, forKey: autoCheckKey)
        }
    }

    var includePrereleases: Bool {
        didSet {
            defaults.set(includePrereleases, forKey: includePrereleasesKey)
        }
    }

    var skippedVersion: String? {
        didSet {
            if let version = skippedVersion {
                defaults.set(version, forKey: skippedVersionKey)
            } else {
                defaults.removeObject(forKey: skippedVersionKey)
            }
        }
    }

    init() {
        if defaults.object(forKey: autoCheckKey) == nil {
            self.automaticallyCheckOnLaunch = true
        } else {
            self.automaticallyCheckOnLaunch = defaults.bool(forKey: autoCheckKey)
        }

        self.includePrereleases = defaults.bool(forKey: includePrereleasesKey)
        self.skippedVersion = defaults.string(forKey: skippedVersionKey)

        if let savedDate = defaults.object(forKey: lastCheckDateKey) as? Date {
            self.lastCheckDate = savedDate
        }
    }

    // MARK: - Update Checking Logic

    func checkForUpdates(manual: Bool = false) {
        guard !isChecking else { return }

        isChecking = true
        lastErrorMessage = nil
        if manual {
            statusMessage = "Checking GitHub for updates..."
        }

        Task { @MainActor in
            do {
                let releases = try await fetchAllReleasesFromGitHub(includePrerelease: includePrereleases)
                
                guard let topRelease = releases.first else {
                    self.latestRelease = nil
                    self.newReleases = []
                    self.isUpdateAvailable = false
                    self.statusMessage = "No public releases found"
                    self.isChecking = false
                    return
                }

                self.latestRelease = topRelease

                let now = Date()
                self.lastCheckDate = now
                self.defaults.set(now, forKey: self.lastCheckDateKey)

                let currentVersionStr = AppInfo.version.trimmingCharacters(in: .whitespacesAndNewlines)
                let currentSemVer = SemanticVersion(string: currentVersionStr)
                let remoteSemVer = topRelease.semVer

                if let remote = remoteSemVer {
                    if let current = currentSemVer, !current.isDevelopment {
                        // All releases strictly newer than current installed version
                        let intermediateNewReleases = releases.filter { release in
                            guard let releaseSemVer = release.semVer else { return false }
                            return releaseSemVer > current
                        }
                        self.newReleases = intermediateNewReleases.isEmpty ? [topRelease] : intermediateNewReleases

                        // Compare current vs remote release
                        if remote > current {
                            if !manual && self.skippedVersion == topRelease.tagName {
                                self.isUpdateAvailable = false
                                self.statusMessage = "Version \(topRelease.tagName) available (Skipped)"
                            } else {
                                self.isUpdateAvailable = true
                                self.statusMessage = "Version \(topRelease.tagName) is available"
                            }
                        } else {
                            self.isUpdateAvailable = false
                            self.statusMessage = "You're up to date (\(AppInfo.displayVersion))"
                        }
                    } else {
                        // Development build: show all recent releases
                        self.newReleases = Array(releases.prefix(5))
                        if manual {
                            self.isUpdateAvailable = true
                            self.statusMessage = "Development build. Latest release is \(topRelease.tagName)"
                        } else {
                            self.isUpdateAvailable = false
                            self.statusMessage = "Development build (\(topRelease.tagName) released)"
                        }
                    }
                } else {
                    self.newReleases = [topRelease]
                    self.isUpdateAvailable = false
                    self.statusMessage = "Unable to parse release version"
                }

                self.isChecking = false
            } catch {
                self.isChecking = false
                let errorDesc = error.localizedDescription
                self.lastErrorMessage = errorDesc
                self.statusMessage = "Check failed: \(errorDesc)"
            }
        }
    }

    private func fetchAllReleasesFromGitHub(includePrerelease: Bool) async throws -> [AppRelease] {
        var request = URLRequest(url: AppInfo.allReleasesAPIURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let appVer = AppInfo.version.isEmpty ? "dev" : AppInfo.version
        request.setValue("XPlaneLauncher/\(appVer)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            throw NSError(
                domain: "AppUpdateManager",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub API rate limit exceeded. Please try again later."]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "AppUpdateManager",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub server responded with status \(httpResponse.statusCode)."]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let allReleases = try decoder.decode([AppRelease].self, from: data)
        let filtered = allReleases.filter { release in
            if release.isDraft { return false }
            if !includePrerelease && release.isPrerelease { return false }
            return true
        }

        // Sort descending by semantic version if available, or keep published date ordering
        return filtered.sorted { (lhs, rhs) -> Bool in
            guard let lVer = lhs.semVer, let rVer = rhs.semVer else {
                return (lhs.publishedAt ?? Date.distantPast) > (rhs.publishedAt ?? Date.distantPast)
            }
            return lVer > rVer
        }
    }

    // MARK: - Actions

    func skipVersion(_ tag: String) {
        skippedVersion = tag
        isUpdateAvailable = false
        statusMessage = "Version \(tag) skipped"
    }

    func clearSkippedVersion() {
        skippedVersion = nil
        if let latest = latestRelease, let remote = latest.semVer,
           let current = SemanticVersion(string: AppInfo.version), remote > current {
            isUpdateAvailable = true
            statusMessage = "Version \(latest.tagName) is available"
        }
    }

    func downloadLatestDMG() {
        if let dmg = latestRelease?.dmgAsset {
            NSWorkspace.shared.open(dmg.browserDownloadURL)
        } else if let release = latestRelease {
            NSWorkspace.shared.open(release.htmlURL)
        } else {
            NSWorkspace.shared.open(AppInfo.releasesURL)
        }
    }

    func openReleasePage() {
        if let release = latestRelease {
            NSWorkspace.shared.open(release.htmlURL)
        } else {
            NSWorkspace.shared.open(AppInfo.releasesURL)
        }
    }
}
