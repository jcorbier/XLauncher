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

final class SceneryService: Sendable {
    static let shared = SceneryService()

    private var fileManager: FileManager { FileManager.default }
    private let kXPlaneCustomSceneryFileName = "scenery_packs.ini"

    // MARK: - Filesystem Helpers

    /// Reports whether a directory entry exists (including broken symlinks).
    private func entryExists(at url: URL) -> Bool {
        var statBuf = stat()
        return lstat(url.path, &statBuf) == 0
    }

    private func isSymlink(at url: URL) -> Bool {
        var statBuf = stat()
        if lstat(url.path, &statBuf) == 0 {
            return (statBuf.st_mode & S_IFMT) == S_IFLNK
        }
        return false
    }

    private func symlinkDestination(at url: URL) -> String? {
        try? fileManager.destinationOfSymbolicLink(atPath: url.path)
    }

    /// A real directory, or a symbolic link that is meant to point at one —
    /// including links whose target is currently unavailable.
    private func isDirectoryOrLink(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return isSymlink(at: url)
    }

    func scanScenery(
        customSceneryFolder: URL,
        managedSceneryFolder: URL?,
        iniURL: URL?
    ) throws -> [Scenery] {
        let pools: [StoragePool]
        if let managedURL = managedSceneryFolder {
            let pool = StoragePool(name: "Default", url: managedURL, isPrimary: true)
            pools = [pool]
        } else {
            pools = []
        }
        return try scanScenery(
            customSceneryFolder: customSceneryFolder,
            storagePools: pools,
            iniURL: iniURL
        )
    }

    func scanScenery(
        customSceneryFolder: URL,
        storagePools: [StoragePool],
        iniURL: URL?,
        knownScenery: [Scenery] = []
    ) throws -> [Scenery] {
        var poolByFolderName: [String: StoragePool] = [:]
        var sourceURLByFolderName: [String: URL] = [:]

        // 0. Discover managed packs across all online storage pools and ensure they are linked
        for pool in storagePools where pool.isOnline {
            let primaryManagedURL = PathService.shared.dataFolder(.scenery, in: pool.url)
            let managedURL: URL
            if fileManager.fileExists(atPath: primaryManagedURL.path) {
                managedURL = primaryManagedURL
            } else if fileManager.fileExists(atPath: pool.url.path) {
                managedURL = pool.url
            } else {
                continue
            }

            if let contents = try? fileManager.contentsOfDirectory(at: managedURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for url in contents {
                    if isDirectoryOrLink(at: url) {
                        let name = url.lastPathComponent
                        if poolByFolderName[name] == nil {
                            poolByFolderName[name] = pool
                            sourceURLByFolderName[name] = url
                        }
                        try? linkScenery(folderName: name, sourceURL: url, customSceneryFolder: customSceneryFolder)
                    }
                }
            }
        }

        // 1. Read scenery_packs.ini to establish order
        var iniItems: [(line: String, folderName: String, enabled: Bool)] = []
        var foundFolderNames: Set<String> = []

        if let iniPath = iniURL,
           let content = try? String(contentsOf: iniPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "SCENERY_PACK") {
                    let isEnabled = trimmed.starts(with: "SCENERY_PACK ")
                    let prefix = isEnabled ? "SCENERY_PACK " : "SCENERY_PACK_DISABLED "
                    let pathPart = String(trimmed.dropFirst(prefix.count))
                    let components = pathPart.split(separator: "/")
                    if let last = components.last {
                        let folderName = String(last)
                        iniItems.append((line: trimmed, folderName: folderName, enabled: isEnabled))
                        foundFolderNames.insert(folderName)
                    }
                }
            }
        }

        // 2. Scan "Custom Scenery" for items NOT in INI
        var installedButNotInIni: [Scenery] = []
        if fileManager.fileExists(atPath: customSceneryFolder.path) {
            let csContents = (try? fileManager.contentsOfDirectory(at: customSceneryFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in csContents {
                if url.lastPathComponent == kXPlaneCustomSceneryFileName { continue }

                if isDirectoryOrLink(at: url) {
                    let name = url.lastPathComponent
                    if !foundFolderNames.contains(name) {
                        let isManagedLink = isSymlink(at: url)
                        let dest = isManagedLink ? symlinkDestination(at: url) : nil
                        let targetExists = fileManager.fileExists(atPath: url.path)
                        let matchingPool = poolByFolderName[name] ?? storagePools.first(where: { SymlinkService.pathBelongsToPool(destination: dest, poolURL: $0.url) })
                        let sourceURL = sourceURLByFolderName[name] ?? dest.map { URL(fileURLWithPath: $0) }
                        if isManagedLink && !targetExists && matchingPool == nil {
                            try? fileManager.removeItem(at: url)
                            continue
                        }
                        let isOffline = isManagedLink && (!targetExists || matchingPool?.isOnline == false)
                        installedButNotInIni.append(Scenery(
                            name: name,
                            isEnabled: true,
                            folderName: name,
                            isManaged: isManagedLink,
                            iniLine: "SCENERY_PACK Custom Scenery/\(name)/",
                            storagePoolId: matchingPool?.id,
                            storagePoolName: matchingPool?.name,
                            sourceURL: sourceURL,
                            isOffline: isOffline
                        ))
                    }
                }
            }
        }

        // 3. Construct final list
        var finalScenery: [Scenery] = []
        var processedFolderNames = Set<String>()

        for item in installedButNotInIni.sorted(by: { $0.name < $1.name }) {
            finalScenery.append(item)
            processedFolderNames.insert(item.folderName)
        }

        for item in iniItems {
            let path = customSceneryFolder.appendingPathComponent(item.folderName)
            let isSpecialIdx = item.folderName.hasPrefix("*")

            if isSpecialIdx || entryExists(at: path) {
                let isManagedLink = !isSpecialIdx && isSymlink(at: path)
                let dest = isManagedLink ? symlinkDestination(at: path) : nil
                let targetExists = isSpecialIdx || fileManager.fileExists(atPath: path.path)
                let matchingPool = poolByFolderName[item.folderName] ?? storagePools.first(where: { SymlinkService.pathBelongsToPool(destination: dest, poolURL: $0.url) })
                let sourceURL = sourceURLByFolderName[item.folderName] ?? dest.map { URL(fileURLWithPath: $0) }
                if isManagedLink && !targetExists && matchingPool == nil {
                    try? fileManager.removeItem(at: path)
                    continue
                }
                let isOffline = isManagedLink && (!targetExists || matchingPool?.isOnline == false)

                finalScenery.append(Scenery(
                    name: item.folderName,
                    isEnabled: isOffline ? false : item.enabled,
                    folderName: item.folderName,
                    isManaged: isManagedLink,
                    iniLine: item.line,
                    storagePoolId: matchingPool?.id,
                    storagePoolName: matchingPool?.name,
                    sourceURL: sourceURL,
                    isOffline: isOffline
                ))
                processedFolderNames.insert(item.folderName)
            }
        }

        // 4. Preserve known items from offline storage pools
        for known in knownScenery where !processedFolderNames.contains(known.folderName) {
            let pool = storagePools.first(where: { $0.id == known.storagePoolId })
            let isPoolOffline = pool?.isOnline == false
            if isPoolOffline || (known.isOffline && pool != nil) {
                var offlineItem = known
                offlineItem.isOffline = true
                offlineItem.isEnabled = false
                finalScenery.append(offlineItem)
                processedFolderNames.insert(known.folderName)
            }
        }

        return finalScenery
    }

    func saveSceneryOrder(scenery: [Scenery], customSceneryFolder: URL, iniURL: URL) throws {
        var content = "I\n1000 Version\nSCENERY\n\n"

        for item in scenery {
            let line: String
            let isSpecialIdx = item.folderName.hasPrefix("*")
            let prefix = item.isEnabled ? "SCENERY_PACK " : "SCENERY_PACK_DISABLED "

            if isSpecialIdx {
                line = "\(prefix)\(item.folderName)"
            } else {
                line = "\(prefix)Custom Scenery/\(item.folderName)/"
            }

            if isSpecialIdx {
                content += line + "\n"
            } else {
                let path = customSceneryFolder.appendingPathComponent(item.folderName)
                if entryExists(at: path) || item.isOffline {
                    content += line + "\n"
                }
            }
        }

        guard PathSecurity.isStrictlyContained(url: iniURL, within: customSceneryFolder) else {
            throw AppError.pathNotFound(iniURL.path)
        }

        try content.write(to: iniURL, atomically: true, encoding: .utf8)
    }

    func linkScenery(folderName: String, managedSceneryFolder: URL, customSceneryFolder: URL) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(folderName)
        let sourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: managedSceneryFolder)
        try linkScenery(folderName: folderName, sourceURL: sourceURL, customSceneryFolder: customSceneryFolder)
    }

    func linkScenery(folderName: String, sourceURL: URL, customSceneryFolder: URL) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(folderName)
        let linkURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: customSceneryFolder)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppError.pathNotFound(sourceURL.path)
        }

        if isSymlink(at: linkURL) {
            // Stale link, e.g. left behind after the central data folder moved.
            try fileManager.removeItem(at: linkURL)
        } else if entryExists(at: linkURL) {
            // A real directory lives here — never replace unmanaged user content.
            return
        }

        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
    }

    func unlinkScenery(folderName: String, customSceneryFolder: URL) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(folderName)
        let linkURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: customSceneryFolder)
        // Only ever remove the link itself, never a real scenery directory.
        // `isSymlink` also matches stale links, which `fileExists` would miss.
        if isSymlink(at: linkURL) {
            try fileManager.removeItem(at: linkURL)
        }
    }

    func createGroup(
        name: String,
        items: [Scenery],
        existingGroups: [SceneryGroup],
        existingScenery: [Scenery]
    ) -> (groups: [SceneryGroup], scenery: [Scenery]) {
        let folderNames = items.map { $0.folderName }
        let newGroup = SceneryGroup(name: name, childFolderNames: folderNames)

        var groups = existingGroups
        for folder in folderNames {
            for (idx, _) in groups.enumerated() {
                if let i = groups[idx].childFolderNames.firstIndex(of: folder) {
                    groups[idx].childFolderNames.remove(at: i)
                }
            }
        }
        groups.append(newGroup)

        var scenery = existingScenery
        if let firstItem = items.first,
           let firstIndex = scenery.firstIndex(where: { $0.folderName == firstItem.folderName }) {
            var remaining = scenery.filter { !folderNames.contains($0.folderName) }
            let insertIndex = min(firstIndex, remaining.count)
            let movingItems = scenery.filter { folderNames.contains($0.folderName) }
            remaining.insert(contentsOf: movingItems, at: insertIndex)
            scenery = remaining
        }

        return (groups, scenery)
    }

    func deleteGroup(group: SceneryGroup, existingGroups: [SceneryGroup]) -> [SceneryGroup] {
        var groups = existingGroups
        groups.removeAll { $0.id == group.id }
        return groups
    }

    func removeFromGroup(sceneryItem: Scenery, existingGroups: [SceneryGroup]) -> [SceneryGroup] {
        var groups = existingGroups
        for (idx, _) in groups.enumerated() {
            if let i = groups[idx].childFolderNames.firstIndex(of: sceneryItem.folderName) {
                groups[idx].childFolderNames.remove(at: i)
            }
        }
        return groups
    }
}
