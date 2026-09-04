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

final class DiskUsageService: Sendable {
    static let shared = DiskUsageService()

    private var fileManager: FileManager { FileManager.default }

    init() {}

    // MARK: - Disk Usage Analysis

    func analyzeDiskUsage(
        xPlanePath: URL?,
        storagePools: [StoragePool],
        profiles: [PluginProfile],
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) async -> DiskUsageSummary {
        var items: [DiskUsageItem] = []

        // Collect all referenced folder names across all profiles to help identify orphans
        var profileReferencedFolders: Set<String> = []
        for profile in profiles {
            profileReferencedFolders.formUnion(profile.pluginFolderNames)
            profileReferencedFolders.formUnion(profile.sceneryFolderNames)
            profileReferencedFolders.formUnion(profile.aircraftFolderNames)
            profileReferencedFolders.formUnion(profile.luaScriptFolderNames)
        }

        // Active symlinks in primary X-Plane
        var primaryActiveSymlinks: Set<String> = []
        if let xp = xPlanePath {
            let sceneryDir = xp.appendingPathComponent("Custom Scenery")
            let pluginsDir = xp.appendingPathComponent("Resources/plugins")
            let aircraftDir = xp.appendingPathComponent("Aircraft")
            let scriptsDir = xp.appendingPathComponent("Resources/plugins/FlyWithLua/Scripts")

            for dir in [sceneryDir, pluginsDir, aircraftDir, scriptsDir] {
                if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                    for item in contents {
                        if let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                            primaryActiveSymlinks.insert(item.lastPathComponent)
                        }
                    }
                }
            }
        }

        // Total scan stages for progress calculation
        let totalSteps = 1.0 + Double(storagePools.count) + 1.0 // 1 for primary sim, N for pools, 1 for post-processing
        var currentStep = 0.0

        // 1. Scan Primary X-Plane Installation
        if let xp = xPlanePath, fileManager.fileExists(atPath: xp.path) {
            progress?(currentStep / totalSteps, "Scanning primary simulator installation...")
            let primaryItems = scanPrimaryInstallation(
                xPlanePath: xp,
                profileReferencedFolders: profileReferencedFolders
            )
            items.append(contentsOf: primaryItems)
        }
        currentStep += 1.0

        // 2. Scan Configured Storage Pools
        for pool in storagePools {
            guard pool.isOnline else {
                currentStep += 1.0
                continue
            }

            progress?(currentStep / totalSteps, "Scanning storage pool: \(pool.name)...")
            let poolItems = scanStoragePool(
                pool: pool,
                profileReferencedFolders: profileReferencedFolders,
                primaryActiveSymlinks: primaryActiveSymlinks
            )
            items.append(contentsOf: poolItems)
            currentStep += 1.0
        }

        // 3. Summarize & Aggregate
        progress?(0.95, "Compiling storage metrics...")

        var totalBytes: UInt64 = 0
        var totalFiles: Int = 0
        var categorySizes: [AddonStorageCategory: UInt64] = [:]
        var locationSizes: [String: UInt64] = [:]
        var cacheItems: [DiskUsageItem] = []
        var orphanItems: [DiskUsageItem] = []

        for cat in AddonStorageCategory.allCases {
            categorySizes[cat] = 0
        }

        for item in items {
            totalBytes += item.sizeBytes
            totalFiles += item.fileCount
            categorySizes[item.category, default: 0] += item.sizeBytes
            locationSizes[item.locationName, default: 0] += item.sizeBytes

            if item.isCache {
                cacheItems.append(item)
            }
            if item.isOrphan {
                orphanItems.append(item)
            }
        }

        // Sort items by size descending to isolate largest space hogs
        let sortedItems = items.sorted { $0.sizeBytes > $1.sizeBytes }
        let topSpaceHogs = Array(sortedItems.prefix(25))

        progress?(1.0, "Scan complete")

        return DiskUsageSummary(
            totalBytes: totalBytes,
            totalFiles: totalFiles,
            items: sortedItems,
            categorySizes: categorySizes,
            locationSizes: locationSizes,
            topSpaceHogs: topSpaceHogs,
            cacheItems: cacheItems.sorted { $0.sizeBytes > $1.sizeBytes },
            orphanItems: orphanItems.sorted { $0.sizeBytes > $1.sizeBytes }
        )
    }

    // MARK: - Primary Installation Scanner

    private func scanPrimaryInstallation(
        xPlanePath: URL,
        profileReferencedFolders: Set<String>
    ) -> [DiskUsageItem] {
        var items: [DiskUsageItem] = []
        let locName = "Primary Simulator (\(xPlanePath.lastPathComponent))"

        // 1. Custom Scenery (Ignore symlinks to avoid double-counting storage pools)
        let customScenery = xPlanePath.appendingPathComponent("Custom Scenery")
        if let entries = try? fileManager.contentsOfDirectory(at: customScenery, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries {
                if isSymbolicLink(entry) { continue }
                guard isDirectory(entry) else { continue }
                if entry.lastPathComponent.lowercased() == "global scenery" { continue }

                let (size, count) = calculateItemSize(at: entry)
                guard size > 0 else { continue }

                let category = classifyScenery(url: entry, folderName: entry.lastPathComponent)
                items.append(DiskUsageItem(
                    name: entry.lastPathComponent,
                    url: entry,
                    sizeBytes: size,
                    fileCount: count,
                    category: category,
                    locationName: locName,
                    locationURL: xPlanePath,
                    isOrphan: false,
                    isCache: false
                ))
            }
        }

        // 2. Aircraft (Ignore symlinks; skip default Laminar folder if desired or track separately)
        let aircraftDir = xPlanePath.appendingPathComponent("Aircraft")
        if let entries = try? fileManager.contentsOfDirectory(at: aircraftDir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries {
                if isSymbolicLink(entry) { continue }
                guard isDirectory(entry) else { continue }

                let isLaminar = entry.lastPathComponent.lowercased().contains("laminar")
                let (size, count) = calculateItemSize(at: entry)
                guard size > 0 else { continue }

                items.append(DiskUsageItem(
                    name: entry.lastPathComponent,
                    url: entry,
                    sizeBytes: size,
                    fileCount: count,
                    category: .aircraft,
                    locationName: locName,
                    locationURL: xPlanePath,
                    isOrphan: false,
                    isCache: false,
                    details: isLaminar ? "Default Simulator Aircraft" : nil
                ))
            }
        }

        // 3. Plugins
        let pluginsDir = xPlanePath.appendingPathComponent("Resources/plugins")
        if let entries = try? fileManager.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries {
                if isSymbolicLink(entry) { continue }
                if entry.lastPathComponent.lowercased() == "flywithlua" { continue } // Handled separately or with plugins

                let (size, count) = calculateItemSize(at: entry)
                guard size > 0 else { continue }

                items.append(DiskUsageItem(
                    name: entry.lastPathComponent,
                    url: entry,
                    sizeBytes: size,
                    fileCount: count,
                    category: .plugins,
                    locationName: locName,
                    locationURL: xPlanePath,
                    isOrphan: false,
                    isCache: false
                ))
            }
        }

        // 4. FlyWithLua Scripts
        let luaDir = xPlanePath.appendingPathComponent("Resources/plugins/FlyWithLua/Scripts")
        if let entries = try? fileManager.contentsOfDirectory(at: luaDir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries {
                if isSymbolicLink(entry) { continue }
                let (size, count) = calculateItemSize(at: entry)
                guard size > 0 else { continue }

                items.append(DiskUsageItem(
                    name: entry.lastPathComponent,
                    url: entry,
                    sizeBytes: size,
                    fileCount: count,
                    category: .luaScripts,
                    locationName: locName,
                    locationURL: xPlanePath,
                    isOrphan: false,
                    isCache: false
                ))
            }
        }

        // 5. Simulator Caches (Output/caches)
        let cachesDir = xPlanePath.appendingPathComponent("Output/caches")
        if fileManager.fileExists(atPath: cachesDir.path) {
            if let entries = try? fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for entry in entries {
                    let (size, count) = calculateItemSize(at: entry)
                    if size > 0 {
                        items.append(DiskUsageItem(
                            name: "Cache: \(entry.lastPathComponent)",
                            url: entry,
                            sizeBytes: size,
                            fileCount: count,
                            category: .caches,
                            locationName: locName,
                            locationURL: xPlanePath,
                            isOrphan: false,
                            isCache: true,
                            details: "Shader/Pipeline Cache"
                        ))
                    }
                }
            } else {
                let (size, count) = calculateItemSize(at: cachesDir)
                if size > 0 {
                    items.append(DiskUsageItem(
                        name: "Output Caches",
                        url: cachesDir,
                        sizeBytes: size,
                        fileCount: count,
                        category: .caches,
                        locationName: locName,
                        locationURL: xPlanePath,
                        isOrphan: false,
                        isCache: true,
                        details: "Shader/Pipeline Cache"
                    ))
                }
            }
        }

        // 6. Crash Reports & Logs (Output/crash_reports)
        let crashDir = xPlanePath.appendingPathComponent("Output/crash_reports")
        if fileManager.fileExists(atPath: crashDir.path) {
            let (size, count) = calculateItemSize(at: crashDir)
            if size > 0 {
                items.append(DiskUsageItem(
                    name: "Crash Reports",
                    url: crashDir,
                    sizeBytes: size,
                    fileCount: count,
                    category: .logsAndCrashes,
                    locationName: locName,
                    locationURL: xPlanePath,
                    isOrphan: false,
                    isCache: true,
                    details: "Crash dumps and diagnostic archives"
                ))
            }
        }

        return items
    }

    // MARK: - Storage Pool Scanner

    private func scanStoragePool(
        pool: StoragePool,
        profileReferencedFolders: Set<String>,
        primaryActiveSymlinks: Set<String>
    ) -> [DiskUsageItem] {
        var items: [DiskUsageItem] = []
        let poolLocName = "Storage Pool: \(pool.name)"

        // Categories in Storage Pool
        let categoriesToScan: [(AddonCategory, AddonStorageCategory)] = [
            (.aircraft, .aircraft),
            (.plugins, .plugins),
            (.luaScripts, .luaScripts)
        ]

        var scannedDirectories = Set<String>()

        // 1. Custom Scenery in pool (checks both standard launcher subfolder and Custom Scenery)
        let sceneryCandidateURLs = [
            PathService.shared.dataFolder(AddonCategory.scenery.subfolder, in: pool.url),
            pool.url.appendingPathComponent("Custom Scenery")
        ]

        for scenerySubfolder in sceneryCandidateURLs {
            guard !scannedDirectories.contains(scenerySubfolder.path),
                  let entries = try? fileManager.contentsOfDirectory(at: scenerySubfolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            scannedDirectories.insert(scenerySubfolder.path)

            for entry in entries {
                guard isDirectory(entry) else { continue }
                let folderName = entry.lastPathComponent
                let (size, count) = calculateItemSize(at: entry)
                guard size > 0 else { continue }

                let cat = classifyScenery(url: entry, folderName: folderName)
                let isOrphan = !profileReferencedFolders.contains(folderName) && !primaryActiveSymlinks.contains(folderName)

                items.append(DiskUsageItem(
                    name: folderName,
                    url: entry,
                    sizeBytes: size,
                    fileCount: count,
                    category: isOrphan ? .orphans : cat,
                    locationName: poolLocName,
                    locationURL: pool.url,
                    isOrphan: isOrphan,
                    isCache: false,
                    details: isOrphan ? "Not referenced by any profile" : nil
                ))
            }
        }

        // 2. Aircraft, Plugins, Lua Scripts in pool
        for (poolCat, storageCat) in categoriesToScan {
            let candidateURLs = [
                PathService.shared.dataFolder(poolCat.subfolder, in: pool.url),
                pool.url.appendingPathComponent(poolCat.subfolder.rawValue),
                pool.url.appendingPathComponent(poolCat.rawValue)
            ]

            for subfolder in candidateURLs {
                guard !scannedDirectories.contains(subfolder.path),
                      let entries = try? fileManager.contentsOfDirectory(at: subfolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                    continue
                }
                scannedDirectories.insert(subfolder.path)

                for entry in entries {
                    let folderName = entry.lastPathComponent
                    let (size, count) = calculateItemSize(at: entry)
                    guard size > 0 else { continue }

                    let isOrphan = !profileReferencedFolders.contains(folderName) && !primaryActiveSymlinks.contains(folderName)

                    items.append(DiskUsageItem(
                        name: folderName,
                        url: entry,
                        sizeBytes: size,
                        fileCount: count,
                        category: isOrphan ? .orphans : storageCat,
                        locationName: poolLocName,
                        locationURL: pool.url,
                        isOrphan: isOrphan,
                        isCache: false,
                        details: isOrphan ? "Not referenced by any profile" : nil
                    ))
                }
            }
        }

        return items
    }

    // MARK: - Scenery Classifier Heuristics

    func classifyScenery(url: URL, folderName: String) -> AddonStorageCategory {
        let lowerName = folderName.lowercased()

        // 1. Library check
        let libTxt = url.appendingPathComponent("library.txt")
        if fileManager.fileExists(atPath: libTxt.path) {
            return .sceneryLibraries
        }
        for known in AddonDiagnosticsService.knownLibraries {
            if known.prefixKeys.contains(where: { lowerName.contains($0.lowercased()) }) {
                return .sceneryLibraries
            }
        }

        // 2. Airport check (contains apt.dat)
        let aptDat = url.appendingPathComponent("Earth nav data/apt.dat")
        if fileManager.fileExists(atPath: aptDat.path) {
            return .sceneryAirports
        }

        // 3. Orthophoto check (folder naming or DDS textures heavy)
        if lowerName.hasPrefix("zortho") || lowerName.hasPrefix("yortho") || lowerName.contains("ortho") || lowerName.contains("photoreal") {
            return .sceneryOrthos
        }

        // 4. Mesh / Overlays check
        if lowerName.contains("mesh") || lowerName.contains("overlay") || lowerName.contains("simheaven") || lowerName.contains("w2xp") || lowerName.contains("dem") {
            return .sceneryMesh
        }

        // 5. Look for DSF or textures subfolders
        let earthNavData = url.appendingPathComponent("Earth nav data")
        if fileManager.fileExists(atPath: earthNavData.path) {
            // Has DSF but no apt.dat -> Mesh or overlay
            return .sceneryMesh
        }

        let texturesDir = url.appendingPathComponent("textures")
        if fileManager.fileExists(atPath: texturesDir.path) {
            return .sceneryOrthos
        }

        return .sceneryLibraries
    }

    // MARK: - Size Calculation Engine

    func calculateItemSize(at url: URL) -> (size: UInt64, count: Int) {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return (0, 0)
        }

        // Skip symlinks to avoid double-counting
        if isSymbolicLink(url) {
            return (0, 1)
        }

        if !isDir.boolValue {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            return (size, 1)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var totalSize: UInt64 = 0
        var totalCount: Int = 0

        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else {
                continue
            }

            if values.isSymbolicLink == true {
                // Do not follow symlinks inside add-ons
                continue
            }

            if values.isRegularFile == true, let size = values.fileSize {
                totalSize += UInt64(size)
                totalCount += 1
            }
        }

        return (totalSize, totalCount)
    }

    // MARK: - Safe Cleanup Utilities

    func clearShaderCache(xPlanePath: URL) async throws -> Int64 {
        let cachesDir = xPlanePath.appendingPathComponent("Output/caches")
        guard fileManager.fileExists(atPath: cachesDir.path) else { return 0 }

        let (initialSize, _) = calculateItemSize(at: cachesDir)
        let entries = try fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil, options: [])
        for entry in entries {
            try fileManager.removeItem(at: entry)
        }
        return Int64(initialSize)
    }

    func clearCrashReports(xPlanePath: URL) async throws -> Int64 {
        let crashDir = xPlanePath.appendingPathComponent("Output/crash_reports")
        guard fileManager.fileExists(atPath: crashDir.path) else { return 0 }

        let (initialSize, _) = calculateItemSize(at: crashDir)
        let entries = try fileManager.contentsOfDirectory(at: crashDir, includingPropertiesForKeys: nil, options: [])
        for entry in entries {
            try fileManager.removeItem(at: entry)
        }
        return Int64(initialSize)
    }

    func deleteItem(at url: URL) async throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - Helpers

    private func isSymbolicLink(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
            return true
        }
        return false
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
