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

    /// Aggregates link sources from multiple storage pools for a specific subfolder.
    func linkSources(in pools: [StoragePool], subfolder: DataSubfolder) -> [String: URL] {
        var aggregated: [String: URL] = [:]
        for pool in pools where pool.isOnline {
            let folder = PathService.shared.dataFolder(subfolder, in: pool.url)
            let sources = linkSources(in: folder)
            for (key, val) in sources where aggregated[key] == nil {
                aggregated[key] = val
            }
        }
        return aggregated
    }

    private struct LuaStructure {
        let scriptsDir: URL?
        let modulesDir: URL?
        let isStructured: Bool
    }

    private func inspectLuaDirectory(at url: URL) -> LuaStructure {
        let subItems = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let scriptsDir = subItems.first { item in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: item.path, isDirectory: &isDir) && isDir.boolValue && item.lastPathComponent.caseInsensitiveCompare("Scripts") == .orderedSame
        }
        let modulesDir = subItems.first { item in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: item.path, isDirectory: &isDir) && isDir.boolValue && item.lastPathComponent.caseInsensitiveCompare("Modules") == .orderedSame
        }
        return LuaStructure(
            scriptsDir: scriptsDir,
            modulesDir: modulesDir,
            isStructured: (scriptsDir != nil || modulesDir != nil)
        )
    }

    private func resolveModulesTargetFolder(from scriptsTargetFolder: URL?, explicitModulesTarget: URL?) -> URL? {
        if let explicitModulesTarget = explicitModulesTarget {
            return explicitModulesTarget
        }
        guard let scriptsTarget = scriptsTargetFolder else { return nil }
        if scriptsTarget.lastPathComponent.caseInsensitiveCompare("Scripts") == .orderedSame {
            return scriptsTarget.deletingLastPathComponent().appendingPathComponent("Modules")
        } else {
            return scriptsTarget.appendingPathComponent("Modules")
        }
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
                let structure = inspectLuaDirectory(at: item)
                if structure.isStructured {
                    if let scriptsDir = structure.scriptsDir {
                        let children = (try? fileManager.contentsOfDirectory(at: scriptsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                        for child in children {
                            sources[child.lastPathComponent] = child
                        }
                    }
                } else {
                    let children = (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    for child in children {
                        sources[child.lastPathComponent] = child
                    }
                }
            } else {
                sources[item.lastPathComponent] = item
            }
        }
        return sources
    }

    /// Aggregates Lua script link sources across multiple storage pools.
    func luaScriptLinkSources(in pools: [StoragePool]) -> [String: URL] {
        var aggregated: [String: URL] = [:]
        for pool in pools where pool.isOnline {
            let folder = PathService.shared.dataFolder(.luaScripts, in: pool.url)
            let sources = luaScriptLinkSources(in: folder)
            for (key, val) in sources where aggregated[key] == nil {
                aggregated[key] = val
            }
        }
        return aggregated
    }

    /// Modules for structured Lua add-ons.
    func luaModuleLinkSources(in dataFolder: URL) -> [String: URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [:]
        }

        var sources: [String: URL] = [:]
        for item in contents {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let structure = inspectLuaDirectory(at: item)
            if let modulesDir = structure.modulesDir {
                let children = (try? fileManager.contentsOfDirectory(at: modulesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for child in children {
                    sources[child.lastPathComponent] = child
                }
            }
        }
        return sources
    }

    /// Aggregates Lua module link sources across multiple storage pools.
    func luaModuleLinkSources(in pools: [StoragePool]) -> [String: URL] {
        var aggregated: [String: URL] = [:]
        for pool in pools where pool.isOnline {
            let folder = PathService.shared.dataFolder(.luaScripts, in: pool.url)
            let sources = luaModuleLinkSources(in: folder)
            for (key, val) in sources where aggregated[key] == nil {
                aggregated[key] = val
            }
        }
        return aggregated
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

    /// Checks whether a symlink destination path points into a given storage pool URL,
    /// accounting for path resolution differences (e.g. /var vs /private/var on macOS).
    static func pathBelongsToPool(destination: String?, poolURL: URL) -> Bool {
        guard let destination = destination else { return false }
        let poolPath = poolURL.path
        if destination == poolPath || destination.hasPrefix(poolPath.hasSuffix("/") ? poolPath : poolPath + "/") {
            return true
        }

        // Fast normalization: macOS /var vs /private/var, /tmp vs /private/tmp, etc.
        let normDest = normalizePrivatePrefix(destination)
        let normPool = normalizePrivatePrefix(poolPath)
        if normDest == normPool || normDest.hasPrefix(normPool.hasSuffix("/") ? normPool : normPool + "/") {
            return true
        }

        // Only perform canonical symlink resolution if the target destination actually exists on disk
        // to avoid blocking on unmounted or offline volumes.
        if FileManager.default.fileExists(atPath: destination) {
            let canonicalDest = URL(fileURLWithPath: destination).resolvingSymlinksInPath().path
            let canonicalPool = poolURL.resolvingSymlinksInPath().path
            return canonicalDest == canonicalPool || canonicalDest.hasPrefix(canonicalPool.hasSuffix("/") ? canonicalPool : canonicalPool + "/")
        }

        return false
    }

    private static func normalizePrivatePrefix(_ path: String) -> String {
        if path.hasPrefix("/private/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    /// Removes any symbolic links in targetFolder whose destination resides within poolURL.
    func unlinkPool(at poolURL: URL, in targetFolder: URL) {
        guard fileManager.fileExists(atPath: targetFolder.path),
              let contents = try? fileManager.contentsOfDirectory(at: targetFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        for item in contents {
            if isSymlink(at: item),
               let dest = symlinkDestination(at: item),
               SymlinkService.pathBelongsToPool(destination: dest, poolURL: poolURL) {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    // MARK: - Plugins

    func scanPlugins(dataFolder: URL, targetFolder: URL) throws -> [Plugin] {
        let pool = StoragePool(name: "Default", url: dataFolder, isPrimary: true)
        return try scanPlugins(storagePools: [pool], targetFolder: targetFolder)
    }

    func scanPlugins(storagePools: [StoragePool], targetFolder: URL, knownPlugins: [Plugin] = []) throws -> [Plugin] {
        var list: [Plugin] = []
        var scannedNames = Set<String>()

        for pool in storagePools where pool.isOnline {
            let primaryFolder = PathService.shared.dataFolder(.plugins, in: pool.url)
            let pluginsFolder: URL
            if fileManager.fileExists(atPath: primaryFolder.path) {
                pluginsFolder = primaryFolder
            } else if fileManager.fileExists(atPath: pool.url.path) {
                pluginsFolder = pool.url
            } else {
                continue
            }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: pluginsFolder.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let contents = (try? fileManager.contentsOfDirectory(at: pluginsFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for folder in contents {
                var folderCheck: ObjCBool = false
                if fileManager.fileExists(atPath: folder.path, isDirectory: &folderCheck), folderCheck.boolValue {
                    let folderName = folder.lastPathComponent
                    guard !scannedNames.contains(folderName) else { continue }
                    scannedNames.insert(folderName)

                    let targetLink = targetFolder.appendingPathComponent(folderName)
                    let isEnabled = fileManager.fileExists(atPath: targetLink.path)
                    list.append(Plugin(
                        name: folderName,
                        isEnabled: isEnabled,
                        folderName: folderName,
                        storagePoolId: pool.id,
                        storagePoolName: pool.name,
                        sourceURL: folder,
                        isOffline: false
                    ))
                }
            }
        }

        // Discover any existing symlinks in targetFolder pointing to offline pools
        if fileManager.fileExists(atPath: targetFolder.path),
           let targetContents = try? fileManager.contentsOfDirectory(at: targetFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for linkURL in targetContents {
                if isSymlink(at: linkURL) {
                    let folderName = linkURL.lastPathComponent
                    guard !scannedNames.contains(folderName) else { continue }
                    let dest = symlinkDestination(at: linkURL)
                    let targetExists = fileManager.fileExists(atPath: linkURL.path)
                    let matchingPool = storagePools.first(where: { SymlinkService.pathBelongsToPool(destination: dest, poolURL: $0.url) })
                    if let matchingPool = matchingPool {
                        if !targetExists || !matchingPool.isOnline {
                            scannedNames.insert(folderName)
                            list.append(Plugin(
                                name: folderName,
                                isEnabled: false,
                                folderName: folderName,
                                storagePoolId: matchingPool.id,
                                storagePoolName: matchingPool.name,
                                sourceURL: dest.map { URL(fileURLWithPath: $0) },
                                isOffline: true
                            ))
                        }
                    } else if !targetExists {
                        try? fileManager.removeItem(at: linkURL)
                    }
                }
            }
        }

        // Preserve known items from offline storage pools
        for known in knownPlugins where !scannedNames.contains(known.folderName) {
            let pool = storagePools.first(where: { $0.id == known.storagePoolId })
            let isPoolOffline = pool?.isOnline == false
            if isPoolOffline || (known.isOffline && pool != nil) {
                var offlineItem = known
                offlineItem.isOffline = true
                offlineItem.isEnabled = false
                list.append(offlineItem)
                scannedNames.insert(known.folderName)
            }
        }

        return list.sorted { $0.name < $1.name }
    }

    func setPluginEnabled(folderName: String, enabled: Bool, dataFolder: URL, targetFolder: URL) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(folderName)
        let sourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: dataFolder)
        try setPluginEnabled(folderName: folderName, enabled: enabled, sourceURL: sourceURL, targetFolder: targetFolder)
    }

    func setPluginEnabled(folderName: String, enabled: Bool, sourceURL: URL, targetFolder: URL) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(folderName)
        let linkURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: targetFolder)

        if enabled {
            try createOrReplaceLink(at: linkURL, to: sourceURL)
        } else {
            try removeLink(at: linkURL)
        }
    }

    // MARK: - Aircraft

    func scanAircraft(dataFolder: URL, targetFolder: URL) throws -> [Aircraft] {
        let pool = StoragePool(name: "Default", url: dataFolder, isPrimary: true)
        return try scanAircraft(storagePools: [pool], targetFolder: targetFolder)
    }

    func scanAircraft(storagePools: [StoragePool], targetFolder: URL, knownAircraft: [Aircraft] = []) throws -> [Aircraft] {
        var list: [Aircraft] = []
        var scannedNames = Set<String>()

        for pool in storagePools where pool.isOnline {
            let primaryFolder = PathService.shared.dataFolder(.aircraft, in: pool.url)
            let aircraftFolder: URL
            if fileManager.fileExists(atPath: primaryFolder.path) {
                aircraftFolder = primaryFolder
            } else if fileManager.fileExists(atPath: pool.url.path) {
                aircraftFolder = pool.url
            } else {
                continue
            }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: aircraftFolder.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let contents = (try? fileManager.contentsOfDirectory(at: aircraftFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for folder in contents {
                var folderCheck: ObjCBool = false
                if fileManager.fileExists(atPath: folder.path, isDirectory: &folderCheck), folderCheck.boolValue {
                    let folderName = folder.lastPathComponent
                    guard !scannedNames.contains(folderName) else { continue }
                    scannedNames.insert(folderName)

                    let targetLink = targetFolder.appendingPathComponent(folderName)
                    let isEnabled = fileManager.fileExists(atPath: targetLink.path)
                    list.append(Aircraft(
                        name: folderName,
                        isEnabled: isEnabled,
                        folderName: folderName,
                        storagePoolId: pool.id,
                        storagePoolName: pool.name,
                        sourceURL: folder,
                        isOffline: false
                    ))
                }
            }
        }

        // Discover any existing symlinks in targetFolder pointing to offline pools
        if fileManager.fileExists(atPath: targetFolder.path),
           let targetContents = try? fileManager.contentsOfDirectory(at: targetFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for linkURL in targetContents {
                if isSymlink(at: linkURL) {
                    let folderName = linkURL.lastPathComponent
                    guard !scannedNames.contains(folderName) else { continue }
                    let dest = symlinkDestination(at: linkURL)
                    let targetExists = fileManager.fileExists(atPath: linkURL.path)
                    let matchingPool = storagePools.first(where: { SymlinkService.pathBelongsToPool(destination: dest, poolURL: $0.url) })
                    if let matchingPool = matchingPool {
                        if !targetExists || !matchingPool.isOnline {
                            scannedNames.insert(folderName)
                            list.append(Aircraft(
                                name: folderName,
                                isEnabled: false,
                                folderName: folderName,
                                storagePoolId: matchingPool.id,
                                storagePoolName: matchingPool.name,
                                sourceURL: dest.map { URL(fileURLWithPath: $0) },
                                isOffline: true
                            ))
                        }
                    } else if !targetExists {
                        try? fileManager.removeItem(at: linkURL)
                    }
                }
            }
        }

        // Preserve known items from offline storage pools
        for known in knownAircraft where !scannedNames.contains(known.folderName) {
            let pool = storagePools.first(where: { $0.id == known.storagePoolId })
            let isPoolOffline = pool?.isOnline == false
            if isPoolOffline || (known.isOffline && pool != nil) {
                var offlineItem = known
                offlineItem.isOffline = true
                offlineItem.isEnabled = false
                list.append(offlineItem)
                scannedNames.insert(known.folderName)
            }
        }

        return list.sorted { $0.name < $1.name }
    }

    func setAircraftEnabled(folderName: String, enabled: Bool, dataFolder: URL, targetFolder: URL) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(folderName)
        let sourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: dataFolder)
        try setAircraftEnabled(folderName: folderName, enabled: enabled, sourceURL: sourceURL, targetFolder: targetFolder)
    }

    func setAircraftEnabled(folderName: String, enabled: Bool, sourceURL: URL, targetFolder: URL) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(folderName)
        let linkURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: targetFolder)

        if enabled {
            try createOrReplaceLink(at: linkURL, to: sourceURL)
        } else {
            try removeLink(at: linkURL)
        }
    }

    // MARK: - FlyWithLua Scripts

    func scanLuaScripts(dataFolder: URL, targetFolder: URL?, modulesTargetFolder: URL? = nil) throws -> [LuaScript] {
        let pool = StoragePool(name: "Default", url: dataFolder, isPrimary: true)
        return try scanLuaScripts(storagePools: [pool], targetFolder: targetFolder, modulesTargetFolder: modulesTargetFolder)
    }

    func scanLuaScripts(storagePools: [StoragePool], targetFolder: URL?, modulesTargetFolder: URL? = nil, knownScripts: [LuaScript] = []) throws -> [LuaScript] {
        var list: [LuaScript] = []
        var scannedNames = Set<String>()
        let resolvedModulesFolder = resolveModulesTargetFolder(from: targetFolder, explicitModulesTarget: modulesTargetFolder)

        for pool in storagePools where pool.isOnline {
            let primaryFolder = PathService.shared.dataFolder(.luaScripts, in: pool.url)
            let dataFolder: URL
            if fileManager.fileExists(atPath: primaryFolder.path) {
                dataFolder = primaryFolder
            } else if fileManager.fileExists(atPath: pool.url.path) {
                dataFolder = pool.url
            } else {
                continue
            }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dataFolder.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let contents = (try? fileManager.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for item in contents {
                var folderCheck: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &folderCheck) {
                    let folderName = item.lastPathComponent
                    guard !scannedNames.contains(folderName) else { continue }
                    scannedNames.insert(folderName)
                    let isDirBool = folderCheck.boolValue

                    var isEnabled = false
                    if let targetFolder = targetFolder {
                        if isDirBool {
                            let structure = inspectLuaDirectory(at: item)
                            if structure.isStructured {
                                if let scriptsDir = structure.scriptsDir,
                                   let childContents = try? fileManager.contentsOfDirectory(at: scriptsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                                   let firstChild = childContents.first {
                                    let childLink = targetFolder.appendingPathComponent(firstChild.lastPathComponent)
                                    isEnabled = fileManager.fileExists(atPath: childLink.path)
                                } else if let modulesDir = structure.modulesDir,
                                          let modulesTarget = resolvedModulesFolder,
                                          let childContents = try? fileManager.contentsOfDirectory(at: modulesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                                          let firstChild = childContents.first {
                                    let childLink = modulesTarget.appendingPathComponent(firstChild.lastPathComponent)
                                    isEnabled = fileManager.fileExists(atPath: childLink.path)
                                }
                            } else {
                                if let childContents = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                                   let firstChild = childContents.first {
                                    let childLink = targetFolder.appendingPathComponent(firstChild.lastPathComponent)
                                    isEnabled = fileManager.fileExists(atPath: childLink.path)
                                }
                            }
                        } else {
                            let targetLink = targetFolder.appendingPathComponent(folderName)
                            isEnabled = fileManager.fileExists(atPath: targetLink.path)
                        }
                    }

                    list.append(LuaScript(
                        name: folderName,
                        isEnabled: isEnabled,
                        folderName: folderName,
                        isDirectory: isDirBool,
                        storagePoolId: pool.id,
                        storagePoolName: pool.name,
                        sourceURL: item,
                        isOffline: false
                    ))
                }
            }
        }

        // Discover any existing symlinks in targetFolder pointing to offline pools
        if let targetFolder = targetFolder, fileManager.fileExists(atPath: targetFolder.path),
           let targetContents = try? fileManager.contentsOfDirectory(at: targetFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for linkURL in targetContents {
                if isSymlink(at: linkURL) {
                    let folderName = linkURL.lastPathComponent
                    guard !scannedNames.contains(folderName) else { continue }
                    let dest = symlinkDestination(at: linkURL)
                    let targetExists = fileManager.fileExists(atPath: linkURL.path)
                    let matchingPool = storagePools.first(where: { SymlinkService.pathBelongsToPool(destination: dest, poolURL: $0.url) })
                    if let matchingPool = matchingPool {
                        if !targetExists || !matchingPool.isOnline {
                            scannedNames.insert(folderName)
                            list.append(LuaScript(
                                name: folderName,
                                isEnabled: false,
                                folderName: folderName,
                                isDirectory: false,
                                storagePoolId: matchingPool.id,
                                storagePoolName: matchingPool.name,
                                sourceURL: dest.map { URL(fileURLWithPath: $0) },
                                isOffline: true
                            ))
                        }
                    } else if !targetExists {
                        try? fileManager.removeItem(at: linkURL)
                    }
                }
            }
        }

        // Preserve known items from offline storage pools
        for known in knownScripts where !scannedNames.contains(known.folderName) {
            let pool = storagePools.first(where: { $0.id == known.storagePoolId })
            let isPoolOffline = pool?.isOnline == false
            if isPoolOffline || (known.isOffline && pool != nil) {
                var offlineItem = known
                offlineItem.isOffline = true
                offlineItem.isEnabled = false
                list.append(offlineItem)
                scannedNames.insert(known.folderName)
            }
        }

        return list.sorted { $0.name < $1.name }
    }

    func setLuaScriptEnabled(item: LuaScript, enabled: Bool, dataFolder: URL, targetFolder: URL, modulesTargetFolder: URL? = nil) throws {
        let cleanName = try PathSecurity.sanitizePathComponent(item.folderName)
        let itemSourceURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: dataFolder)
        try setLuaScriptEnabled(item: item, enabled: enabled, sourceURL: itemSourceURL, targetFolder: targetFolder, modulesTargetFolder: modulesTargetFolder)
    }

    func setLuaScriptEnabled(item: LuaScript, enabled: Bool, sourceURL: URL, targetFolder: URL, modulesTargetFolder: URL? = nil) throws {
        let resolvedModulesFolder = resolveModulesTargetFolder(from: targetFolder, explicitModulesTarget: modulesTargetFolder)

        if enabled {
            if item.isDirectory {
                let structure = inspectLuaDirectory(at: sourceURL)
                if structure.isStructured {
                    if let scriptsDir = structure.scriptsDir {
                        try? fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
                        let children = try fileManager.contentsOfDirectory(at: scriptsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                        for child in children {
                            let childCleanName = try PathSecurity.sanitizePathComponent(child.lastPathComponent)
                            let linkURL = try PathSecurity.validateSubpath(relativePath: childCleanName, within: targetFolder)
                            try createOrReplaceLink(at: linkURL, to: child)
                        }
                    }
                    if let modulesDir = structure.modulesDir, let modulesTarget = resolvedModulesFolder {
                        try? fileManager.createDirectory(at: modulesTarget, withIntermediateDirectories: true)
                        let children = try fileManager.contentsOfDirectory(at: modulesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                        for child in children {
                            let childCleanName = try PathSecurity.sanitizePathComponent(child.lastPathComponent)
                            let linkURL = try PathSecurity.validateSubpath(relativePath: childCleanName, within: modulesTarget)
                            try createOrReplaceLink(at: linkURL, to: child)
                        }
                    }
                } else {
                    try? fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
                    let children = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    for child in children {
                        let childCleanName = try PathSecurity.sanitizePathComponent(child.lastPathComponent)
                        let linkURL = try PathSecurity.validateSubpath(relativePath: childCleanName, within: targetFolder)
                        try createOrReplaceLink(at: linkURL, to: child)
                    }
                }
            } else {
                try? fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
                let cleanName = try PathSecurity.sanitizePathComponent(item.folderName)
                let linkURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: targetFolder)
                try createOrReplaceLink(at: linkURL, to: sourceURL)
            }
        } else {
            if item.isDirectory {
                let structure = inspectLuaDirectory(at: sourceURL)
                if structure.isStructured {
                    if let scriptsDir = structure.scriptsDir,
                       let children = try? fileManager.contentsOfDirectory(at: scriptsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for child in children {
                            if let childCleanName = try? PathSecurity.sanitizePathComponent(child.lastPathComponent),
                               let linkURL = try? PathSecurity.validateSubpath(relativePath: childCleanName, within: targetFolder) {
                                try removeLink(at: linkURL)
                            }
                        }
                    }
                    if let modulesDir = structure.modulesDir, let modulesTarget = resolvedModulesFolder,
                       let children = try? fileManager.contentsOfDirectory(at: modulesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for child in children {
                            if let childCleanName = try? PathSecurity.sanitizePathComponent(child.lastPathComponent),
                               let linkURL = try? PathSecurity.validateSubpath(relativePath: childCleanName, within: modulesTarget) {
                                try removeLink(at: linkURL)
                            }
                        }
                    }
                } else {
                    if let children = try? fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for child in children {
                            if let childCleanName = try? PathSecurity.sanitizePathComponent(child.lastPathComponent),
                               let linkURL = try? PathSecurity.validateSubpath(relativePath: childCleanName, within: targetFolder) {
                                try removeLink(at: linkURL)
                            }
                        }
                    }
                }
            } else {
                let cleanName = try PathSecurity.sanitizePathComponent(item.folderName)
                let linkURL = try PathSecurity.validateSubpath(relativePath: cleanName, within: targetFolder)
                try removeLink(at: linkURL)
            }
        }
    }
}
