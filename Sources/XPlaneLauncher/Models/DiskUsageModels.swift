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

enum AddonStorageCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case aircraft = "Aircraft"
    case sceneryAirports = "Airports"
    case sceneryOrthos = "Orthophotos"
    case sceneryMesh = "Mesh & Overlays"
    case sceneryLibraries = "Scenery Libraries"
    case plugins = "Plugins"
    case luaScripts = "Lua Scripts"
    case cslModels = "CSL Models"
    case caches = "Simulator Caches"
    case logsAndCrashes = "Logs & Crash Reports"
    case orphans = "Orphaned Packages"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .aircraft: return "airplane"
        case .sceneryAirports: return "airplane.arrival"
        case .sceneryOrthos: return "photo.stack"
        case .sceneryMesh: return "mountain.2"
        case .sceneryLibraries: return "building.2"
        case .plugins: return "puzzlepiece.extension"
        case .luaScripts: return "scroll"
        case .cslModels: return "airplane.circle"
        case .caches: return "trash.circle"
        case .logsAndCrashes: return "doc.badge.ellipsis"
        case .orphans: return "questionmark.folder"
        }
    }

    var color: Color {
        switch self {
        case .aircraft: return .blue
        case .sceneryAirports: return .green
        case .sceneryOrthos: return .teal
        case .sceneryMesh: return .indigo
        case .sceneryLibraries: return .orange
        case .plugins: return .purple
        case .luaScripts: return .yellow
        case .cslModels: return .cyan
        case .caches: return .pink
        case .logsAndCrashes: return .red
        case .orphans: return .brown
        }
    }

    var isSceneryCategory: Bool {
        switch self {
        case .sceneryAirports, .sceneryOrthos, .sceneryMesh, .sceneryLibraries:
            return true
        default:
            return false
        }
    }
}

struct DiskUsageItem: Identifiable, Sendable {
    let id: UUID
    let name: String
    let url: URL
    let sizeBytes: UInt64
    let fileCount: Int
    let category: AddonStorageCategory
    let locationName: String
    let locationURL: URL
    let isOrphan: Bool
    let isCache: Bool
    let details: String?

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        sizeBytes: UInt64,
        fileCount: Int,
        category: AddonStorageCategory,
        locationName: String,
        locationURL: URL,
        isOrphan: Bool = false,
        isCache: Bool = false,
        details: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.category = category
        self.locationName = locationName
        self.locationURL = locationURL
        self.isOrphan = isOrphan
        self.isCache = isCache
        self.details = details
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

struct DiskUsageSummary: Sendable {
    let scanTimestamp: Date
    let totalBytes: UInt64
    let totalFiles: Int
    let items: [DiskUsageItem]
    let categorySizes: [AddonStorageCategory: UInt64]
    let locationSizes: [String: UInt64]
    let topSpaceHogs: [DiskUsageItem]
    let cacheItems: [DiskUsageItem]
    let orphanItems: [DiskUsageItem]

    init(
        scanTimestamp: Date = Date(),
        totalBytes: UInt64,
        totalFiles: Int,
        items: [DiskUsageItem],
        categorySizes: [AddonStorageCategory: UInt64],
        locationSizes: [String: UInt64],
        topSpaceHogs: [DiskUsageItem],
        cacheItems: [DiskUsageItem],
        orphanItems: [DiskUsageItem]
    ) {
        self.scanTimestamp = scanTimestamp
        self.totalBytes = totalBytes
        self.totalFiles = totalFiles
        self.items = items
        self.categorySizes = categorySizes
        self.locationSizes = locationSizes
        self.topSpaceHogs = topSpaceHogs
        self.cacheItems = cacheItems
        self.orphanItems = orphanItems
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }
}
