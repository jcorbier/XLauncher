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

public final class StoragePoolService: Sendable {
    public static let shared = StoragePoolService()

    private var defaults: UserDefaults { UserDefaults.standard }
    private var fileManager: FileManager { FileManager.default }

    public init() {}

    // MARK: - Persistence & Migration

    public func loadStoragePools() -> [StoragePool] {
        if let data = defaults.data(forKey: .storagePools),
           let decoded = try? JSONDecoder().decode([StoragePool].self, from: data),
           !decoded.isEmpty {
            return ensurePrimaryPool(in: decoded)
        }

        // Migration from legacy single LauncherDataFolder
        if let legacyPath = defaults.string(forKey: .launcherDataFolder) {
            let legacyURL = URL(fileURLWithPath: legacyPath)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: legacyURL.path, isDirectory: &isDir) && isDir.boolValue {
                let pool = StoragePool(
                    name: "Primary Storage",
                    url: legacyURL,
                    isPrimary: true,
                    defaultCategories: AddonCategory.allCases
                )
                saveStoragePools([pool])
                return [pool]
            }
        }

        // Default initial fallback
        if let defaultFolder = PathService.defaultLauncherDataFolder {
            let pool = StoragePool(
                name: "Primary Storage",
                url: defaultFolder,
                isPrimary: true,
                defaultCategories: AddonCategory.allCases
            )
            return [pool]
        }

        return []
    }

    public func saveStoragePools(_ pools: [StoragePool]) {
        let normalized = ensurePrimaryPool(in: pools)
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: .storagePools)
        }
        // Update legacy key for primary pool to maintain full backwards compatibility
        if let primary = normalized.first(where: { $0.isPrimary }) ?? normalized.first {
            defaults.set(primary.url.path, forKey: .launcherDataFolder)
        } else {
            defaults.removeObject(forKey: .launcherDataFolder)
        }
    }

    private func ensurePrimaryPool(in pools: [StoragePool]) -> [StoragePool] {
        guard !pools.isEmpty else { return [] }
        var result = pools
        let primaryCount = result.filter { $0.isPrimary }.count
        if primaryCount == 0 {
            result[0].isPrimary = true
        } else if primaryCount > 1 {
            var foundFirst = false
            for i in 0..<result.count {
                if result[i].isPrimary {
                    if foundFirst {
                        result[i].isPrimary = false
                    } else {
                        foundFirst = true
                    }
                }
            }
        }
        return result
    }

    // MARK: - Category Routing

    public func resolveDestinationPool(category: AddonCategory, in pools: [StoragePool]) -> StoragePool? {
        let onlinePools = pools.filter { $0.isOnline }
        let candidates = onlinePools.isEmpty ? pools : onlinePools

        // 1. Check if any candidate has explicitly configured default for this category
        if let designated = candidates.first(where: { $0.defaultCategories.contains(category) }) {
            return designated
        }

        // 2. Fall back to primary pool
        if let primary = candidates.first(where: { $0.isPrimary }) {
            return primary
        }

        // 3. Fall back to first available pool
        return candidates.first
    }

    // MARK: - Volume Metrics & Statistics

    public func calculateStats(for pool: StoragePool) -> StoragePoolStats {
        let isOnline = pool.isOnline
        let metrics = pool.volumeMetrics

        guard isOnline else {
            return StoragePoolStats(
                poolId: pool.id,
                poolName: pool.name,
                isOnline: false,
                volumeMetrics: nil,
                itemCounts: [:],
                itemSizes: [:]
            )
        }

        var counts: [AddonCategory: Int] = [:]
        var sizes: [AddonCategory: UInt64] = [:]

        for category in AddonCategory.allCases {
            let subfolderURL = PathService.shared.dataFolder(category.subfolder, in: pool.url)
            guard let contents = try? fileManager.contentsOfDirectory(at: subfolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                counts[category] = 0
                sizes[category] = 0
                continue
            }

            counts[category] = contents.count
            var categorySize: UInt64 = 0
            for item in contents {
                categorySize += calculateDirectoryOrFileSize(at: item)
            }
            sizes[category] = categorySize
        }

        return StoragePoolStats(
            poolId: pool.id,
            poolName: pool.name,
            isOnline: true,
            volumeMetrics: metrics,
            itemCounts: counts,
            itemSizes: sizes
        )
    }

    public func calculateDirectoryOrFileSize(at url: URL) -> UInt64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        }

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var total: UInt64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += UInt64(size)
            }
        }
        return total
    }
}
