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
import zlib

struct SkunkCraftsConfig: Sendable {
    var name: String
    var version: String?
    var remoteManifestURL: String?
    var baseURL: String?
    var configFileName: String? = nil
    var isBetaEnabled: Bool = false
    var protocolLevel: Int = 1
    var zone: String? = nil
    var manifestFileName: String? = nil
    var activeChannel: String = "stable"
    var availableChannels: [String] = []
    var changelogPath: String? = nil
    var readmePath: String? = nil
    var isDisabled: Bool = false
    var isLocked: Bool = false
    var liveriesEnabled: Bool = true
}

struct SkunkCraftsFileItem: Sendable {
    let relativePath: String
    let expectedCRC: String?
    let expectedSize: Int64?
}

actor SkunkCraftsUpdaterService {
    static let shared = SkunkCraftsUpdaterService()
    private var fileManager: FileManager { .default }
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    // MARK: - URL & CDN Zone Resolution

    nonisolated func resolveBaseURL(module: String?, zone: String? = nil) -> URL? {
        guard var raw = module?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // 1. IP address replacements (e.g. legacy Thranda server addresses)
        raw = raw.replacingOccurrences(of: "72.2.11.3:8080", with: "updates.thranda.org")
        raw = raw.replacingOccurrences(of: "72.2.11.34:8080", with: "updates.thranda.org")

        // 2. Remove common config / manifest suffixes if mistakenly appended to the base module
        let knownSuffixes = [
            "skunkcrafts_updater.cfg",
            "skunkcrafts_updater_beta.cfg",
            "skunkcrafts_updater_manifest.txt",
            "skunkcrafts_updater_whitelist.txt"
        ]
        for suffix in knownSuffixes {
            if raw.lowercased().hasSuffix(suffix) {
                raw = String(raw.dropLast(suffix.count))
                break
            }
        }

        // 3. CDN Zone Resolution
        var baseString: String
        let cleanZone = zone?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanZone, !cleanZone.isEmpty, cleanZone.lowercased() != "custom" {
            var pathPart = raw
            if let schemeRange = pathPart.range(of: "://") {
                pathPart = String(pathPart[schemeRange.upperBound...])
            }
            while pathPart.hasPrefix("/") {
                pathPart.removeFirst()
            }
            baseString = "http://\(cleanZone)-ccd.kxcdn.com/\(pathPart)"
        } else {
            baseString = raw
        }

        while baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        baseString += "/"

        return URL(string: baseString)
    }

    // MARK: - Protected Client Files

    nonisolated func isProtectedClientFile(_ relativePath: String) -> Bool {
        var normalized = relativePath.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/")
        while normalized.hasPrefix("/") {
            normalized.removeFirst()
        }
        let lower = normalized.lowercased()
        if lower == "skunkcrafts_updater.cfg" ||
           lower == "skunkcrafts_updater_ignore.txt" ||
           lower == "skunkcrafts" ||
           lower.hasPrefix("skunkcrafts/") {
            return true
        }
        if lower.hasPrefix("skunkcrafts_updater_beta") && lower.hasSuffix(".cfg") {
            return true
        }
        return false
    }

    // MARK: - Channel Management

    nonisolated func hasBetaChannel(in folderURL: URL) -> Bool {
        // 1. Legacy v3 beta file in root
        let betaURL = folderURL.appendingPathComponent("skunkcrafts_updater_beta.cfg")
        if FileManager.default.fileExists(atPath: betaURL.path) {
            return true
        }

        // 2. Any root file matching skunkcrafts_updater_beta*.cfg
        if let files = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) {
            if files.contains(where: { $0.lowercased().hasPrefix("skunkcrafts_updater_beta") && $0.lowercased().hasSuffix(".cfg") }) {
                return true
            }
        }

        // 3. Modern v4 channel files in skunkcrafts/channels/
        let channelsDir = folderURL.appendingPathComponent("skunkcrafts/channels")
        if let channelFiles = try? FileManager.default.contentsOfDirectory(atPath: channelsDir.path) {
            if channelFiles.contains(where: { $0.lowercased().hasSuffix(".cfg") }) {
                return true
            }
        }

        // 4. Declared in skunkcrafts_updater.cfg directly
        let cfgURL = folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
        if let parsed = parseConfig(at: cfgURL, defaultName: folderURL.lastPathComponent) {
            if parsed.availableChannels.contains(where: { $0.lowercased() != "stable" }) {
                return true
            }
        }

        return false
    }

    nonisolated func setChannel(_ channelName: String, in folderURL: URL) {
        let skunkDir = folderURL.appendingPathComponent("skunkcrafts")
        try? FileManager.default.createDirectory(at: skunkDir, withIntermediateDirectories: true)
        let channelCfgURL = skunkDir.appendingPathComponent("channel.cfg")
        let content = "channel|\(channelName)\n"
        try? content.write(to: channelCfgURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Config Detection & Parsing

    nonisolated func findConfig(in folderURL: URL, preferBeta: Bool = false) -> URL? {
        // Migrate early 4.0-beta layout if present
        let legacyBeta4URL = folderURL.appendingPathComponent("skunkcrafts/updater.cfg")
        let standardURL = folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
        if FileManager.default.fileExists(atPath: legacyBeta4URL.path) {
            if !FileManager.default.fileExists(atPath: standardURL.path) {
                try? FileManager.default.moveItem(at: legacyBeta4URL, to: standardURL)
            } else {
                try? FileManager.default.removeItem(at: legacyBeta4URL)
            }
        }
        let legacyIgnoreURL = folderURL.appendingPathComponent("skunkcrafts/ignore.txt")
        let standardIgnoreURL = folderURL.appendingPathComponent("skunkcrafts_updater_ignore.txt")
        if FileManager.default.fileExists(atPath: legacyIgnoreURL.path) {
            if FileManager.default.fileExists(atPath: standardIgnoreURL.path) {
                if let oldIgnore = try? String(contentsOf: legacyIgnoreURL, encoding: .utf8),
                   let fileHandle = try? FileHandle(forWritingTo: standardIgnoreURL) {
                    fileHandle.seekToEndOfFile()
                    if let data = ("\n" + oldIgnore).data(using: .utf8) {
                        fileHandle.write(data)
                    }
                    try? fileHandle.close()
                }
            } else {
                try? FileManager.default.moveItem(at: legacyIgnoreURL, to: standardIgnoreURL)
            }
            try? FileManager.default.removeItem(at: legacyIgnoreURL)
        }

        if preferBeta {
            let betaURL = folderURL.appendingPathComponent("skunkcrafts_updater_beta.cfg")
            if FileManager.default.fileExists(atPath: betaURL.path) {
                return betaURL
            }
        }
        let skunkcraftsFiles = [
            "skunkcrafts_updater.cfg",
            "skunkcrafts_updater_beta.cfg",
            "skunkcrafts_updater.json",
            "skunkcrafts_updater_config.txt"
        ]
        for name in skunkcraftsFiles {
            let url = folderURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    nonisolated func parseConfig(at url: URL, defaultName: String) -> SkunkCraftsConfig? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var name = defaultName
        var version: String? = nil
        var remoteURL: String? = nil
        var baseURL: String? = nil
        var zone: String? = nil
        var protocolLevel: Int = 1
        var manifestFileName: String? = nil
        var activeChannel: String = "stable"
        var changelogPath: String? = nil
        var readmePath: String? = nil
        var isDisabled: Bool = false
        var isLocked: Bool = false
        var liveriesEnabled: Bool = true
        var channelModules: [String: String] = [:]
        var channelZones: [String: String] = [:]

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }

            let parts: [String]
            if trimmed.contains("|") {
                parts = trimmed.components(separatedBy: "|")
            } else if trimmed.contains("=") {
                parts = trimmed.components(separatedBy: "=")
            } else {
                continue
            }

            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let val = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "name" {
                name = val
            } else if key == "version" || key == "build" {
                version = val
            } else if key == "url" || key == "manifest_url" || key == "base_url" || key == "module" {
                if key == "base_url" || key == "module" { baseURL = val; remoteURL = val }
                else { remoteURL = val }
            } else if key == "zone" {
                zone = val
            } else if key == "protocol" {
                if let proto = Int(val), proto >= 1 {
                    protocolLevel = proto
                }
            } else if key == "manifest" {
                manifestFileName = val
            } else if key == "channel" {
                activeChannel = val.lowercased()
            } else if key == "changelog" {
                changelogPath = val
            } else if key == "readme" {
                readmePath = val
            } else if key == "disabled" {
                isDisabled = (val.lowercased() == "true" || val == "1")
            } else if key == "locked" {
                isLocked = (val.lowercased() == "true" || val == "1")
            } else if key == "liveries" {
                liveriesEnabled = (val.lowercased() != "false" && val != "0")
            } else if key.hasPrefix("channel.") {
                let sub = String(key.dropFirst("channel.".count))
                let subParts = sub.components(separatedBy: ".")
                if subParts.count == 1 {
                    channelModules[subParts[0]] = val
                } else if subParts.count >= 2 {
                    let chName = subParts[0]
                    let prop = subParts[1]
                    if prop == "module" || prop == "url" {
                        channelModules[chName] = val
                    } else if prop == "zone" {
                        channelZones[chName] = val
                    }
                }
            }
        }

        // Folder where config is located
        let folderURL = url.deletingLastPathComponent()

        // Discover available channels
        var availableChannels = Set<String>(["stable"])
        for ch in channelModules.keys {
            availableChannels.insert(ch)
        }
        if !activeChannel.isEmpty {
            availableChannels.insert(activeChannel)
        }

        // Check skunkcrafts/channels/
        let channelsDir = folderURL.appendingPathComponent("skunkcrafts/channels")
        if let channelFiles = try? FileManager.default.contentsOfDirectory(atPath: channelsDir.path) {
            for file in channelFiles where file.lowercased().hasSuffix(".cfg") {
                let chName = String(file.dropLast(".cfg".count)).lowercased()
                availableChannels.insert(chName)
                let chFileURL = channelsDir.appendingPathComponent(file)
                if let chContent = try? String(contentsOf: chFileURL, encoding: .utf8) {
                    for chLine in chContent.components(separatedBy: .newlines) {
                        let chParts = chLine.components(separatedBy: "|")
                        if chParts.count >= 2 {
                            let k = chParts[0].trimmingCharacters(in: .whitespaces).lowercased()
                            let v = chParts[1].trimmingCharacters(in: .whitespaces)
                            if k == "module" || k == "url" {
                                channelModules[chName] = v
                            } else if k == "zone" {
                                channelZones[chName] = v
                            }
                        }
                    }
                }
            }
        }

        // Check for legacy beta files at the root
        let betaCfgURL = folderURL.appendingPathComponent("skunkcrafts_updater_beta.cfg")
        if FileManager.default.fileExists(atPath: betaCfgURL.path) {
            availableChannels.insert("beta")
            if channelModules["beta"] == nil, let betaContent = try? String(contentsOf: betaCfgURL, encoding: .utf8) {
                for bLine in betaContent.components(separatedBy: .newlines) {
                    let bParts = bLine.components(separatedBy: "|")
                    if bParts.count >= 2 {
                        let k = bParts[0].trimmingCharacters(in: .whitespaces).lowercased()
                        let v = bParts[1].trimmingCharacters(in: .whitespaces)
                        if k == "url" || k == "module" || k == "base_url" {
                            channelModules["beta"] = v
                        }
                    }
                }
            }
        }

        // Check skunkcrafts/channel.cfg for active channel override
        let activeChannelCfg = folderURL.appendingPathComponent("skunkcrafts/channel.cfg")
        if let chData = try? String(contentsOf: activeChannelCfg, encoding: .utf8) {
            for chLine in chData.components(separatedBy: .newlines) {
                let chParts = chLine.components(separatedBy: "|")
                if chParts.count >= 2 && chParts[0].trimmingCharacters(in: .whitespaces).lowercased() == "channel" {
                    activeChannel = chParts[1].trimmingCharacters(in: .whitespaces).lowercased()
                    availableChannels.insert(activeChannel)
                    break
                }
            }
        }

        let isBeta = url.lastPathComponent.lowercased().contains("beta") || activeChannel.contains("beta")

        // If non-stable active channel is selected and has custom module/zone, override
        if activeChannel != "stable" {
            if let chModule = channelModules[activeChannel] {
                remoteURL = chModule
                baseURL = chModule
            }
            if let chZone = channelZones[activeChannel] {
                zone = chZone
            }
        }

        let resolvedBase = resolveBaseURL(module: baseURL ?? remoteURL, zone: zone)

        let sortedChannels = availableChannels.sorted { a, b in
            if a.lowercased() == "stable" { return true }
            if b.lowercased() == "stable" { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }

        return SkunkCraftsConfig(
            name: name,
            version: version,
            remoteManifestURL: remoteURL,
            baseURL: resolvedBase?.absoluteString ?? baseURL ?? remoteURL,
            configFileName: url.lastPathComponent,
            isBetaEnabled: isBeta,
            protocolLevel: protocolLevel,
            zone: zone,
            manifestFileName: manifestFileName,
            activeChannel: activeChannel,
            availableChannels: sortedChannels,
            changelogPath: changelogPath,
            readmePath: readmePath,
            isDisabled: isDisabled,
            isLocked: isLocked,
            liveriesEnabled: liveriesEnabled
        )
    }

    // MARK: - Ignore & Blacklist Parsing

    nonisolated func parseIgnoreFile(in folderURL: URL) -> Set<String> {
        let ignoreFileURL = folderURL.appendingPathComponent("skunkcrafts_updater_ignore.txt")
        guard let content = try? String(contentsOf: ignoreFileURL, encoding: .utf8) else {
            return []
        }
        return parseBlacklist(content: content)
    }

    nonisolated func parseBlacklist(content: String) -> Set<String> {
        var paths = Set<String>()
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }
            var normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
            while normalized.hasPrefix("/") {
                normalized.removeFirst()
            }
            while normalized.hasSuffix("/") {
                normalized.removeLast()
            }
            if !normalized.isEmpty {
                paths.insert(normalized)
            }
        }
        return paths
    }

    nonisolated func isIgnored(relativePath: String, ignoredSet: Set<String>) -> Bool {
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
        for ignoreEntry in ignoredSet {
            if normalizedPath == ignoreEntry || normalizedPath.hasPrefix(ignoreEntry + "/") {
                return true
            }
            if ignoreEntry.hasPrefix("*") {
                let suffix = ignoreEntry.dropFirst()
                if normalizedPath.hasSuffix(suffix) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Manifest & Whitelist Parsing

    nonisolated func parseWhitelist(content: String) -> [SkunkCraftsFileItem] {
        var items: [SkunkCraftsFileItem] = []
        let metadataKeys: Set<String> = [
            "name", "version", "build", "url", "manifest_url", "base_url", "module",
            "disabled", "locked", "zone", "liveries", "protocol", "manifest", "channel",
            "changelog", "readme", "pack", "pack_name", "pack_members", "member"
        ]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }

            let parts: [String]
            if trimmed.contains("|") {
                parts = trimmed.components(separatedBy: "|")
            } else if trimmed.contains(":") {
                parts = trimmed.components(separatedBy: ":")
            } else {
                parts = [trimmed]
            }

            guard !parts.isEmpty else { continue }
            let firstPart = parts[0].trimmingCharacters(in: .whitespaces)
            let lowerFirst = firstPart.lowercased()
            if metadataKeys.contains(lowerFirst) || lowerFirst.hasPrefix("channel.") {
                continue
            }

            var rawPath = firstPart.replacingOccurrences(of: "\\", with: "/")
            while rawPath.hasPrefix("/") {
                rawPath.removeFirst()
            }
            guard !rawPath.isEmpty else { continue }

            // Security check: reject path traversal and protected skunkcrafts internal directory
            if rawPath.contains("..") || rawPath.contains(":") || rawPath.lowercased().hasPrefix("skunkcrafts/") {
                continue
            }

            var expectedCRC: String? = nil
            var expectedSize: Int64? = nil

            if parts.count >= 2 {
                let secondPart = parts[1].trimmingCharacters(in: .whitespaces)
                if !secondPart.isEmpty {
                    expectedCRC = secondPart
                }
            }
            if parts.count >= 3 {
                let thirdPart = parts[2].trimmingCharacters(in: .whitespaces)
                expectedSize = Int64(thirdPart)
            }

            items.append(SkunkCraftsFileItem(relativePath: rawPath, expectedCRC: expectedCRC, expectedSize: expectedSize))
        }
        return items
    }

    nonisolated func parseManifest(content: String) -> [SkunkCraftsFileItem] {
        var items: [SkunkCraftsFileItem] = []
        let metadataKeys: Set<String> = [
            "name", "version", "build", "url", "manifest_url", "base_url", "module",
            "disabled", "locked", "zone", "liveries", "protocol", "manifest", "channel",
            "changelog", "readme", "pack", "pack_name", "pack_members", "member"
        ]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }

            let parts: [String]
            if trimmed.contains("|") {
                parts = trimmed.components(separatedBy: "|")
            } else if trimmed.contains(":") {
                parts = trimmed.components(separatedBy: ":")
            } else {
                continue
            }

            guard parts.count >= 2 else { continue }
            let firstPart = parts[0].trimmingCharacters(in: .whitespaces)
            let lowerFirst = firstPart.lowercased()
            if metadataKeys.contains(lowerFirst) || lowerFirst.hasPrefix("channel.") {
                continue
            }

            if firstPart.hasPrefix("/") || firstPart.hasPrefix("\\") {
                continue
            }

            let rawPath = firstPart.replacingOccurrences(of: "\\", with: "/")
            guard !rawPath.isEmpty else { continue }

            // Security check: reject directory traversal and paths in internal skunkcrafts/ folder
            if rawPath.contains("..") || rawPath.contains(":") || rawPath.lowercased().hasPrefix("skunkcrafts/") {
                continue
            }

            var expectedCRC: String? = nil
            var expectedSize: Int64? = nil

            let secondPart = parts[1].trimmingCharacters(in: .whitespaces)
            if !secondPart.isEmpty && secondPart != "-1" {
                expectedCRC = secondPart
            }

            if parts.count >= 3 {
                let thirdPart = parts[2].trimmingCharacters(in: .whitespaces)
                if let size = Int64(thirdPart), size >= 0 {
                    expectedSize = size
                }
            }

            items.append(SkunkCraftsFileItem(relativePath: rawPath, expectedCRC: expectedCRC, expectedSize: expectedSize))
        }
        return items
    }

    nonisolated func parseSizesList(content: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }
            let parts = trimmed.contains("|") ? trimmed.components(separatedBy: "|") : trimmed.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            var rawPath = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/")
            while rawPath.hasPrefix("/") {
                rawPath.removeFirst()
            }
            guard !rawPath.isEmpty, let size = Int64(parts[1].trimmingCharacters(in: .whitespaces)), size >= 0 else {
                continue
            }
            sizes[rawPath] = size
        }
        return sizes
    }

    // MARK: - Remote Data Fetching & CRC Verification

    private func fetchTextContent(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        URLCache.shared.removeCachedResponse(for: request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") {
            throw URLError(.cannotParseResponse)
        }
        return content
    }

    nonisolated func parseCRC32(_ string: String) -> UInt32? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 1. Explicit hex with 0x / 0X prefix
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            let hexStr = String(trimmed.dropFirst(2))
            return UInt32(hexStr, radix: 16)
        }

        // 2. Unsigned decimal
        if let dec = UInt32(trimmed) {
            return dec
        }

        // 3. Signed decimal (from signed 32-bit CRC generators e.g. Python 2)
        if let signed = Int32(trimmed) {
            return UInt32(bitPattern: signed)
        }

        // 4. Hex without 0x prefix (e.g. "ABCD1234", "a1b2c3d4")
        if let hex = UInt32(trimmed, radix: 16) {
            return hex
        }

        return nil
    }

    nonisolated func calculateCRC32UInt32(for url: URL) -> UInt32? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }
        var crc: uLong = zlib.crc32(0, nil, 0)
        let bufferSize = 65536
        while true {
            let chunk = fileHandle.readData(ofLength: bufferSize)
            if chunk.isEmpty { break }
            chunk.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    crc = zlib.crc32(crc, base.assumingMemoryBound(to: Bytef.self), uInt(chunk.count))
                }
            }
        }
        return UInt32(crc)
    }

    func checkAddonStatus(
        folderURL: URL,
        config: SkunkCraftsConfig,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> (latestVersion: String?, isUpdateAvailable: Bool, statusMessage: String) {
        guard let baseURL = resolveBaseURL(module: config.baseURL ?? config.remoteManifestURL, zone: config.zone) else {
            await logHandler("[SkunkCrafts] No valid remote URL configured for \(config.name)")
            throw URLError(.badURL)
        }

        let channelLabel = (config.isBetaEnabled || config.activeChannel.lowercased() != "stable") ? " (\(config.activeChannel.capitalized) Channel)" : ""
        await logHandler("[SkunkCrafts] Checking \(config.name)\(channelLabel) from \(baseURL.absoluteString)...")

        let configFileName = config.configFileName ?? (config.isBetaEnabled ? "skunkcrafts_updater_beta.cfg" : "skunkcrafts_updater.cfg")

        var localVersion = config.version
        if localVersion == nil {
            let specificURL = folderURL.appendingPathComponent(configFileName)
            if FileManager.default.fileExists(atPath: specificURL.path), let parsed = parseConfig(at: specificURL, defaultName: config.name) {
                localVersion = parsed.version
            } else if let cfgURL = findConfig(in: folderURL, preferBeta: config.isBetaEnabled), let parsed = parseConfig(at: cfgURL, defaultName: config.name) {
                localVersion = parsed.version
            }
        }

        // 1. Fetch remote config
        var remoteVersion: String? = nil
        var remoteProtocol: Int? = nil
        var remoteManifestName: String? = nil
        var remoteLocked: Bool = false

        let remoteConfigURL = baseURL.appendingPathComponent(configFileName)
        var configContent: String? = try? await fetchTextContent(from: remoteConfigURL)
        if configContent == nil && configFileName != "skunkcrafts_updater.cfg" {
            configContent = try? await fetchTextContent(from: baseURL.appendingPathComponent("skunkcrafts_updater.cfg"))
        }
        if let configContent = configContent {
            let lines = configContent.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.components(separatedBy: "|")
                if parts.count >= 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let v = parts[1].trimmingCharacters(in: .whitespaces)
                    if k == "version" || k == "build" {
                        remoteVersion = v
                    } else if k == "protocol" {
                        if let p = Int(v) { remoteProtocol = p }
                    } else if k == "manifest" {
                        remoteManifestName = v
                    } else if k == "locked" {
                        remoteLocked = (v.lowercased() == "true" || v == "1")
                    }
                }
            }
        }

        if remoteLocked {
            await logHandler("[SkunkCrafts] Remote repository is locked for maintenance.")
            return (remoteVersion ?? localVersion, false, "Repository locked for maintenance")
        }

        let effectiveProtocol = remoteProtocol ?? config.protocolLevel
        await logHandler("[SkunkCrafts] Remote version: \(remoteVersion ?? "unknown") (protocol \(effectiveProtocol))")

        // 2. Fetch remote manifest
        var manifestItems: [SkunkCraftsFileItem] = []
        if effectiveProtocol >= 2 {
            let manifestName = remoteManifestName ?? config.manifestFileName ?? "skunkcrafts_updater_manifest.txt"
            let manifestURL = baseURL.appendingPathComponent(manifestName)
            if let manifestText = try? await fetchTextContent(from: manifestURL) {
                manifestItems = parseManifest(content: manifestText)
                await logHandler("[SkunkCrafts] Fetched \(manifestName) (\(manifestItems.count) entries, protocol 2)")
            }
        } else {
            let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
            if let whitelistText = try? await fetchTextContent(from: whitelistURL) {
                manifestItems = parseWhitelist(content: whitelistText)
                await logHandler("[SkunkCrafts] Fetched skunkcrafts_updater_whitelist.txt (\(manifestItems.count) entries, protocol 1)")
            }
            let sizesURL = baseURL.appendingPathComponent("skunkcrafts_updater_sizeslist.txt")
            if let sizesText = try? await fetchTextContent(from: sizesURL) {
                let sizes = parseSizesList(content: sizesText)
                manifestItems = manifestItems.map { item in
                    if let s = sizes[item.relativePath] {
                        return SkunkCraftsFileItem(relativePath: item.relativePath, expectedCRC: item.expectedCRC, expectedSize: s)
                    }
                    return item
                }
                await logHandler("[SkunkCrafts] Applied auxiliary file sizes (\(sizes.count) entries)")
            }
        }

        if !manifestItems.contains(where: { $0.relativePath.lowercased() == configFileName.lowercased() }) {
            manifestItems.append(SkunkCraftsFileItem(relativePath: configFileName, expectedCRC: nil, expectedSize: nil))
        }

        // 3. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: folderURL)
        var blacklistedPaths: Set<String> = []
        let blacklistURL = baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt")
        if let blacklistText = try? await fetchTextContent(from: blacklistURL) {
            blacklistedPaths = parseBlacklist(content: blacklistText)
            ignoredSet.formUnion(blacklistedPaths)
            await logHandler("[SkunkCrafts] Fetched skunkcrafts_updater_blacklist.txt (\(blacklistedPaths.count) entries)")
        }

        let latestVersion = remoteVersion ?? localVersion

        if let remoteVersion = remoteVersion, let localVersion = localVersion {
            if VersionComparator.isNewer(remoteVersion, than: localVersion) {
                await logHandler("[SkunkCrafts] Newer remote version found: Local '\(localVersion)' vs Remote '\(remoteVersion)'. Marking addon for update.")
                return (remoteVersion, true, "Update available (\(remoteVersion))")
            } else if VersionComparator.isNewer(localVersion, than: remoteVersion) {
                await logHandler("[SkunkCrafts] Local version '\(localVersion)' is newer than remote '\(remoteVersion)'. Addon is up to date.")
                return (localVersion, false, "Up to date")
            }
        }

        // 4. Compare local files against manifest
        var count = 0
        for item in manifestItems {
            count += 1
            if count % 50 == 0 {
                await Task.yield()
            }

            if isIgnored(relativePath: item.relativePath, ignoredSet: ignoredSet) {
                await logHandler("[SkunkCrafts] Ignored file: \(item.relativePath)")
                continue
            }

            let localFileURL: URL
            do {
                localFileURL = try PathSecurity.validateSubpath(relativePath: item.relativePath, within: folderURL)
            } catch {
                await logHandler("[SkunkCrafts] Insecure path rejected in manifest: \(item.relativePath)")
                continue
            }

            if !fileManager.fileExists(atPath: localFileURL.path) {
                await logHandler("[SkunkCrafts] Missing file: \(item.relativePath). Marking addon for update.")
                return (latestVersion, true, "Update available (modified files)")
            } else if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr) {
                // 0xFFFFFFFF (4294967295) and 0 are sentinel values in SkunkCrafts manifests for install-only / user config / cache files.
                if distantCRC != 0xFFFFFFFF && distantCRC != 0 {
                    if let localCRC = calculateCRC32UInt32(for: localFileURL) {
                        if localCRC != distantCRC {
                            await logHandler("[SkunkCrafts] CRC mismatch for \(item.relativePath) (local: \(localCRC), distant: \(distantCRC)). Marking addon for update.")
                            return (latestVersion, true, "Update available (modified files)")
                        }
                    } else {
                        await logHandler("[SkunkCrafts] Unreadable file: \(item.relativePath). Marking addon for update.")
                        return (latestVersion, true, "Update available (modified files)")
                    }
                }
            } else if let expectedSize = item.expectedSize, expectedSize >= 0 {
                if let attrs = try? fileManager.attributesOfItem(atPath: localFileURL.path),
                   let localSize = attrs[.size] as? Int64 {
                    if localSize != expectedSize {
                        await logHandler("[SkunkCrafts] Size mismatch for \(item.relativePath) (local: \(localSize), distant: \(expectedSize)). Marking addon for update.")
                        return (latestVersion, true, "Update available (modified files)")
                    }
                }
            }
        }

        // 5. Check if any local file is in the remote blacklist (needing deletion)
        for blacklisted in blacklistedPaths {
            if isProtectedClientFile(blacklisted) { continue }
            if let localURL = try? PathSecurity.validateSubpath(relativePath: blacklisted, within: folderURL),
               fileManager.fileExists(atPath: localURL.path) {
                await logHandler("[SkunkCrafts] Blacklisted file present locally: \(blacklisted). Marking addon for update.")
                return (latestVersion, true, "Update available (blacklisted files)")
            }
        }

        await logHandler("[SkunkCrafts] \(config.name) is up to date.")
        return (latestVersion, false, "Up to date")
    }

    func downloadAndApplyUpdates(
        for addonFolder: URL,
        config: SkunkCraftsConfig,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in },
        progressHandler: @Sendable @escaping @MainActor (String, Double) -> Void
    ) async throws {
        guard let baseURL = resolveBaseURL(module: config.baseURL ?? config.remoteManifestURL, zone: config.zone) else { return }

        let channelLabel = (config.isBetaEnabled || config.activeChannel.lowercased() != "stable") ? " (\(config.activeChannel.capitalized) Channel)" : ""
        await logHandler("[SkunkCrafts] Starting update check for \(config.name)\(channelLabel)...")

        let configFileName = config.configFileName ?? (config.isBetaEnabled ? "skunkcrafts_updater_beta.cfg" : "skunkcrafts_updater.cfg")

        var localVersion = config.version
        if localVersion == nil {
            let specificURL = addonFolder.appendingPathComponent(configFileName)
            if FileManager.default.fileExists(atPath: specificURL.path), let parsed = parseConfig(at: specificURL, defaultName: config.name) {
                localVersion = parsed.version
            } else if let cfgURL = findConfig(in: addonFolder, preferBeta: config.isBetaEnabled), let parsed = parseConfig(at: cfgURL, defaultName: config.name) {
                localVersion = parsed.version
            }
        }

        // 1. Fetch remote config
        var remoteVersion: String? = nil
        var remoteProtocol: Int? = nil
        var remoteManifestName: String? = nil

        let remoteConfigURL = baseURL.appendingPathComponent(configFileName)
        var configContent: String? = try? await fetchTextContent(from: remoteConfigURL)
        if configContent == nil && configFileName != "skunkcrafts_updater.cfg" {
            configContent = try? await fetchTextContent(from: baseURL.appendingPathComponent("skunkcrafts_updater.cfg"))
        }
        if let configContent = configContent {
            let lines = configContent.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.components(separatedBy: "|")
                if parts.count >= 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let v = parts[1].trimmingCharacters(in: .whitespaces)
                    if k == "version" || k == "build" {
                        remoteVersion = v
                    } else if k == "protocol" {
                        if let p = Int(v) { remoteProtocol = p }
                    } else if k == "manifest" {
                        remoteManifestName = v
                    }
                }
            }
        }

        let effectiveProtocol = remoteProtocol ?? config.protocolLevel

        // 2. Fetch remote manifest
        var manifestItems: [SkunkCraftsFileItem] = []
        if effectiveProtocol >= 2 {
            let manifestName = remoteManifestName ?? config.manifestFileName ?? "skunkcrafts_updater_manifest.txt"
            let manifestURL = baseURL.appendingPathComponent(manifestName)
            if let manifestText = try? await fetchTextContent(from: manifestURL) {
                manifestItems = parseManifest(content: manifestText)
            }
        } else {
            let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
            if let whitelistText = try? await fetchTextContent(from: whitelistURL) {
                manifestItems = parseWhitelist(content: whitelistText)
            }
            let sizesURL = baseURL.appendingPathComponent("skunkcrafts_updater_sizeslist.txt")
            if let sizesText = try? await fetchTextContent(from: sizesURL) {
                let sizes = parseSizesList(content: sizesText)
                manifestItems = manifestItems.map { item in
                    if let s = sizes[item.relativePath] {
                        return SkunkCraftsFileItem(relativePath: item.relativePath, expectedCRC: item.expectedCRC, expectedSize: s)
                    }
                    return item
                }
            }
        }

        if !manifestItems.contains(where: { $0.relativePath.lowercased() == configFileName.lowercased() }) {
            manifestItems.append(SkunkCraftsFileItem(relativePath: configFileName, expectedCRC: nil, expectedSize: nil))
        }

        // 3. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: addonFolder)
        var blacklistedPaths: Set<String> = []
        if let blacklistText = try? await fetchTextContent(from: baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt")) {
            blacklistedPaths = parseBlacklist(content: blacklistText)
            ignoredSet.formUnion(blacklistedPaths)
        }

        // 4. Filter files needing download
        var filesToDownload: [SkunkCraftsFileItem] = []
        var checkCount = 0
        for item in manifestItems {
            checkCount += 1
            if checkCount % 50 == 0 {
                await Task.yield()
            }

            if isIgnored(relativePath: item.relativePath, ignoredSet: ignoredSet) {
                await logHandler("[SkunkCrafts] Skipping ignored file: \(item.relativePath)")
                continue
            }

            let localFileURL: URL
            do {
                localFileURL = try PathSecurity.validateSubpath(relativePath: item.relativePath, within: addonFolder)
            } catch {
                await logHandler("[SkunkCrafts] Insecure path rejected in manifest: \(item.relativePath)")
                continue
            }

            let fileExists = fileManager.fileExists(atPath: localFileURL.path)
            if !fileExists {
                await logHandler("[SkunkCrafts] Missing file: \(item.relativePath). Queuing for download.")
                filesToDownload.append(item)
            } else if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr) {
                if distantCRC != 0xFFFFFFFF && distantCRC != 0 {
                    if let localCRC = calculateCRC32UInt32(for: localFileURL) {
                        if localCRC != distantCRC {
                            await logHandler("[SkunkCrafts] CRC mismatch for \(item.relativePath) (local: \(localCRC), distant: \(distantCRC)). Queuing for download.")
                            filesToDownload.append(item)
                        }
                    } else {
                        await logHandler("[SkunkCrafts] Unreadable local file: \(item.relativePath). Queuing for repair.")
                        filesToDownload.append(item)
                    }
                }
            } else if let expectedSize = item.expectedSize, expectedSize >= 0 {
                if let attrs = try? fileManager.attributesOfItem(atPath: localFileURL.path),
                   let localSize = attrs[.size] as? Int64 {
                    if localSize != expectedSize {
                        await logHandler("[SkunkCrafts] Size mismatch for \(item.relativePath) (local: \(localSize), distant: \(expectedSize)). Queuing for download.")
                        filesToDownload.append(item)
                    }
                } else {
                    filesToDownload.append(item)
                }
            } else {
                let isConfigFile = item.relativePath.lowercased().hasPrefix("skunkcrafts_updater") &&
                    (item.relativePath.lowercased().hasSuffix(".cfg") || item.relativePath.lowercased().hasSuffix(".txt") || item.relativePath.lowercased().hasSuffix(".json"))
                if isConfigFile && (remoteVersion != nil && (localVersion == nil || remoteVersion != localVersion)) {
                    filesToDownload.append(item)
                }
            }
        }

        // 5. Filter blacklisted files needing deletion
        var filesToDelete: [String] = []
        for blacklisted in blacklistedPaths {
            if isProtectedClientFile(blacklisted) { continue }
            if let localURL = try? PathSecurity.validateSubpath(relativePath: blacklisted, within: addonFolder),
               fileManager.fileExists(atPath: localURL.path) {
                filesToDelete.append(blacklisted)
            }
        }

        guard !filesToDownload.isEmpty || !filesToDelete.isEmpty else {
            await logHandler("[SkunkCrafts] All files are already up to date.")
            await progressHandler("Up to date", 1.0)
            return
        }

        if !filesToDownload.isEmpty {
            await logHandler("[SkunkCrafts] Downloading \(filesToDownload.count) file(s) needing update/repair out of \(manifestItems.count) total files...")
        }

        // 6. Download each file
        let totalFiles = filesToDownload.count
        for (index, item) in filesToDownload.enumerated() {
            let progress = totalFiles > 0 ? Double(index) / Double(totalFiles) : 1.0
            let filename = (item.relativePath as NSString).lastPathComponent
            await progressHandler("Downloading \(filename)...", progress)

            let relativeEncoded = item.relativePath
                .split(separator: "/")
                .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/")

            guard let fileURL = URL(string: relativeEncoded, relativeTo: baseURL) else {
                await logHandler("[SkunkCrafts] Invalid download URL for: \(item.relativePath)")
                continue
            }

            let localDestination: URL
            do {
                localDestination = try PathSecurity.validateSubpath(relativePath: item.relativePath, within: addonFolder)
            } catch {
                await logHandler("[SkunkCrafts] Insecure subpath rejected during download: \(item.relativePath)")
                continue
            }

            let parentDir = localDestination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

            await logHandler("[SkunkCrafts] Downloading: \(item.relativePath)...")

            var downloadRequest = URLRequest(url: fileURL)
            downloadRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            downloadRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            downloadRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")
            URLCache.shared.removeCachedResponse(for: downloadRequest)

            let (tempDownloadedURL, response) = try await session.download(for: downloadRequest)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                await logHandler("[SkunkCrafts] Failed downloading \(item.relativePath): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                continue
            }

            if fileManager.fileExists(atPath: localDestination.path) {
                try? fileManager.removeItem(at: localDestination)
            }
            try fileManager.moveItem(at: tempDownloadedURL, to: localDestination)
        }

        // 7. Delete blacklisted files
        for file in filesToDelete {
            if let localURL = try? PathSecurity.validateSubpath(relativePath: file, within: addonFolder) {
                try? fileManager.removeItem(at: localURL)
                await logHandler("[SkunkCrafts] Deleted blacklisted file: \(file)")
            }
        }

        // 8. Clean up early 4.0-beta leftover files if present
        let legacyBeta4URL = addonFolder.appendingPathComponent("skunkcrafts/updater.cfg")
        if fileManager.fileExists(atPath: legacyBeta4URL.path) {
            try? fileManager.removeItem(at: legacyBeta4URL)
        }
        let legacyIgnoreURL = addonFolder.appendingPathComponent("skunkcrafts/ignore.txt")
        if fileManager.fileExists(atPath: legacyIgnoreURL.path) {
            try? fileManager.removeItem(at: legacyIgnoreURL)
        }

        await logHandler("[SkunkCrafts] Update completed successfully.")
        await progressHandler("Up to date", 1.0)
    }

    func fetchReleaseNotes(
        for addonFolder: URL,
        config: SkunkCraftsConfig,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> String? {
        let baseURL = resolveBaseURL(module: config.baseURL ?? config.remoteManifestURL, zone: config.zone)

        // 1. Explicit changelog or readme configured
        if let changelog = config.changelogPath, !changelog.isEmpty {
            if let baseURL,
               let encoded = changelog.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let remoteURL = URL(string: encoded, relativeTo: baseURL),
               let content = try? await fetchTextContent(from: remoteURL),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            let localURL = addonFolder.appendingPathComponent(changelog)
            if let content = try? String(contentsOf: localURL, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
        }

        if let readme = config.readmePath, !readme.isEmpty {
            if let baseURL,
               let encoded = readme.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let remoteURL = URL(string: encoded, relativeTo: baseURL),
               let content = try? await fetchTextContent(from: remoteURL),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            let localURL = addonFolder.appendingPathComponent(readme)
            if let content = try? String(contentsOf: localURL, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
        }

        // 2. Discover changelog in remote manifest
        if let baseURL {
            await logHandler("[SkunkCrafts] Searching for changelog / release notes in remote manifest for \(config.name)...")

            var candidatePaths: [String] = []
            if config.protocolLevel >= 2 {
                let manifestName = config.manifestFileName ?? "skunkcrafts_updater_manifest.txt"
                if let manifestText = try? await fetchTextContent(from: baseURL.appendingPathComponent(manifestName)) {
                    candidatePaths = parseManifest(content: manifestText).map(\.relativePath)
                }
            } else {
                if let whitelistText = try? await fetchTextContent(from: baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")) {
                    candidatePaths = parseWhitelist(content: whitelistText).map(\.relativePath)
                }
            }

            if let bestMatch = ChangelogFinder.bestChangelogMatch(in: candidatePaths) {
                await logHandler("[SkunkCrafts] Found release notes candidate: \(bestMatch)")
                let relativeEncoded = bestMatch
                    .split(separator: "/")
                    .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                    .joined(separator: "/")
                if let fileURL = URL(string: relativeEncoded, relativeTo: baseURL),
                   let content = try? await fetchTextContent(from: fileURL),
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return content
                }
            }
        }

        // 3. Fallback to local file in addon folder
        if let localURL = ChangelogFinder.findLocalChangelog(in: addonFolder),
           let content = try? String(contentsOf: localURL, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await logHandler("[SkunkCrafts] Loaded local release notes from \(localURL.lastPathComponent)")
            return content
        }

        return nil
    }
}

// MARK: - AddonUpdater Conformance

extension SkunkCraftsUpdaterService: AddonUpdater {
    func checkStatus(
        for addon: UpdateManager.UpdatableAddon,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> AddonUpdateCheckResult {
        var config = parseConfig(at: addon.configFileURL, defaultName: addon.name) ?? SkunkCraftsConfig(
            name: addon.name,
            version: addon.currentVersion,
            remoteManifestURL: addon.remoteManifestURL,
            baseURL: nil,
            configFileName: addon.configFileURL.lastPathComponent,
            isBetaEnabled: addon.isBetaEnabled
        )
        config.activeChannel = addon.activeChannel
        config.isBetaEnabled = addon.isBetaEnabled || (addon.activeChannel.lowercased() == "beta")
        let result = try await checkAddonStatus(folderURL: addon.folderURL, config: config, logHandler: logHandler)
        return AddonUpdateCheckResult(
            latestVersion: result.latestVersion,
            isUpdateAvailable: result.isUpdateAvailable,
            statusMessage: result.statusMessage
        )
    }

    func applyUpdates(
        for addon: UpdateManager.UpdatableAddon,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in },
        progressHandler: @Sendable @escaping @MainActor (String, Double) -> Void
    ) async throws {
        var config = parseConfig(at: addon.configFileURL, defaultName: addon.name) ?? SkunkCraftsConfig(
            name: addon.name,
            version: addon.currentVersion,
            remoteManifestURL: addon.remoteManifestURL,
            baseURL: nil,
            configFileName: addon.configFileURL.lastPathComponent,
            isBetaEnabled: addon.isBetaEnabled
        )
        config.activeChannel = addon.activeChannel
        config.isBetaEnabled = addon.isBetaEnabled || (addon.activeChannel.lowercased() == "beta")
        try await downloadAndApplyUpdates(
            for: addon.folderURL,
            config: config,
            logHandler: logHandler,
            progressHandler: progressHandler
        )
    }

    func fetchReleaseNotes(
        for addon: UpdateManager.UpdatableAddon,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> String? {
        var config = parseConfig(at: addon.configFileURL, defaultName: addon.name) ?? SkunkCraftsConfig(
            name: addon.name,
            version: addon.currentVersion,
            remoteManifestURL: addon.remoteManifestURL,
            baseURL: nil,
            configFileName: addon.configFileURL.lastPathComponent,
            isBetaEnabled: addon.isBetaEnabled
        )
        config.activeChannel = addon.activeChannel
        config.isBetaEnabled = addon.isBetaEnabled || (addon.activeChannel.lowercased() == "beta")
        return try await fetchReleaseNotes(for: addon.folderURL, config: config, logHandler: logHandler)
    }
}
