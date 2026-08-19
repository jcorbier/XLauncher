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

public struct DetectedNavdataItem: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { definition.id }
    public let definition: NavdataAddonDefinition
    public let targetURL: URL
    public var currentCycle: String?
    public var currentRevision: String?
    public var currentAirac: String?
    public var currentProvider: String?
    public var latestCycle: String?
    public var latestRevision: String?
    public var latestMasterfile: String?
    public var isInstalled: Bool
    public var isUpdateAvailable: Bool
    public var isUpdating: Bool = false
    public var statusMessage: String = "Up to date"
    public var progress: Double = 0.0
}

public struct NavdataBackupFileEntry: Codable, Equatable, Hashable, Sendable {
    public let relative_path: String
    public let size: Int64
    public let checksum: String?
}

public struct NavdataBackupVerification: Codable, Equatable, Hashable, Sendable {
    public let provider_name: String
    public let target_relative_path: String?
    public let cycle: String?
    public let airac: String?
    public let backup_time: String
    public let file_count: Int
    public let files: [NavdataBackupFileEntry]
}

public struct NavdataBackupItem: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { folderName }
    public let folderName: String
    public let folderURL: URL
    public let verification: NavdataBackupVerification

    public var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: verification.backup_time) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return verification.backup_time
    }
}

public final class NavdataScanner: Sendable {

    public init() { }

    /// Scans X-Plane 12 for the base simulator navdata and user-configured add-on mappings.
    public func scanAddons(
        xPlaneURL: URL,
        launcherDataFolder: URL? = nil,
        catalog: FMSCatalog? = nil
    ) -> [DetectedNavdataItem] {
        var results: [DetectedNavdataItem] = []
        var seenIds = Set<String>()

        // 1. Default: Always include X-Plane 12 Base Custom Data
        let xp12CatalogAddon = catalog?.addons.first(where: {
            $0.name.contains("X-Plane 12") && $0.mappings.contains(where: { $0.simulator == "XP12" })
        })

        let xp12Guid = xp12CatalogAddon?.guid ?? "17271467-ff15-4302-82a6-946b0ffe2aec"
        let xp12Name = xp12CatalogAddon?.name ?? "X-Plane 12 (Base Custom Data)"
        let xp12RelPath = "Custom Data"
        let xp12TargetURL = xPlaneURL.appendingPathComponent(xp12RelPath)
        let xp12Installed = FileManager.default.fileExists(atPath: xp12TargetURL.path)
        let xp12CycleInfo = xp12Installed ? readCycleInfo(at: xp12TargetURL) : nil

        let xp12LatestCycle = xp12CatalogAddon?.cycle.isEmpty == false ? xp12CatalogAddon!.cycle : (catalog?.cycle ?? "2608")
        let xp12LatestRevision = xp12CatalogAddon?.revision.isEmpty == false ? xp12CatalogAddon!.revision : "1"
        let xp12Masterfile = xp12CatalogAddon?.masterfile ?? "master_xplane12_\(xp12LatestCycle).zip"

        var xp12UpdateAvailable = false
        var xp12Status = xp12Installed ? "Installed" : "Ready to install"

        if let current = xp12CycleInfo?.cycle {
            if current != xp12LatestCycle {
                xp12UpdateAvailable = true
                xp12Status = "Update available (Cycle \(xp12LatestCycle))"
            } else {
                xp12Status = "Up to date (Cycle \(current))"
            }
        } else if xp12Installed {
            xp12UpdateAvailable = true
            xp12Status = "Cycle unknown (Latest: \(xp12LatestCycle))"
        } else {
            xp12UpdateAvailable = true
            xp12Status = "Ready to install (Cycle \(xp12LatestCycle))"
        }

        let xp12Def = NavdataAddonDefinition(
            id: xp12Guid,
            name: xp12Name,
            formatKey: "x-plane12",
            relativeTargetPath: xp12RelPath,
            masterfile: xp12Masterfile,
            isCustom: false
        )

        results.append(DetectedNavdataItem(
            definition: xp12Def,
            targetURL: xp12TargetURL,
            currentCycle: xp12CycleInfo?.cycle,
            currentRevision: xp12CycleInfo?.revision,
            currentAirac: xp12CycleInfo?.airac,
            currentProvider: xp12CycleInfo?.provider,
            latestCycle: xp12LatestCycle,
            latestRevision: xp12LatestRevision,
            latestMasterfile: xp12Masterfile,
            isInstalled: xp12Installed,
            isUpdateAvailable: xp12UpdateAvailable,
            isUpdating: false,
            statusMessage: xp12Status,
            progress: 0.0
        ))

        seenIds.insert(xp12Guid)

        // 2. Scan User Mappings (configured via Add Mapping)
        let customDefs = NavdataCatalog.loadCustomAddons()
        for def in customDefs {
            guard !seenIds.contains(def.id) else { continue }

            let catalogMatch = catalog?.addons.first(where: { $0.guid == def.id || $0.name == def.name })

            let targetURL: URL
            if def.relativeTargetPath.hasPrefix("/") {
                targetURL = URL(fileURLWithPath: def.relativeTargetPath)
            } else {
                targetURL = xPlaneURL.appendingPathComponent(def.relativeTargetPath)
            }

            let isInstalled = FileManager.default.fileExists(atPath: targetURL.path)
            let cycleInfo = isInstalled ? readCycleInfo(at: targetURL) : nil

            let latestCycle = catalogMatch?.cycle.isEmpty == false ? catalogMatch!.cycle : (catalog?.cycle)
            let latestRevision = catalogMatch?.revision.isEmpty == false ? catalogMatch!.revision : "1"
            let latestMasterfile = catalogMatch?.masterfile ?? def.masterfile

            var isUpdateAvailable = false
            var statusMessage = isInstalled ? "Installed" : "Not Installed"

            if let latest = latestCycle {
                if let current = cycleInfo?.cycle {
                    if current != latest {
                        isUpdateAvailable = true
                        statusMessage = "Update available (Cycle \(latest))"
                    } else {
                        statusMessage = "Up to date (Cycle \(current))"
                    }
                } else if isInstalled {
                    isUpdateAvailable = true
                    statusMessage = "Cycle unknown (Latest: \(latest))"
                } else {
                    isUpdateAvailable = true
                    statusMessage = "Ready to install (Cycle \(latest))"
                }
            }

            results.append(DetectedNavdataItem(
                definition: def,
                targetURL: targetURL,
                currentCycle: cycleInfo?.cycle,
                currentRevision: cycleInfo?.revision,
                currentAirac: cycleInfo?.airac,
                currentProvider: cycleInfo?.provider,
                latestCycle: latestCycle,
                latestRevision: latestRevision,
                latestMasterfile: latestMasterfile,
                isInstalled: isInstalled,
                isUpdateAvailable: isUpdateAvailable,
                isUpdating: false,
                statusMessage: statusMessage,
                progress: 0.0
            ))

            seenIds.insert(def.id)
        }

        return results
    }

    // MARK: - Suggested Path Computation

    /// Computes a suggested relative path for an add-on from `data.index`, checking if it is detected on disk.
    public func computeSuggestedPath(
        for addon: FMSAddonDefinition,
        xPlaneURL: URL?,
        launcherDataFolder: URL?
    ) -> String {
        guard let mapping = addon.mappings.first(where: { $0.simulator == "XP12" }) else {
            return ""
        }

        let defaultRelPath = sanitizeMappingPath(mapping.directoryPath)
        guard let xPlaneURL else { return defaultRelPath }

        let fileManager = FileManager.default

        // 1. Direct path check in X-Plane root
        let directSimURL = xPlaneURL.appendingPathComponent(defaultRelPath)
        if fileManager.fileExists(atPath: directSimURL.path) {
            return defaultRelPath
        }

        // 2. Direct path check in Central folder
        if let launcherDataFolder {
            let directCentralURL = launcherDataFolder.appendingPathComponent(defaultRelPath)
            if fileManager.fileExists(atPath: directCentralURL.path) {
                return defaultRelPath
            }
        }

        // 3. Search for specific .acf file in Aircraft directories
        var candidateRoots = [xPlaneURL.appendingPathComponent("Aircraft")]
        if let launcherDataFolder {
            candidateRoots.append(launcherDataFolder.appendingPathComponent("Aircraft"))
        }

        for search in mapping.searches {
            let filename = search.filename.trimmingCharacters(in: .whitespaces)
            guard filename.hasSuffix(".acf") else { continue }

            for rootURL in candidateRoots {
                guard fileManager.fileExists(atPath: rootURL.path) else { continue }

                if let foundFile = findFile(named: filename, in: rootURL, maxDepth: 4) {
                    let aircraftFolder = foundFile.deletingLastPathComponent()

                    let subfolder = (defaultRelPath as NSString).lastPathComponent
                    let targetFolder: URL
                    if subfolder.lowercased() == "nav-data" ||
                       subfolder.lowercased() == "navdata" ||
                       subfolder.lowercased() == "defaultdata" {
                        targetFolder = aircraftFolder.appendingPathComponent(subfolder)
                    } else {
                        targetFolder = aircraftFolder
                    }

                    var rel = targetFolder.path.replacingOccurrences(of: xPlaneURL.path, with: "")
                    while rel.hasPrefix("/") { rel.removeFirst() }
                    return rel
                }
            }
        }

        return defaultRelPath
    }

    private func findFile(named targetName: String, in directory: URL, maxDepth: Int) -> URL? {
        guard maxDepth > 0 else { return nil }
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        for item in contents {
            if item.lastPathComponent.lowercased() == targetName.lowercased() {
                return item
            }

            if let isDir = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true {
                if let found = findFile(named: targetName, in: item, maxDepth: maxDepth - 1) {
                    return found
                }
            }
        }

        return nil
    }

    // MARK: - Cycle Information Parsing

    /// Reads cycle information from `cycle_info.txt` or `cycle.json` in the specified folder.
    public func readCycleInfo(at folderURL: URL) -> (cycle: String?, revision: String?, airac: String?, provider: String?)? {
        let fileManager = FileManager.default

        let candidateTxtURLs = [
            folderURL.appendingPathComponent("cycle_info.txt"),
            folderURL.appendingPathComponent("navdata").appendingPathComponent("cycle_info.txt"),
            folderURL.appendingPathComponent("NavData").appendingPathComponent("cycle_info.txt"),
            folderURL.appendingPathComponent("fmc_data").appendingPathComponent("NavData").appendingPathComponent("cycle_info.txt")
        ]

        for txtURL in candidateTxtURLs {
            if fileManager.fileExists(atPath: txtURL.path),
               let text = try? String(contentsOf: txtURL, encoding: .utf8) {
                if let parsed = parseCycleInfoTxt(text) {
                    return parsed
                }
            }
        }

        let cycleJsonURL = folderURL.appendingPathComponent("cycle.json")
        if fileManager.fileExists(atPath: cycleJsonURL.path),
           let data = try? Data(contentsOf: cycleJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let cycle = json["cycle"] as? String
            let revision = json["revision"] as? String ?? "1"
            let airac = json["airac"] as? String
            let provider = json["name"] as? String ?? json["provider"] as? String ?? "Navigraph"
            return (cycle, revision, airac, provider)
        }

        return nil
    }

    /// Parses the key-value structure of `cycle_info.txt`.
    public func parseCycleInfoTxt(_ content: String) -> (cycle: String?, revision: String?, airac: String?, provider: String?)? {
        var cycle: String?
        var revision: String?
        var validRange: String?

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]

            if key.contains("airac cycle") || key == "cycle" {
                cycle = value
            } else if key == "version" || key == "revision" {
                revision = value
            } else if key.contains("valid") {
                validRange = value
            }
        }

        guard cycle != nil || validRange != nil else { return nil }
        return (cycle: cycle, revision: revision, airac: validRange, provider: "Navigraph")
    }

    // MARK: - Backups

    public func scanBackups(xPlaneURL: URL) -> [NavdataBackupItem] {
        let backupDir = xPlaneURL.appendingPathComponent("Custom Data").appendingPathComponent("Backup_Data")
        guard let subdirs = try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var backups: [NavdataBackupItem] = []
        for dir in subdirs {
            let verURL = dir.appendingPathComponent("verification.json")
            guard let data = try? Data(contentsOf: verURL),
                   let verification = try? JSONDecoder().decode(NavdataBackupVerification.self, from: data) else {
                continue
            }

            backups.append(NavdataBackupItem(
                folderName: dir.lastPathComponent,
                folderURL: dir,
                verification: verification
            ))
        }

        return backups.sorted { $0.verification.backup_time > $1.verification.backup_time }
    }

    public func sanitizeMappingPath(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "\\", with: "/")
        for prefix in ["[SIMROOT]/", "[XP12ROOT]/", "[XP11ROOT]/", "[XP10ROOT]/", "[SIMROOT]", "[XP12ROOT]", "[XP11ROOT]", "[XP10ROOT]"] {
            if p.starts(with: prefix) {
                p = String(p.dropFirst(prefix.count))
            }
        }
        while p.hasPrefix("/") {
            p = String(p.dropFirst())
        }
        return p
    }
}
