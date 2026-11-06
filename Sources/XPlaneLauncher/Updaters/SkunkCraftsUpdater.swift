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

struct SkunkCraftsPackMember: Sendable, Equatable {
    let memberId: String
    let defaultFolder: String
    let depotURL: String
}

struct SkunkCraftsCRCCacheEntry: Sendable, Equatable {
    let size: Int64
    let mtime: Int64
    let crc: UInt32
}

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
    var mainName: String? = nil
    var packId: String? = nil
    var memberId: String? = nil
    var packName: String? = nil
    var packMembers: [SkunkCraftsPackMember] = []
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

    nonisolated func absorbBetaFiles(in folderURL: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return }
        let betaFiles = files.filter {
            let lower = $0.lowercased()
            return lower.hasPrefix("skunkcrafts_updater_beta") && lower.hasSuffix(".cfg")
        }
        guard !betaFiles.isEmpty else { return }

        let channelsDir = folderURL.appendingPathComponent("skunkcrafts/channels")
        try? FileManager.default.createDirectory(at: channelsDir, withIntermediateDirectories: true)
        let channelCfgURL = folderURL.appendingPathComponent("skunkcrafts/channel.cfg")
        let hasActiveCfg = FileManager.default.fileExists(atPath: channelCfgURL.path)

        for file in betaFiles {
            let fileURL = folderURL.appendingPathComponent(file)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            var chModule: String? = nil
            var chZone: String = "custom"
            var chName: String? = nil
            var chEnabled: Bool = true

            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.contains("|") ? trimmed.components(separatedBy: "|") : trimmed.components(separatedBy: "=")
                guard parts.count >= 2 else { continue }
                let k = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                if k == "module" || k == "url" || k == "base_url" {
                    chModule = v
                } else if k == "zone" {
                    chZone = v
                } else if k == "channel" {
                    chName = v
                } else if k == "enabled" {
                    chEnabled = (v.lowercased() == "true" || v == "1")
                }
            }

            guard let mod = chModule, !mod.isEmpty else {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }

            let effectiveName: String
            if let customName = chName, !customName.isEmpty {
                effectiveName = customName
            } else {
                let baseWithoutPrefix = String(file.dropFirst("skunkcrafts_updater_beta".count))
                var stem = String(baseWithoutPrefix.dropLast(".cfg".count))
                if stem.hasPrefix("_") { stem.removeFirst() }
                effectiveName = stem.isEmpty ? "beta" : stem
            }

            let targetChannelURL = channelsDir.appendingPathComponent("\(effectiveName).cfg")
            let channelContent = "channel|\(effectiveName)\nmodule|\(mod)\nzone|\(chZone)\n"
            try? channelContent.write(to: targetChannelURL, atomically: true, encoding: .utf8)

            if !hasActiveCfg && chEnabled {
                let act = "channel|\(effectiveName)\n"
                try? act.write(to: channelCfgURL, atomically: true, encoding: .utf8)
            }

            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    nonisolated func resolveChannel(channelName: String, in folderURL: URL) -> (module: String?, zone: String?)? {
        if channelName.lowercased() == "stable" { return nil }
        let channelCfgURL = folderURL.appendingPathComponent("skunkcrafts/channels/\(channelName).cfg")
        guard let content = try? String(contentsOf: channelCfgURL, encoding: .utf8) else {
            return nil
        }
        var mod: String? = nil
        var zone: String? = "custom"
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count >= 2 {
                let k = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                if k == "module" || k == "url" { mod = v }
                else if k == "zone" { zone = v }
            }
        }
        return (mod, zone)
    }

    // MARK: - Packs (Part 5)

    nonisolated func parsePackMembers(_ content: String) -> [SkunkCraftsPackMember] {
        var members: [SkunkCraftsPackMember] = []
        let entries = content.components(separatedBy: ";")
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 3 else { continue }
            let memberId = parts[0].trimmingCharacters(in: .whitespaces)
            let defaultFolder = parts[1].trimmingCharacters(in: .whitespaces)
            let depotURL = parts[2].trimmingCharacters(in: .whitespaces)

            guard !memberId.isEmpty, !defaultFolder.isEmpty, !depotURL.isEmpty else { continue }
            guard isPackPathAllowed(defaultFolder) else { continue }

            members.append(SkunkCraftsPackMember(
                memberId: memberId,
                defaultFolder: defaultFolder,
                depotURL: depotURL
            ))
        }
        return members
    }

    nonisolated func isPackPathAllowed(_ relPath: String) -> Bool {
        let trimmed = relPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("\\") else {
            return false
        }
        var norm = trimmed.replacingOccurrences(of: "\\", with: "/")
        while norm.hasSuffix("/") { norm.removeLast() }
        guard !norm.isEmpty, !norm.contains(".."), !norm.contains(":"), norm.contains("/") else {
            return false
        }
        let lower = norm.lowercased()
        let forbidden = [
            "resources/default", "resources/bitmaps", "resources/dlls", "resources/sounds",
            "resources/cif", "resources/fonts", "resources/shaders", "resources/skins",
            "global scenery", "output", "custom data"
        ]
        for forb in forbidden {
            if lower == forb || lower.hasPrefix(forb + "/") {
                return false
            }
        }
        return true
    }

    nonisolated func createPackMemberFolder(
        in xplaneRoot: URL,
        decl: SkunkCraftsPackMember,
        packId: String,
        packName: String?
    ) throws -> URL {
        guard isPackPathAllowed(decl.defaultFolder) else {
            throw AppError.invalidConfig("Disallowed pack path: \(decl.defaultFolder)")
        }
        let folderURL = xplaneRoot.appendingPathComponent(decl.defaultFolder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let cfgURL = folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
        var content = "# created by SkunkCrafts Updater for pack member; the first update fills the folder\n"
        content += "name|\(decl.memberId)\n"
        content += "module|\(decl.depotURL)\n"
        content += "version|none\n"
        content += "zone|custom\n"
        content += "disabled|false\n"
        content += "pack|\(packId)\n"
        content += "member|\(decl.memberId)\n"
        if let pName = packName, !pName.isEmpty, pName != packId {
            content += "pack_name|\(pName)\n"
        }
        try content.write(to: cfgURL, atomically: true, encoding: .utf8)
        return folderURL
    }

    // MARK: - CRC Cache (skunkcrafts/crc_cache.txt)

    nonisolated func loadCRCCache(for addonFolder: URL) -> [String: SkunkCraftsCRCCacheEntry] {
        let cacheFileURL = addonFolder.appendingPathComponent("skunkcrafts/crc_cache.txt")
        guard let content = try? String(contentsOf: cacheFileURL, encoding: .utf8) else {
            return [:]
        }
        var cache: [String: SkunkCraftsCRCCacheEntry] = [:]
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "|")
            guard parts.count >= 4 else { continue }
            let relPath = parts[0]
            guard let size = Int64(parts[1]),
                  let mtime = Int64(parts[2]),
                  let crc = UInt32(parts[3]) else { continue }
            cache[relPath] = SkunkCraftsCRCCacheEntry(size: size, mtime: mtime, crc: crc)
        }
        return cache
    }

    nonisolated func saveCRCCache(_ cache: [String: SkunkCraftsCRCCacheEntry], for addonFolder: URL) {
        let skunkDir = addonFolder.appendingPathComponent("skunkcrafts")
        try? FileManager.default.createDirectory(at: skunkDir, withIntermediateDirectories: true)
        let cacheFileURL = skunkDir.appendingPathComponent("crc_cache.txt")
        var content = ""
        for (relPath, entry) in cache {
            content += "\(relPath)|\(entry.size)|\(entry.mtime)|\(entry.crc)\n"
        }
        try? content.write(to: cacheFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - In-Place Local Configuration Updating

    nonisolated func updateLocalConfigFile(
        at url: URL,
        remoteName: String?,
        remoteVersion: String?,
        remoteModule: String?,
        remoteZone: String?,
        mainName: String?,
        packKeys: [String: String] = [:],
        isStable: Bool
    ) throws {
        var updates: [String: String] = [:]
        if let remoteName, !remoteName.isEmpty { updates["name"] = remoteName }
        if let remoteVersion, !remoteVersion.isEmpty { updates["version"] = remoteVersion }
        if isStable {
            if let remoteModule, !remoteModule.isEmpty { updates["module"] = remoteModule }
            if let remoteZone, !remoteZone.isEmpty { updates["zone"] = remoteZone }
        }
        if let mainName, !mainName.isEmpty, mainName.lowercased() != "stable" {
            updates["main_name"] = mainName
        }
        for (k, v) in packKeys {
            updates[k] = v
        }

        guard let existingContent = try? String(contentsOf: url, encoding: .utf8) else {
            var newContent = ""
            for (k, v) in updates {
                newContent += "\(k)|\(v)\n"
            }
            try newContent.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let lines = existingContent.components(separatedBy: .newlines)
        var updatedLines: [String] = []
        var appliedKeys = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                updatedLines.append(line)
                continue
            }
            let parts = trimmed.contains("|") ? trimmed.components(separatedBy: "|") : trimmed.components(separatedBy: "=")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                if let newVal = updates[key] {
                    updatedLines.append("\(key)|\(newVal)")
                    appliedKeys.insert(key)
                    continue
                }
            }
            updatedLines.append(line)
        }

        for (key, val) in updates {
            if !appliedKeys.contains(key) {
                updatedLines.append("\(key)|\(val)")
            }
        }

        let newContent = updatedLines.joined(separator: "\n")
        try newContent.write(to: url, atomically: true, encoding: .utf8)
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

    nonisolated func parseConfig(at url: URL, defaultName: String, overrideChannel: String? = nil) -> SkunkCraftsConfig? {
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
        var mainName: String? = nil
        var packId: String? = nil
        var memberId: String? = nil
        var packName: String? = nil
        var packMembers: [SkunkCraftsPackMember] = []
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
            } else if key == "main_name" {
                if val.lowercased() != "stable" {
                    mainName = val
                }
            } else if key == "pack" {
                packId = val
            } else if key == "member" {
                memberId = val
            } else if key == "pack_name" {
                packName = val
            } else if key == "pack_members" {
                packMembers = parsePackMembers(val)
            } else if key.hasPrefix("channel.") {
                let sub = String(key.dropFirst("channel.".count))
                let subParts = sub.components(separatedBy: ".")
                if subParts.count == 1 {
                    let ch = subParts[0]
                    if ch.lowercased() != "stable" && ch.lowercased() != "main" && !ch.hasSuffix(".module") && !ch.hasSuffix(".zone") {
                        channelModules[ch] = val
                    }
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

        // Absorb any legacy or tester beta files at the root into skunkcrafts/channels/
        absorbBetaFiles(in: folderURL)

        // Discover available channels
        var availableChannels = Set<String>(["stable"])
        for ch in channelModules.keys {
            availableChannels.insert(ch)
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

        // Check for legacy beta files at the root (fallback if any remain)
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

        if let override = overrideChannel, !override.isEmpty {
            activeChannel = override.lowercased()
            availableChannels.insert(activeChannel)
        }

        let isBeta = url.lastPathComponent.lowercased().contains("beta") || activeChannel.contains("beta")

        // If non-stable active channel is selected and has custom module/zone, override
        if activeChannel != "stable" {
            if let chModule = channelModules[activeChannel] {
                remoteURL = chModule
                baseURL = chModule
            } else if let ch = resolveChannel(channelName: activeChannel, in: folderURL) {
                if let m = ch.module {
                    remoteURL = m
                    baseURL = m
                }
                if let z = ch.zone {
                    zone = z
                }
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
            liveriesEnabled: liveriesEnabled,
            mainName: mainName,
            packId: packId,
            memberId: memberId,
            packName: packName,
            packMembers: packMembers
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

    private func executeFetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        URLCache.shared.removeCachedResponse(for: request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw URLError(.fileDoesNotExist)
            }
            throw URLError(.badServerResponse)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        let trimmed = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") {
            throw URLError(.cannotParseResponse)
        }
        return content
    }

    private func fetchTextContent(
        from url: URL,
        queryParam: (key: String, value: String)? = nil
    ) async throws -> String {
        var targetURL = url
        if let (k, v) = queryParam {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                var queryItems = components.queryItems ?? []
                queryItems.append(URLQueryItem(name: k, value: v))
                components.queryItems = queryItems
                if let u = components.url {
                    targetURL = u
                }
            }
        }

        do {
            return try await executeFetchText(targetURL)
        } catch {
            if queryParam != nil {
                return try await executeFetchText(url)
            }
            throw error
        }
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
        var effectiveBaseURLString = config.baseURL ?? config.remoteManifestURL
        var effectiveZone = config.zone

        if config.activeChannel != "stable" {
            if let ch = resolveChannel(channelName: config.activeChannel, in: folderURL) {
                if let m = ch.module { effectiveBaseURLString = m }
                if let z = ch.zone { effectiveZone = z }
            }
        }

        guard let baseURL = resolveBaseURL(module: effectiveBaseURLString, zone: effectiveZone) else {
            await logHandler("[SkunkCrafts] No valid remote URL configured for \(config.name)")
            throw URLError(.badURL)
        }

        let channelLabel = (config.isBetaEnabled || config.activeChannel.lowercased() != "stable") ? " (\(config.activeChannel.capitalized) Channel)" : ""
        await logHandler("[SkunkCrafts] Checking \(config.name)\(channelLabel) from \(baseURL.absoluteString)...")

        var localVersion = config.version
        let standardLocalConfigURL = folderURL.appendingPathComponent("skunkcrafts_updater.cfg")
        if localVersion == nil, let parsed = parseConfig(at: standardLocalConfigURL, defaultName: config.name) {
            localVersion = parsed.version
        }

        // 1. Fetch remote config (always skunkcrafts_updater.cfg on the depot)
        var remoteVersion: String? = nil
        var remoteProtocol: Int? = nil
        var remoteManifestName: String? = nil
        var remoteLocked: Bool = false

        let remoteConfigURL = baseURL.appendingPathComponent("skunkcrafts_updater.cfg")
        let timestamp = "\(Int(Date().timeIntervalSince1970))"
        var configContent: String? = try? await fetchTextContent(from: remoteConfigURL, queryParam: ("t", timestamp))

        // Client 4.2.3+ fallback: if main depot 404s, fall back to first public channel
        if configContent == nil && config.activeChannel == "stable" {
            if let firstPublic = config.availableChannels.first(where: { $0.lowercased() != "stable" }),
               let fallbackURL = resolveBaseURL(module: firstPublic, zone: nil) ?? resolveBaseURL(module: config.baseURL, zone: nil) {
                await logHandler("[SkunkCrafts] Main depot has no release yet (HTTP 404), checking public channel '\(firstPublic)'")
                configContent = try? await fetchTextContent(from: fallbackURL.appendingPathComponent("skunkcrafts_updater.cfg"), queryParam: ("t", timestamp))
            }
        }

        if let configContent = configContent {
            let lines = configContent.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.contains("|") ? trimmed.components(separatedBy: "|") : trimmed.components(separatedBy: "=")
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

        // 2. Fetch remote manifest/whitelist
        var manifestItems: [SkunkCraftsFileItem] = []
        let versionQuery: (key: String, value: String)? = remoteVersion != nil ? ("v", remoteVersion!) : nil

        if effectiveProtocol >= 2 {
            let manifestName = remoteManifestName ?? config.manifestFileName ?? "skunkcrafts_updater_manifest.txt"
            let manifestURL = baseURL.appendingPathComponent(manifestName)
            if let manifestText = try? await fetchTextContent(from: manifestURL, queryParam: versionQuery) {
                manifestItems = parseManifest(content: manifestText)
                await logHandler("[SkunkCrafts] Fetched \(manifestName) (\(manifestItems.count) entries, protocol 2)")
            }
        } else {
            let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
            if let whitelistText = try? await fetchTextContent(from: whitelistURL, queryParam: versionQuery) {
                manifestItems = parseWhitelist(content: whitelistText)
                await logHandler("[SkunkCrafts] Fetched skunkcrafts_updater_whitelist.txt (\(manifestItems.count) entries, protocol 1)")
            }
            let sizesURL = baseURL.appendingPathComponent("skunkcrafts_updater_sizeslist.txt")
            if let sizesText = try? await fetchTextContent(from: sizesURL, queryParam: versionQuery) {
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

        // Exclude client files from remote checks
        manifestItems = manifestItems.filter { !isProtectedClientFile($0.relativePath) }

        // 3. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: folderURL)
        var blacklistedPaths: Set<String> = []
        let blacklistURL = baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt")
        if let blacklistText = try? await fetchTextContent(from: blacklistURL, queryParam: versionQuery) {
            blacklistedPaths = parseBlacklist(content: blacklistText)
            blacklistedPaths = blacklistedPaths.filter { !isProtectedClientFile($0) }
            ignoredSet.formUnion(blacklistedPaths)
            await logHandler("[SkunkCrafts] Fetched skunkcrafts_updater_blacklist.txt (\(blacklistedPaths.count) entries)")
        }

        // 4. Compare local files against manifest using CRC cache
        var crcCache = loadCRCCache(for: folderURL)
        var modifiedCount = 0
        var count = 0

        for item in manifestItems {
            count += 1
            if count % 50 == 0 {
                await Task.yield()
            }

            if !config.liveriesEnabled && item.relativePath.lowercased().hasPrefix("liveries/") {
                continue
            }

            if isIgnored(relativePath: item.relativePath, ignoredSet: ignoredSet) {
                continue
            }

            let localFileURL: URL
            do {
                localFileURL = try PathSecurity.validateSubpath(relativePath: item.relativePath, within: folderURL)
            } catch {
                await logHandler("[SkunkCrafts] Insecure path rejected in manifest: \(item.relativePath)")
                continue
            }

            guard fileManager.fileExists(atPath: localFileURL.path) else {
                modifiedCount += 1
                continue
            }

            let attrs = try? fileManager.attributesOfItem(atPath: localFileURL.path)
            let fileSize = (attrs?[.size] as? Int64) ?? 0
            let modDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            let mtime = Int64(modDate.timeIntervalSince1970)

            if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr) {
                if distantCRC != 0xFFFFFFFF && distantCRC != 0 {
                    var localCRC: UInt32? = nil
                    if let cached = crcCache[item.relativePath], cached.size == fileSize, cached.mtime == mtime {
                        localCRC = cached.crc
                    } else if let computed = calculateCRC32UInt32(for: localFileURL) {
                        localCRC = computed
                        crcCache[item.relativePath] = SkunkCraftsCRCCacheEntry(size: fileSize, mtime: mtime, crc: computed)
                    }

                    if let localCRC = localCRC {
                        if localCRC != distantCRC {
                            modifiedCount += 1
                        }
                    } else {
                        modifiedCount += 1
                    }
                }
            } else if let expectedSize = item.expectedSize, expectedSize >= 0 {
                if fileSize != expectedSize {
                    modifiedCount += 1
                }
            }
        }

        // 5. Check if any local file is blacklisted
        for blacklisted in blacklistedPaths {
            if isProtectedClientFile(blacklisted) { continue }
            if let localURL = try? PathSecurity.validateSubpath(relativePath: blacklisted, within: folderURL),
               fileManager.fileExists(atPath: localURL.path) {
                modifiedCount += 1
            }
        }

        saveCRCCache(crcCache, for: folderURL)

        let latestVersion = remoteVersion ?? localVersion
        let sameVersion = (localVersion != nil && remoteVersion != nil && localVersion == remoteVersion)

        if modifiedCount == 0 {
            if sameVersion || remoteVersion == nil || localVersion == nil {
                await logHandler("[SkunkCrafts] \(config.name) is up to date.")
                return (latestVersion, false, "Up to date")
            } else {
                await logHandler("[SkunkCrafts] All files match, but version differs (Local: '\(localVersion!)' vs Remote: '\(remoteVersion!)').")
                return (latestVersion, true, "Version mismatch (Local: \(localVersion!), Remote: \(remoteVersion!))")
            }
        } else if sameVersion {
            await logHandler("[SkunkCrafts] \(modifiedCount) file(s) modified/missing on version '\(localVersion!)'. Repair available.")
            return (latestVersion, true, "Repair available (\(modifiedCount) file(s) modified)")
        } else {
            await logHandler("[SkunkCrafts] Update available: \(remoteVersion ?? "new version") (\(modifiedCount) file(s) to update).")
            return (latestVersion, true, "Update available (\(remoteVersion ?? ""))")
        }
    }

    func downloadAndApplyUpdates(
        for addonFolder: URL,
        config: SkunkCraftsConfig,
        logHandler: @Sendable @escaping @MainActor (String) -> Void = { _ in },
        progressHandler: @Sendable @escaping @MainActor (String, Double) -> Void
    ) async throws {
        var effectiveBaseURLString = config.baseURL ?? config.remoteManifestURL
        var effectiveZone = config.zone

        if config.activeChannel != "stable" {
            if let ch = resolveChannel(channelName: config.activeChannel, in: addonFolder) {
                if let m = ch.module { effectiveBaseURLString = m }
                if let z = ch.zone { effectiveZone = z }
            }
        }

        guard let baseURL = resolveBaseURL(module: effectiveBaseURLString, zone: effectiveZone) else { return }

        let channelLabel = (config.isBetaEnabled || config.activeChannel.lowercased() != "stable") ? " (\(config.activeChannel.capitalized) Channel)" : ""
        await logHandler("[SkunkCrafts] Starting update check for \(config.name)\(channelLabel)...")

        var localVersion = config.version
        let standardLocalConfigURL = addonFolder.appendingPathComponent("skunkcrafts_updater.cfg")
        if localVersion == nil, let parsed = parseConfig(at: standardLocalConfigURL, defaultName: config.name) {
            localVersion = parsed.version
        }

        // 1. Fetch remote config (always skunkcrafts_updater.cfg)
        var remoteVersion: String? = nil
        var remoteProtocol: Int? = nil
        var remoteManifestName: String? = nil
        var remoteName: String? = nil
        var remoteModule: String? = nil
        var remoteZone: String? = nil
        var remoteMainName: String? = nil
        var remotePackKeys: [String: String] = [:]

        let remoteConfigURL = baseURL.appendingPathComponent("skunkcrafts_updater.cfg")
        let timestamp = "\(Int(Date().timeIntervalSince1970))"
        var configContent: String? = try? await fetchTextContent(from: remoteConfigURL, queryParam: ("t", timestamp))

        if configContent == nil && config.activeChannel == "stable" {
            if let firstPublic = config.availableChannels.first(where: { $0.lowercased() != "stable" }),
               let fallbackURL = resolveBaseURL(module: firstPublic, zone: nil) ?? resolveBaseURL(module: config.baseURL, zone: nil) {
                await logHandler("[SkunkCrafts] Main depot has no release yet; fetching config from public channel '\(firstPublic)'")
                configContent = try? await fetchTextContent(from: fallbackURL.appendingPathComponent("skunkcrafts_updater.cfg"), queryParam: ("t", timestamp))
            }
        }

        if let configContent = configContent {
            let lines = configContent.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.contains("|") ? trimmed.components(separatedBy: "|") : trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let v = parts[1].trimmingCharacters(in: .whitespaces)
                    if k == "version" || k == "build" {
                        remoteVersion = v
                    } else if k == "name" {
                        remoteName = v
                    } else if k == "module" || k == "url" || k == "base_url" {
                        remoteModule = v
                    } else if k == "zone" {
                        remoteZone = v
                    } else if k == "protocol" {
                        if let p = Int(v) { remoteProtocol = p }
                    } else if k == "manifest" {
                        remoteManifestName = v
                    } else if k == "main_name" {
                        remoteMainName = v
                    } else if ["pack", "member", "pack_name", "pack_members"].contains(k) {
                        remotePackKeys[k] = v
                    }
                }
            }
        }

        let effectiveProtocol = remoteProtocol ?? config.protocolLevel
        let versionQuery: (key: String, value: String)? = remoteVersion != nil ? ("v", remoteVersion!) : nil

        // 2. Fetch remote manifest
        var manifestItems: [SkunkCraftsFileItem] = []
        if effectiveProtocol >= 2 {
            let manifestName = remoteManifestName ?? config.manifestFileName ?? "skunkcrafts_updater_manifest.txt"
            let manifestURL = baseURL.appendingPathComponent(manifestName)
            if let manifestText = try? await fetchTextContent(from: manifestURL, queryParam: versionQuery) {
                manifestItems = parseManifest(content: manifestText)
            }
        } else {
            let whitelistURL = baseURL.appendingPathComponent("skunkcrafts_updater_whitelist.txt")
            if let whitelistText = try? await fetchTextContent(from: whitelistURL, queryParam: versionQuery) {
                manifestItems = parseWhitelist(content: whitelistText)
            }
            let sizesURL = baseURL.appendingPathComponent("skunkcrafts_updater_sizeslist.txt")
            if let sizesText = try? await fetchTextContent(from: sizesURL, queryParam: versionQuery) {
                let sizes = parseSizesList(content: sizesText)
                manifestItems = manifestItems.map { item in
                    if let s = sizes[item.relativePath] {
                        return SkunkCraftsFileItem(relativePath: item.relativePath, expectedCRC: item.expectedCRC, expectedSize: s)
                    }
                    return item
                }
            }
        }

        // Never download or check client files from remote depot
        manifestItems = manifestItems.filter { !isProtectedClientFile($0.relativePath) }

        // 3. Fetch remote blacklist & read local ignore
        var ignoredSet = parseIgnoreFile(in: addonFolder)
        var blacklistedPaths: Set<String> = []
        if let blacklistText = try? await fetchTextContent(from: baseURL.appendingPathComponent("skunkcrafts_updater_blacklist.txt"), queryParam: versionQuery) {
            blacklistedPaths = parseBlacklist(content: blacklistText)
            blacklistedPaths = blacklistedPaths.filter { !isProtectedClientFile($0) }
            ignoredSet.formUnion(blacklistedPaths)
        }

        // 4. Filter files needing download using CRC cache
        var crcCache = loadCRCCache(for: addonFolder)
        var filesToDownload: [SkunkCraftsFileItem] = []
        var checkCount = 0

        for item in manifestItems {
            checkCount += 1
            if checkCount % 50 == 0 {
                await Task.yield()
            }

            if !config.liveriesEnabled && item.relativePath.lowercased().hasPrefix("liveries/") {
                continue
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
            } else {
                let attrs = try? fileManager.attributesOfItem(atPath: localFileURL.path)
                let fileSize = (attrs?[.size] as? Int64) ?? 0
                let modDate = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                let mtime = Int64(modDate.timeIntervalSince1970)

                if let expectedCRCStr = item.expectedCRC, let distantCRC = parseCRC32(expectedCRCStr) {
                    if distantCRC != 0xFFFFFFFF && distantCRC != 0 {
                        var localCRC: UInt32? = nil
                        if let cached = crcCache[item.relativePath], cached.size == fileSize, cached.mtime == mtime {
                            localCRC = cached.crc
                        } else if let computed = calculateCRC32UInt32(for: localFileURL) {
                            localCRC = computed
                            crcCache[item.relativePath] = SkunkCraftsCRCCacheEntry(size: fileSize, mtime: mtime, crc: computed)
                        }

                        if localCRC != distantCRC {
                            await logHandler("[SkunkCrafts] CRC mismatch for \(item.relativePath). Queuing for download.")
                            filesToDownload.append(item)
                        }
                    }
                } else if let expectedSize = item.expectedSize, expectedSize >= 0 {
                    if fileSize != expectedSize {
                        await logHandler("[SkunkCrafts] Size mismatch for \(item.relativePath). Queuing for download.")
                        filesToDownload.append(item)
                    }
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
            // If files match but remoteVersion differs, update local configuration version in place
            if let rVer = remoteVersion, localVersion != rVer {
                try? updateLocalConfigFile(
                    at: standardLocalConfigURL,
                    remoteName: remoteName,
                    remoteVersion: rVer,
                    remoteModule: remoteModule,
                    remoteZone: remoteZone,
                    mainName: remoteMainName,
                    packKeys: remotePackKeys,
                    isStable: config.activeChannel == "stable"
                )
                await logHandler("[SkunkCrafts] Local configuration version updated to \(rVer).")
            }
            await logHandler("[SkunkCrafts] All files are already up to date.")
            await progressHandler("Up to date", 1.0)
            return
        }

        // 6. Delete blacklisted files first
        for file in filesToDelete {
            if let localURL = try? PathSecurity.validateSubpath(relativePath: file, within: addonFolder) {
                try? fileManager.removeItem(at: localURL)
                crcCache.removeValue(forKey: file)
                await logHandler("[SkunkCrafts] Deleted blacklisted file: \(file)")
            }
        }

        if !filesToDownload.isEmpty {
            await logHandler("[SkunkCrafts] Downloading \(filesToDownload.count) file(s) needing update/repair out of \(manifestItems.count) total files...")
        }

        // 7. Download each file
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

            // Update CRC cache
            if let computedCRC = calculateCRC32UInt32(for: localDestination) {
                let attrs = try? fileManager.attributesOfItem(atPath: localDestination.path)
                let dSize = (attrs?[.size] as? Int64) ?? 0
                let dMod = (attrs?[.modificationDate] as? Date) ?? Date()
                crcCache[item.relativePath] = SkunkCraftsCRCCacheEntry(size: dSize, mtime: Int64(dMod.timeIntervalSince1970), crc: computedCRC)
            }
        }

        // 8. Update local configuration in place (never replace whole file)
        try? updateLocalConfigFile(
            at: standardLocalConfigURL,
            remoteName: remoteName,
            remoteVersion: remoteVersion,
            remoteModule: remoteModule,
            remoteZone: remoteZone,
            mainName: remoteMainName,
            packKeys: remotePackKeys,
            isStable: config.activeChannel == "stable"
        )

        // 9. Save CRC cache
        saveCRCCache(crcCache, for: addonFolder)

        // 10. Clean up early 4.0-beta leftover files if present
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
               !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return content
            }
            let localURL = addonFolder.appendingPathComponent(changelog)
            if let content = try? String(contentsOf: localURL, encoding: .utf8),
               !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return content
            }
        }

        if let readme = config.readmePath, !readme.isEmpty {
            if let baseURL,
               let encoded = readme.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let remoteURL = URL(string: encoded, relativeTo: baseURL),
               let content = try? await fetchTextContent(from: remoteURL),
               !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return content
            }
            let localURL = addonFolder.appendingPathComponent(readme)
            if let content = try? String(contentsOf: localURL, encoding: .utf8),
               !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
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
                   !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    return content
                }
            }
        }

        // 3. Fallback to local file in addon folder
        if let localURL = ChangelogFinder.findLocalChangelog(in: addonFolder),
           let content = try? String(contentsOf: localURL, encoding: .utf8),
           !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
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
