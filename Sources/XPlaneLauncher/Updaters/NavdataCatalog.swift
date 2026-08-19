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

public struct NavdataAddonDefinition: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var formatKey: String
    public var relativeTargetPath: String
    public var masterfile: String?
    public var isCustom: Bool

    public init(
        id: String,
        name: String,
        formatKey: String,
        relativeTargetPath: String,
        masterfile: String? = nil,
        isCustom: Bool = true
    ) {
        self.id = id
        self.name = name
        self.formatKey = formatKey
        self.relativeTargetPath = relativeTargetPath
        self.masterfile = masterfile
        self.isCustom = isCustom
    }
}

public enum NavdataCatalog {
    public static func loadCustomAddons() -> [NavdataAddonDefinition] {
        guard let data = UserDefaults.standard.data(forKey: .customNavdataAddonMappings),
              let list = try? JSONDecoder().decode([NavdataAddonDefinition].self, from: data) else {
            return []
        }
        return list
    }

    public static func saveCustomAddon(_ addon: NavdataAddonDefinition) {
        var list = loadCustomAddons().filter { $0.id != addon.id }
        list.append(addon)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: .customNavdataAddonMappings)
        }
    }

    public static func deleteCustomAddon(id: String) {
        let list = loadCustomAddons().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: .customNavdataAddonMappings)
        }
    }
}
