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
}

struct SkunkCraftsFileItem: Sendable {
    let relativePath: String
    let expectedCRC: String?
    let expectedSize: Int64?
}

actor SkunkCraftsUpdaterService {
    static let shared = SkunkCraftsUpdaterService()
    private var fileManager: FileManager { .default }

    // MARK: - Config Detection & Parsing

    nonisolated func findConfig(in folderURL: URL) -> URL? {
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

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.components(separatedBy: "|")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let val = parts[1].trimmingCharacters(in: .whitespaces)
                if key == "name" { name = val }
                else if key == "version" || key == "build" { version = val }
                else if key == "url" || key == "manifest_url" || key == "base_url" || key == "module" {
                    if key == "base_url" || key == "module" { baseURL = val; remoteURL = val }
                    else { remoteURL = val }
                }
            } else {
                let eqParts = trimmed.components(separatedBy: "=")
                if eqParts.count >= 2 {
                    let key = eqParts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let val = eqParts[1].trimmingCharacters(in: .whitespaces)
                    if key == "name" { name = val }
                    else if key == "version" || key == "build" { version = val }
                    else if key == "url" || key == "manifest_url" || key == "base_url" || key == "module" {
                        if key == "base_url" || key == "module" { baseURL = val; remoteURL = val }
                        else { remoteURL = val }
                    }
                }
            }
        }

        return SkunkCraftsConfig(name: name, version: version, remoteManifestURL: remoteURL, baseURL: baseURL)
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
            paths.insert(normalized)
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
        let metadataKeys: Set<String> = ["name", "version", "build", "url", "manifest_url", "base_url", "module", "disabled", "locked", "zone", "liveries"]
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
            if metadataKeys.contains(firstPart.lowercased()) {
                continue
            }

            var rawPath = firstPart.replacingOccurrences(of: "\\", with: "/")
            while rawPath.hasPrefix("/") {
                rawPath.removeFirst()
            }
            guard !rawPath.isEmpty else { continue }

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

    // MARK: - Remote Data Fetching & CRC Verification

    private func fetchTextContent(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
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
        guard let baseURLString = config.baseURL ?? config.remoteManifestURL else {
            await logHandler("[SkunkCrafts] No remote URL configured for \(config.name)")
            throw URLError(.badURL)
        }

        var base = baseURLString
        if base.hasSuffix("skunkcrafts_updater.cfg") {
            base = String(base.dropLast("skunkcrafts_updater.cfg".count))
        }
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else {
            throw URLError(.badURL)
        }

        await logHandler("[SkunkCrafts] Checking \(config.name) from \(baseURL.absoluteString)...")

        var localVersion = config.version
        if localVersion == nil, let cfgURL = findConfig(in: folderURL), let parsed = parseConfig(at: cfgURL, defaultName: config.name) {
            localVersion = parsed.version
        }

        let configFileName: String
        if let cfgURL = findConfig(in: folderURL) {
            configFileName = cfgURL.lastPathComponent
        } else {
            configFileName = "skunkcrafts_updater.cfg"
        }

        // 1. Fetch remote skunkcrafts_updater.cfg
        var remoteVersion: String? = nil
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
                if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "version" {
                    remoteVersion = parts[1].trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        await logHandler("[SkunkCrafts] Remote version: \(remoteVersion ?? "unknown")")

        // 2. Fetch remote whitelist (skunkcrafts_updater_whitelist.txt)
        var whitelistItems: [SkunkCraftsFileItem] = []
        let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
        if let whitelistText = try? await fetchTextContent(from: whitelistURL) {
            whitelistItems = parseWhitelist(content: whitelistText)
            await logHandler("[SkunkCrafts] Fetched skunkcrafts_updater_whitelist.txt (\(whitelistItems.count) entries)")
        }

        if !whitelistItems.contains(where: { $0.relativePath.lowercased() == configFileName.lowercased() }) {
            whitelistItems.append(SkunkCraftsFileItem(relativePath: configFileName, expectedCRC: nil, expectedSize: nil))
        }

        // 3. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: folderURL)
        let blacklistURL = baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt")
        if let blacklistText = try? await fetchTextContent(from: blacklistURL) {
            ignoredSet.formUnion(parseBlacklist(content: blacklistText))
            await logHandler("[SkunkCrafts] Fetched skunkcrafts_updater_blacklist.txt")
        }

        let latestVersion = remoteVersion ?? localVersion
        let versionMismatch = (remoteVersion != nil && localVersion != nil && remoteVersion != localVersion)
        if versionMismatch {
            let rVersion = remoteVersion!
            await logHandler("[SkunkCrafts] Version mismatch: Local '\(localVersion ?? "none")' vs Remote '\(rVersion)'. Marking addon for update.")
            return (rVersion, true, "Update available (\(rVersion))")
        }

        // 4. Compare local CRC vs distant CRC for all whitelist files (early exit on first mismatch)
        var count = 0
        for item in whitelistItems {
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
                await logHandler("[SkunkCrafts] Insecure path rejected in whitelist: \(item.relativePath)")
                continue
            }

            if !fileManager.fileExists(atPath: localFileURL.path) {
                await logHandler("[SkunkCrafts] Missing file: \(item.relativePath). Marking addon for update.")
                return (latestVersion, true, "Update available (modified files)")
            } else if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr) {
                // 0xFFFFFFFF (4294967295) and 0 are sentinel values in SkunkCrafts manifests for install-only / user config / cache files.
                // If they already exist on disk, their contents should not be checked or overwritten.
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
            } else if let expectedSize = item.expectedSize {
                if let attrs = try? fileManager.attributesOfItem(atPath: localFileURL.path),
                   let localSize = attrs[.size] as? Int64 {
                    if localSize != expectedSize {
                        await logHandler("[SkunkCrafts] Size mismatch for \(item.relativePath) (local: \(localSize), distant: \(expectedSize)). Marking addon for update.")
                        return (latestVersion, true, "Update available (modified files)")
                    }
                }
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
        guard let baseURLString = config.baseURL ?? config.remoteManifestURL else { return }
        var base = baseURLString
        if base.hasSuffix("skunkcrafts_updater.cfg") {
            base = String(base.dropLast("skunkcrafts_updater.cfg".count))
        }
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard let baseURL = URL(string: base) else { return }

        await logHandler("[SkunkCrafts] Starting update check for \(config.name)...")

        var localVersion = config.version
        if localVersion == nil, let cfgURL = findConfig(in: addonFolder), let parsed = parseConfig(at: cfgURL, defaultName: config.name) {
            localVersion = parsed.version
        }

        let configFileName: String
        if let cfgURL = findConfig(in: addonFolder) {
            configFileName = cfgURL.lastPathComponent
        } else {
            configFileName = "skunkcrafts_updater.cfg"
        }

        // 1. Fetch remote skunkcrafts_updater.cfg for version comparison
        var remoteVersion: String? = nil
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
                if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "version" {
                    remoteVersion = parts[1].trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // 2. Fetch remote whitelist
        var whitelistItems: [SkunkCraftsFileItem] = []
        let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
        if let whitelistText = try? await fetchTextContent(from: whitelistURL) {
            whitelistItems = parseWhitelist(content: whitelistText)
        }

        if !whitelistItems.contains(where: { $0.relativePath.lowercased() == configFileName.lowercased() }) {
            whitelistItems.append(SkunkCraftsFileItem(relativePath: configFileName, expectedCRC: nil, expectedSize: nil))
        }

        // 3. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: addonFolder)
        if let blacklistText = try? await fetchTextContent(from: baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt")) {
            ignoredSet.formUnion(parseBlacklist(content: blacklistText))
        }

        // 4. Filter files needing download
        var filesToDownload: [SkunkCraftsFileItem] = []
        var checkCount = 0
        for item in whitelistItems {
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
                await logHandler("[SkunkCrafts] Insecure path rejected in whitelist: \(item.relativePath)")
                continue
            }

            let fileExists = fileManager.fileExists(atPath: localFileURL.path)
            if !fileExists {
                await logHandler("[SkunkCrafts] Missing file: \(item.relativePath). Queuing for download.")
                filesToDownload.append(item)
            } else if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr) {
                // 0xFFFFFFFF (4294967295) and 0 are sentinel values in SkunkCrafts manifests for install-only / user config / cache files.
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
            } else if let expectedSize = item.expectedSize {
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

        guard !filesToDownload.isEmpty else {
            await logHandler("[SkunkCrafts] All whitelist files are already up to date.")
            await progressHandler("Up to date", 1.0)
            return
        }

        await logHandler("[SkunkCrafts] Downloading \(filesToDownload.count) file(s) needing update/repair out of \(whitelistItems.count) total files...")

        // 5. Download and write each file
        let totalFiles = filesToDownload.count
        for (index, item) in filesToDownload.enumerated() {
            let progress = Double(index) / Double(totalFiles)
            let filename = (item.relativePath as NSString).lastPathComponent
            await progressHandler("Downloading \(filename)...", progress)

            // Construct relative encoded URL
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

            let (tempDownloadedURL, response) = try await URLSession.shared.download(from: fileURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                await logHandler("[SkunkCrafts] Failed downloading \(item.relativePath): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                continue
            }

            if fileManager.fileExists(atPath: localDestination.path) {
                try? fileManager.removeItem(at: localDestination)
            }
            try fileManager.moveItem(at: tempDownloadedURL, to: localDestination)
        }

        await logHandler("[SkunkCrafts] Update completed successfully.")
        await progressHandler("Up to date", 1.0)
    }

    func fetchReleaseNotes(
        for addonFolder: URL,
        config: SkunkCraftsConfig,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> String? {
        if let baseURLString = config.baseURL ?? config.remoteManifestURL {
            var base = baseURLString
            if base.hasSuffix("skunkcrafts_updater.cfg") {
                base = String(base.dropLast("skunkcrafts_updater.cfg".count))
            }
            if !base.hasSuffix("/") {
                base += "/"
            }
            if let baseURL = URL(string: base) {
                await logHandler("[SkunkCrafts] Searching for changelog / release notes in remote manifest for \(config.name)...")

                let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
                if let whitelistText = try? await fetchTextContent(from: whitelistURL) {
                    let whitelistItems = parseWhitelist(content: whitelistText)
                    let candidatePaths = whitelistItems.map(\.relativePath)
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
            }
        }

        // Fallback to local file in addon folder
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
        let config = SkunkCraftsConfig(
            name: addon.name,
            version: addon.currentVersion,
            remoteManifestURL: addon.remoteManifestURL,
            baseURL: nil
        )
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
        let config = SkunkCraftsConfig(
            name: addon.name,
            version: addon.currentVersion,
            remoteManifestURL: addon.remoteManifestURL,
            baseURL: nil
        )
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
        let config = SkunkCraftsConfig(
            name: addon.name,
            version: addon.currentVersion,
            remoteManifestURL: addon.remoteManifestURL,
            baseURL: nil
        )
        return try await fetchReleaseNotes(for: addon.folderURL, config: config, logHandler: logHandler)
    }
}

