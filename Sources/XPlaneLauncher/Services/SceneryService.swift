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

    func scanScenery(
        customSceneryFolder: URL,
        managedSceneryFolder: URL?,
        iniURL: URL?
    ) throws -> [Scenery] {
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
            let csContents = try fileManager.contentsOfDirectory(at: customSceneryFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for url in csContents {
                if url.lastPathComponent == kXPlaneCustomSceneryFileName { continue }

                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let name = url.lastPathComponent
                    if !foundFolderNames.contains(name) {
                        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                        let isSymlink = (attributes?[.type] as? String) == FileAttributeType.typeSymbolicLink.rawValue

                        installedButNotInIni.append(Scenery(
                            name: name,
                            isEnabled: true,
                            folderName: name,
                            isManaged: isSymlink,
                            isInIni: false,
                            iniLine: "SCENERY_PACK Custom Scenery/\(name)/"
                        ))
                    }
                }
            }
        }

        // 3. Scan managed Scenery folder for uninstalled items
        var uninstalled: [Scenery] = []
        if let managedURL = managedSceneryFolder, fileManager.fileExists(atPath: managedURL.path) {
            let contents = try fileManager.contentsOfDirectory(at: managedURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for url in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let name = url.lastPathComponent
                    let isInstalled = foundFolderNames.contains(name) || installedButNotInIni.contains(where: { $0.folderName == name })

                    if !isInstalled {
                        uninstalled.append(Scenery(
                            name: name,
                            isEnabled: false,
                            folderName: name,
                            isManaged: true,
                            isInIni: false,
                            iniLine: ""
                        ))
                    }
                }
            }
        }

        // 4. Construct final list
        var finalScenery: [Scenery] = []
        finalScenery.append(contentsOf: installedButNotInIni.sorted { $0.name < $1.name })

        for item in iniItems {
            let path = customSceneryFolder.appendingPathComponent(item.folderName)
            let isSpecialIdx = item.folderName.hasPrefix("*")

            if isSpecialIdx || fileManager.fileExists(atPath: path.path) {
                var isSymlink = false
                if !isSpecialIdx {
                    let attributes = try? fileManager.attributesOfItem(atPath: path.path)
                    isSymlink = (attributes?[.type] as? String) == FileAttributeType.typeSymbolicLink.rawValue
                }

                finalScenery.append(Scenery(
                    name: item.folderName,
                    isEnabled: item.enabled,
                    folderName: item.folderName,
                    isManaged: isSymlink,
                    isInIni: true,
                    iniLine: item.line
                ))
            }
        }

        finalScenery.append(contentsOf: uninstalled.sorted { $0.name < $1.name })
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
                if fileManager.fileExists(atPath: path.path) {
                    content += line + "\n"
                }
            }
        }

        try content.write(to: iniURL, atomically: true, encoding: .utf8)
    }

    func linkScenery(folderName: String, managedSceneryFolder: URL, customSceneryFolder: URL) throws {
        let linkURL = customSceneryFolder.appendingPathComponent(folderName)
        let sourceURL = managedSceneryFolder.appendingPathComponent(folderName)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppError.pathNotFound(sourceURL.path)
        }

        if !fileManager.fileExists(atPath: linkURL.path) {
            try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
        }
    }

    func unlinkScenery(folderName: String, customSceneryFolder: URL) throws {
        let linkURL = customSceneryFolder.appendingPathComponent(folderName)
        if fileManager.fileExists(atPath: linkURL.path) {
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
