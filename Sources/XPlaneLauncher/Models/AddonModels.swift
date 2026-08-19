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

struct Plugin: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    var isEnabled: Bool
    let folderName: String

    init(id: UUID = UUID(), name: String, isEnabled: Bool, folderName: String) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.folderName = folderName
    }
}

struct Aircraft: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    var isEnabled: Bool
    let folderName: String

    init(id: UUID = UUID(), name: String, isEnabled: Bool, folderName: String) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.folderName = folderName
    }
}

struct LuaScript: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    var isEnabled: Bool
    let folderName: String
    let isDirectory: Bool

    init(id: UUID = UUID(), name: String, isEnabled: Bool, folderName: String, isDirectory: Bool = false) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.folderName = folderName
        self.isDirectory = isDirectory
    }
}

struct Scenery: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var folderName: String
    var isManaged: Bool
    var isInIni: Bool
    var iniLine: String

    var isToggleable: Bool {
        !folderName.hasPrefix("*")
    }

    init(id: UUID = UUID(), name: String, isEnabled: Bool, folderName: String, isManaged: Bool, isInIni: Bool, iniLine: String) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.folderName = folderName
        self.isManaged = isManaged
        self.isInIni = isInIni
        self.iniLine = iniLine
    }
}

struct SceneryGroup: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var childFolderNames: [String]
    var isExpanded: Bool

    init(id: UUID = UUID(), name: String, childFolderNames: [String] = [], isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.childFolderNames = childFolderNames
        self.isExpanded = isExpanded
    }
}

struct ScriptEnvVar: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

struct ProfileScript: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var path: String
    var isEnabled: Bool

    init(id: UUID = UUID(), path: String, isEnabled: Bool = true) {
        self.id = id
        self.path = path
        self.isEnabled = isEnabled
    }
}

struct PluginProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var pluginFolderNames: [String]
    var sceneryFolderNames: [String]
    var aircraftFolderNames: [String]
    var luaScriptFolderNames: [String]
    var shellScriptPath: String?
    var scripts: [ProfileScript]
    var environmentVariables: [ScriptEnvVar]

    enum CodingKeys: String, CodingKey {
        case id, name, pluginFolderNames, sceneryFolderNames, aircraftFolderNames, luaScriptFolderNames, shellScriptPath, scripts, environmentVariables
    }

    init(
        id: UUID = UUID(),
        name: String,
        pluginFolderNames: [String],
        sceneryFolderNames: [String] = [],
        aircraftFolderNames: [String] = [],
        luaScriptFolderNames: [String] = [],
        shellScriptPath: String? = nil,
        scripts: [ProfileScript] = [],
        environmentVariables: [ScriptEnvVar] = []
    ) {
        self.id = id
        self.name = name
        self.pluginFolderNames = pluginFolderNames
        self.sceneryFolderNames = sceneryFolderNames
        self.aircraftFolderNames = aircraftFolderNames
        self.luaScriptFolderNames = luaScriptFolderNames
        self.shellScriptPath = shellScriptPath
        self.scripts = scripts
        self.environmentVariables = environmentVariables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.pluginFolderNames = try container.decode([String].self, forKey: .pluginFolderNames)
        self.sceneryFolderNames = try container.decodeIfPresent([String].self, forKey: .sceneryFolderNames) ?? []
        self.aircraftFolderNames = try container.decodeIfPresent([String].self, forKey: .aircraftFolderNames) ?? []
        self.luaScriptFolderNames = try container.decodeIfPresent([String].self, forKey: .luaScriptFolderNames) ?? []
        self.shellScriptPath = try container.decodeIfPresent(String.self, forKey: .shellScriptPath)
        self.scripts = try container.decodeIfPresent([ProfileScript].self, forKey: .scripts) ?? []
        self.environmentVariables = try container.decodeIfPresent([ScriptEnvVar].self, forKey: .environmentVariables) ?? []
    }
}
