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

final class SkunkCraftsUpdaterService: Sendable {
    static let shared = SkunkCraftsUpdaterService()
    private var fileManager: FileManager { .default }

    // MARK: - Config Detection & Parsing

    func findConfig(in folderURL: URL) -> URL? {
        let skunkcraftsFiles = [
            "skunkcrafts_updater.cfg",
            "skunkcrafts_updater_beta.cfg",
            "skunkcrafts_updater.json",
            "skunkcrafts_updater_config.txt"
        ]
        for name in skunkcraftsFiles {
            let url = folderURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func parseConfig(at url: URL, defaultName: String) -> SkunkCraftsConfig? {
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

    func parseIgnoreFile(in folderURL: URL) -> Set<String> {
        let ignoreFileURL = folderURL.appendingPathComponent("skunkcrafts_updater_ignore.txt")
        guard let content = try? String(contentsOf: ignoreFileURL, encoding: .utf8) else {
            return []
        }
        return parseBlacklist(content: content)
    }

    func parseBlacklist(content: String) -> Set<String> {
        var paths = Set<String>()
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
            paths.insert(normalized)
        }
        return paths
    }

    func isIgnored(relativePath: String, ignoredSet: Set<String>) -> Bool {
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

    func parseWhitelist(content: String) -> [SkunkCraftsFileItem] {
        var items: [SkunkCraftsFileItem] = []
        let metadataKeys: Set<String> = ["name", "version", "build", "url", "manifest_url", "base_url", "module", "disabled", "locked", "zone", "liveries"]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.components(separatedBy: "|")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                if metadataKeys.contains(key) {
                    continue
                }
                let rawPath = parts[0].trimmingCharacters(in: .whitespaces)
                let path = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
                let crc = parts[1].trimmingCharacters(in: .whitespaces)
                let size = parts.count >= 3 ? Int64(parts[2].trimmingCharacters(in: .whitespaces)) : nil
                items.append(SkunkCraftsFileItem(relativePath: path, expectedCRC: crc, expectedSize: size))
            } else if parts.count == 1 && parts[0].contains(".") {
                let rawPath = parts[0].trimmingCharacters(in: .whitespaces)
                let path = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
                items.append(SkunkCraftsFileItem(relativePath: path, expectedCRC: nil, expectedSize: nil))
            }
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

    func parseCRC32(_ string: String) -> UInt32? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if let dec = UInt32(trimmed) {
            return dec
        }
        if let hex = UInt32(trimmed.replacingOccurrences(of: "0x", with: ""), radix: 16) {
            return hex
        }
        return nil
    }

    private func calculateCRC32UInt32(for url: URL) -> UInt32? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.withUnsafeBytes { ptr -> UInt32 in
            guard let baseAddress = ptr.baseAddress else { return 0 }
            return UInt32(zlib.crc32(0, baseAddress.assumingMemoryBound(to: Bytef.self), uInt(data.count)))
        }
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

        // 1. Fetch remote skunkcrafts_updater.cfg
        var remoteVersion: String? = nil
        let remoteConfigURL = baseURL.appendingPathComponent("skunkcrafts_updater.cfg")
        if let configContent = try? await fetchTextContent(from: remoteConfigURL) {
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

        if !whitelistItems.contains(where: { $0.relativePath.lowercased() == "skunkcrafts_updater.cfg" }) {
            whitelistItems.append(SkunkCraftsFileItem(relativePath: "skunkcrafts_updater.cfg", expectedCRC: nil, expectedSize: nil))
        }

        // 3. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: folderURL)
        let blacklistURL = baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt")
        if let blacklistText = try? await fetchTextContent(from: blacklistURL) {
            ignoredSet.formUnion(parseBlacklist(content: blacklistText))
            await logHandler("[SkunkCrafts] Fetched skunkcrafts_updater_blacklist.txt")
        }

        // 4. Compare local CRC vs distant CRC for all whitelist files
        var modifiedCount = 0
        for item in whitelistItems {
            if isIgnored(relativePath: item.relativePath, ignoredSet: ignoredSet) {
                await logHandler("[SkunkCrafts] Ignored file: \(item.relativePath)")
                continue
            }
            let localFileURL = folderURL.appendingPathComponent(item.relativePath)
            if !fileManager.fileExists(atPath: localFileURL.path) {
                modifiedCount += 1
                await logHandler("[SkunkCrafts] Missing file: \(item.relativePath)")
            } else if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr), let localCRC = calculateCRC32UInt32(for: localFileURL) {
                if localCRC != distantCRC {
                    modifiedCount += 1
                    await logHandler("[SkunkCrafts] CRC mismatch for \(item.relativePath) (local: \(localCRC), distant: \(distantCRC))")
                }
            }
        }

        let versionMismatch = (remoteVersion != nil && config.version != nil && remoteVersion != config.version)
        let isUpdateAvailable = versionMismatch || (modifiedCount > 0)
        let latestVersion = remoteVersion ?? config.version

        var statusMessage = "Up to date"
        if isUpdateAvailable {
            if let rVersion = remoteVersion, rVersion != config.version {
                if modifiedCount > 0 {
                    statusMessage = "Update available (\(rVersion) - \(modifiedCount) modified files)"
                } else {
                    statusMessage = "Update available (\(rVersion))"
                }
                await logHandler("[SkunkCrafts] Version mismatch: Local '\(config.version ?? "none")' vs Remote '\(rVersion)'")
            } else if modifiedCount > 0 {
                statusMessage = "Update available (\(modifiedCount) modified files)"
                await logHandler("[SkunkCrafts] \(modifiedCount) files modified or missing")
            } else {
                statusMessage = "Update available"
            }
        } else {
            await logHandler("[SkunkCrafts] \(config.name) is up to date.")
        }

        return (latestVersion, isUpdateAvailable, statusMessage)
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

        await logHandler("[SkunkCrafts] Starting update download for \(config.name)...")

        // 1. Fetch remote whitelist
        var whitelistItems: [SkunkCraftsFileItem] = []
        let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
        if let whitelistText = try? await fetchTextContent(from: whitelistURL) {
            whitelistItems = parseWhitelist(content: whitelistText)
        }

        if !whitelistItems.contains(where: { $0.relativePath.lowercased() == "skunkcrafts_updater.cfg" }) {
            whitelistItems.append(SkunkCraftsFileItem(relativePath: "skunkcrafts_updater.cfg", expectedCRC: nil, expectedSize: nil))
        }

        // 2. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: addonFolder)
        if let blacklistText = try? await fetchTextContent(from: baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt")) {
            ignoredSet.formUnion(parseBlacklist(content: blacklistText))
        }

        // 3. Filter files needing download
        var filesToDownload: [SkunkCraftsFileItem] = []
        for item in whitelistItems {
            if isIgnored(relativePath: item.relativePath, ignoredSet: ignoredSet) {
                await logHandler("[SkunkCrafts] Skipping ignored file: \(item.relativePath)")
                continue
            }

            let localFileURL = addonFolder.appendingPathComponent(item.relativePath)
            if !fileManager.fileExists(atPath: localFileURL.path) {
                filesToDownload.append(item)
            } else if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr), let localCRC = calculateCRC32UInt32(for: localFileURL) {
                if localCRC != distantCRC {
                    filesToDownload.append(item)
                }
            } else {
                filesToDownload.append(item)
            }
        }

        if filesToDownload.isEmpty {
            await logHandler("[SkunkCrafts] No files required download.")
            await progressHandler("Up to date", 1.0)
            return
        }

        let total = filesToDownload.count
        await logHandler("[SkunkCrafts] Downloading \(total) files from \(baseURL.absoluteString)...")
        for (index, item) in filesToDownload.enumerated() {
            let progress = Double(index + 1) / Double(total)
            let statusText = "Downloading (\(index + 1)/\(total)): \(item.relativePath)"
            await progressHandler(statusText, progress)

            let downloadURL = baseURL.appendingPathComponent(item.relativePath)
            await logHandler("[SkunkCrafts] Fetching \(downloadURL.absoluteString)...")

            let (fileData, response) = try await URLSession.shared.data(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await logHandler("[SkunkCrafts] Download failed for \(item.relativePath) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                continue
            }

            let destinationURL = addonFolder.appendingPathComponent(item.relativePath)
            let parentDir = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileData.write(to: destinationURL, options: .atomic)
            await logHandler("[SkunkCrafts] Replaced \(item.relativePath) (\(fileData.count) bytes)")
        }

        await logHandler("[SkunkCrafts] Update completed successfully.")
        await progressHandler("Up to date", 1.0)
    }
}
