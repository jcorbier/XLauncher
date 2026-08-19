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

final class SymlinkService: Sendable {
    static let shared = SymlinkService()

    private var fileManager: FileManager { FileManager.default }

    // MARK: - Link Management

    /// Reports whether a directory entry exists, without resolving symbolic links.
    /// `FileManager.fileExists` follows links, so a link whose target moved away
    /// reads as "missing" even though the entry is still there.
    private func entryExists(at url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private func isSymlink(at url: URL) -> Bool {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.type] as? String) == FileAttributeType.typeSymbolicLink.rawValue
    }

    /// Points `linkURL` at `sourceURL`, replacing a link left over from an earlier
    /// data folder location. Real directories are never touched: they hold add-ons
    /// the launcher does not manage.
    private func createOrReplaceLink(at linkURL: URL, to sourceURL: URL) throws {
        if isSymlink(at: linkURL) {
            try fileManager.removeItem(at: linkURL)
        } else if entryExists(at: linkURL) {
            return
        }

        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
    }

    /// Removes a managed link. Unmanaged content stays where it is.
    private func removeLink(at linkURL: URL) throws {
        if isSymlink(at: linkURL) {
            try fileManager.removeItem(at: linkURL)
        }
    }

    // MARK: - Link Repair

    /// Source add-ons available for repair, keyed by the name they are linked under.
    func linkSources(in dataFolder: URL) -> [String: URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: contents.map { ($0.lastPathComponent, $0) })
    }

    /// Lua bundles are linked child by child, so the children are the repair sources.
    func luaScriptLinkSources(in dataFolder: URL) -> [String: URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [:]
        }

        var sources: [String: URL] = [:]
        for item in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let children = (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for child in children {
                    sources[child.lastPathComponent] = child
                }
            } else {
                sources[item.lastPathComponent] = item
            }
        }
        return sources
    }

    /// Repoints links that no longer resolve at a source of the same name, which is
    /// what an add-on left behind after its source folder moved looks like.
    ///
    /// Deliberately conservative: intact links keep pointing where they point, real
    /// directories are never touched, and a link without a matching source is left
    /// in place rather than guessed at or deleted. Returns the repaired names.
    @discardableResult
    func repairStaleLinks(in targetFolder: URL, using sources: [String: URL]) -> [String] {
        guard !sources.isEmpty,
              let contents = try? fileManager.contentsOfDirectory(at: targetFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        var repaired: [String] = []
        for linkURL in contents {
            let name = linkURL.lastPathComponent
            guard isSymlink(at: linkURL),
                  !fileManager.fileExists(atPath: linkURL.path),  // resolves the link: false means the target is gone
                  let sourceURL = sources[name] else { continue }

            do {
                try fileManager.removeItem(at: linkURL)
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
                repaired.append(name)
            } catch {
                continue
            }
        }
        return repaired.sorted()
    }

    // MARK: - Plugins

    func scanPlugins(dataFolder: URL, targetFolder: URL) throws -> [Plugin] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dataFolder.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var list: [Plugin] = []

        for folder in contents {
            var folderCheck: ObjCBool = false
            if fileManager.fileExists(atPath: folder.path, isDirectory: &folderCheck), folderCheck.boolValue {
                let folderName = folder.lastPathComponent
                let targetLink = targetFolder.appendingPathComponent(folderName)
                let isEnabled = fileManager.fileExists(atPath: targetLink.path)
                list.append(Plugin(name: folderName, isEnabled: isEnabled, folderName: folderName))
            }
        }

        return list.sorted { $0.name < $1.name }
    }

    func setPluginEnabled(folderName: String, enabled: Bool, dataFolder: URL, targetFolder: URL) throws {
        let sourceURL = dataFolder.appendingPathComponent(folderName)
        let linkURL = targetFolder.appendingPathComponent(folderName)

        if enabled {
            try createOrReplaceLink(at: linkURL, to: sourceURL)
        } else {
            try removeLink(at: linkURL)
        }
    }

    // MARK: - Aircraft

    func scanAircraft(dataFolder: URL, targetFolder: URL) throws -> [Aircraft] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dataFolder.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var list: [Aircraft] = []

        for folder in contents {
            var folderCheck: ObjCBool = false
            if fileManager.fileExists(atPath: folder.path, isDirectory: &folderCheck), folderCheck.boolValue {
                let folderName = folder.lastPathComponent
                let targetLink = targetFolder.appendingPathComponent(folderName)
                let isEnabled = fileManager.fileExists(atPath: targetLink.path)
                list.append(Aircraft(name: folderName, isEnabled: isEnabled, folderName: folderName))
            }
        }

        return list.sorted { $0.name < $1.name }
    }

    func setAircraftEnabled(folderName: String, enabled: Bool, dataFolder: URL, targetFolder: URL) throws {
        let sourceURL = dataFolder.appendingPathComponent(folderName)
        let linkURL = targetFolder.appendingPathComponent(folderName)

        if enabled {
            try createOrReplaceLink(at: linkURL, to: sourceURL)
        } else {
            try removeLink(at: linkURL)
        }
    }

    // MARK: - FlyWithLua Scripts

    func scanLuaScripts(dataFolder: URL, targetFolder: URL?) throws -> [LuaScript] {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dataFolder.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let contents = try fileManager.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var list: [LuaScript] = []

        for item in contents {
            var folderCheck: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &folderCheck) {
                let folderName = item.lastPathComponent
                let isDirBool = folderCheck.boolValue

                var isEnabled = false
                if let targetFolder = targetFolder {
                    if isDirBool {
                        if let childContents = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                           let firstChild = childContents.first {
                            let childLink = targetFolder.appendingPathComponent(firstChild.lastPathComponent)
                            isEnabled = fileManager.fileExists(atPath: childLink.path)
                        }
                    } else {
                        let targetLink = targetFolder.appendingPathComponent(folderName)
                        isEnabled = fileManager.fileExists(atPath: targetLink.path)
                    }
                }

                list.append(LuaScript(name: folderName, isEnabled: isEnabled, folderName: folderName, isDirectory: isDirBool))
            }
        }

        return list.sorted { $0.name < $1.name }
    }

    func setLuaScriptEnabled(item: LuaScript, enabled: Bool, dataFolder: URL, targetFolder: URL) throws {
        let itemSourceURL = dataFolder.appendingPathComponent(item.folderName)

        if enabled {
            try? fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            if item.isDirectory {
                let children = try fileManager.contentsOfDirectory(at: itemSourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                for child in children {
                    let linkURL = targetFolder.appendingPathComponent(child.lastPathComponent)
                    try createOrReplaceLink(at: linkURL, to: child)
                }
            } else {
                let linkURL = targetFolder.appendingPathComponent(item.folderName)
                try createOrReplaceLink(at: linkURL, to: itemSourceURL)
            }
        } else {
            if item.isDirectory {
                if let children = try? fileManager.contentsOfDirectory(at: itemSourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for child in children {
                        let linkURL = targetFolder.appendingPathComponent(child.lastPathComponent)
                        try removeLink(at: linkURL)
                    }
                }
            } else {
                let linkURL = targetFolder.appendingPathComponent(item.folderName)
                try removeLink(at: linkURL)
            }
        }
    }
}
