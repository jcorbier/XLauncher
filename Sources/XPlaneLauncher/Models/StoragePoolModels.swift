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

/// A registered storage pool location across internal or external/Thunderbolt drives.
public struct StoragePool: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var isPrimary: Bool
    public var defaultCategories: [AddonCategory]

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        isPrimary: Bool = false,
        defaultCategories: [AddonCategory] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isPrimary = isPrimary
        self.defaultCategories = defaultCategories
    }

    /// Whether this storage pool's directory is currently mounted and accessible on the filesystem.
    public var isOnline: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Retrieves volume-level resource values if the volume is mounted.
    public var volumeMetrics: VolumeMetrics? {
        guard isOnline else { return nil }

        let values = try? url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])

        var total: UInt64 = UInt64(values?.volumeTotalCapacity ?? 0)
        var available: UInt64 = 0

        if let importantUsage = values?.volumeAvailableCapacityForImportantUsage, importantUsage > 0 {
            available = UInt64(importantUsage)
        } else if let standardAvailable = values?.volumeAvailableCapacity, standardAvailable > 0 {
            available = UInt64(standardAvailable)
        }

        // Fallback to POSIX / statfs filesystem attributes if URLResourceValues was incomplete
        if total == 0 || available == 0 {
            if let fsAttrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path) {
                if total == 0, let fsTotal = (fsAttrs[.systemSize] as? NSNumber)?.uint64Value, fsTotal > 0 {
                    total = fsTotal
                }
                if available == 0, let fsFree = (fsAttrs[.systemFreeSize] as? NSNumber)?.uint64Value, fsFree > 0 {
                    available = fsFree
                }
            }
        }

        guard total > 0 else { return nil }

        let volName = values?.volumeName ?? url.lastPathComponent
        let used = total > available ? (total - available) : 0

        return VolumeMetrics(
            volumeName: volName,
            totalCapacity: total,
            availableCapacity: available,
            usedCapacity: used
        )
    }

    /// An appropriate SF Symbol icon for this pool based on mount state and path.
    public var iconName: String {
        if !isOnline {
            return "externaldrive.badge.xmark"
        }
        if url.path.hasPrefix("/Volumes/") {
            return "externaldrive.connected.to.line.below"
        }
        return isPrimary ? "internaldrive" : "externaldrive"
    }
}

public struct VolumeMetrics: Sendable, Hashable {
    public let volumeName: String
    public let totalCapacity: UInt64
    public let availableCapacity: UInt64
    public let usedCapacity: UInt64

    public var usedFraction: Double {
        guard totalCapacity > 0 else { return 0.0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    public init(volumeName: String, totalCapacity: UInt64, availableCapacity: UInt64, usedCapacity: UInt64) {
        self.volumeName = volumeName
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.usedCapacity = usedCapacity
    }
}

/// Statistics and add-on storage footprint breakdown for a single storage pool.
public struct StoragePoolStats: Identifiable, Sendable, Hashable {
    public var id: UUID { poolId }
    public let poolId: UUID
    public let poolName: String
    public let isOnline: Bool
    public let volumeMetrics: VolumeMetrics?
    public let itemCounts: [AddonCategory: Int]
    public let itemSizes: [AddonCategory: UInt64]

    public init(
        poolId: UUID,
        poolName: String,
        isOnline: Bool,
        volumeMetrics: VolumeMetrics?,
        itemCounts: [AddonCategory: Int] = [:],
        itemSizes: [AddonCategory: UInt64] = [:]
    ) {
        self.poolId = poolId
        self.poolName = poolName
        self.isOnline = isOnline
        self.volumeMetrics = volumeMetrics
        self.itemCounts = itemCounts
        self.itemSizes = itemSizes
    }

    public var totalItemCount: Int {
        itemCounts.values.reduce(0, +)
    }

    public var totalItemSize: UInt64 {
        itemSizes.values.reduce(0, +)
    }

    public var pluginCount: Int { itemCounts[.plugins] ?? 0 }
    public var sceneryCount: Int { itemCounts[.scenery] ?? 0 }
    public var aircraftCount: Int { itemCounts[.aircraft] ?? 0 }
    public var luaScriptCount: Int { itemCounts[.luaScripts] ?? 0 }

    public var pluginSizeBytes: Int64 { Int64(itemSizes[.plugins] ?? 0) }
    public var scenerySizeBytes: Int64 { Int64(itemSizes[.scenery] ?? 0) }
    public var aircraftSizeBytes: Int64 { Int64(itemSizes[.aircraft] ?? 0) }
    public var luaSizeBytes: Int64 { Int64(itemSizes[.luaScripts] ?? 0) }
}
