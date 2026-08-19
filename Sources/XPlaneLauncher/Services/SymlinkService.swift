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
            if !fileManager.fileExists(atPath: linkURL.path) {
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
            }
        } else {
            if fileManager.fileExists(atPath: linkURL.path) {
                try fileManager.removeItem(at: linkURL)
            }
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
            if !fileManager.fileExists(atPath: linkURL.path) {
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: sourceURL)
            }
        } else {
            if fileManager.fileExists(atPath: linkURL.path) {
                try fileManager.removeItem(at: linkURL)
            }
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
                    if fileManager.fileExists(atPath: linkURL.path) {
                        try fileManager.removeItem(at: linkURL)
                    }
                    try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: child)
                }
            } else {
                let linkURL = targetFolder.appendingPathComponent(item.folderName)
                if fileManager.fileExists(atPath: linkURL.path) {
                    try fileManager.removeItem(at: linkURL)
                }
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: itemSourceURL)
            }
        } else {
            if item.isDirectory {
                if let children = try? fileManager.contentsOfDirectory(at: itemSourceURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for child in children {
                        let linkURL = targetFolder.appendingPathComponent(child.lastPathComponent)
                        if fileManager.fileExists(atPath: linkURL.path) {
                            try fileManager.removeItem(at: linkURL)
                        }
                    }
                }
            } else {
                let linkURL = targetFolder.appendingPathComponent(item.folderName)
                if fileManager.fileExists(atPath: linkURL.path) {
                    try fileManager.removeItem(at: linkURL)
                }
            }
        }
    }
}
