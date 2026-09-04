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

final class AddonCategorizationService: Sendable {
    static let shared = AddonCategorizationService()

    private var fileManager: FileManager { FileManager.default }

    init() {}

    // MARK: - Aircraft Heuristic Classification

    func detectAircraftCategory(name: String, folderName: String, folderURL: URL?) -> AircraftCategory {
        let combined = "\(name) \(folderName)".lowercased()
        let tokens = combined.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }

        // 1. Helicopter detection
        let heloKeywords = [
            "helo", "helicopter", "rotor", "bell", "robinson", "ec135", "ec145", "h145", "h125", "h135",
            "uh-60", "blackhawk", "sikorsky", "ch-47", "chinook", "aw139", "aw109",
            "as350", "bo105", "cabri", "ka-52", "mi-8", "mi-24"
        ]
        let heloExactTokens = ["r22", "r44", "r66"]
        if heloKeywords.contains(where: { combined.contains($0) }) ||
           heloExactTokens.contains(where: { tokens.contains($0) }) {
            return .helicopter
        }

        // 2. Military detection
        let militaryKeywords = [
            "f-14", "f-15", "f-16", "f-18", "f/a-18", "fa-18", "f-22", "f-35", "eurofighter", "typhoon",
            "rafale", "mirage", "mig-", "mig21", "mig29", "su-25", "su-27", "su-33", "su-57", "c-130",
            "hercules", "a-10", "warthog", "tornado", "harrier", "gripen", "military", "fighter", "bomber",
            "stealth", "blackbird", "sr-71", "b-52", "b-1b", "b-2", "vulcan", "f4u", "p-51", "spitfire", "bf109"
        ]
        if militaryKeywords.contains(where: { combined.contains($0) }) {
            return .military
        }

        // 3. Airliner detection
        let airlinerKeywords = [
            "a300", "a310", "a318", "a319", "a320", "a321", "a330", "a340", "a350", "a380",
            "b707", "b717", "b727", "b737", "b747", "b757", "b767", "b777", "b787",
            "737", "747", "757", "767", "777", "787", "727", "717",
            "e170", "e175", "e190", "e195", "erj", "crj", "md-11", "md-80", "md-82", "md-88", "md-90",
            "dc-9", "dc-10", "q400", "dash 8", "dash-8", "atr 42", "atr 72", "atr-42", "atr-72",
            "saab 340", "ba146", "rj85", "concorde", "tu-154", "il-96", "airliner", "airbus", "boeing",
            "embraer", "bombardier", "toliss", "zibo", "flightfactor", "ixeg", "rotate", "felis"
        ]
        if airlinerKeywords.contains(where: { combined.contains($0) }) {
            return .airliner
        }

        // 4. General Aviation detection
        let gaKeywords = [
            "c150", "c152", "c172", "c182", "c206", "c208", "c210", "c310", "c340", "c414", "c421",
            "caravan", "cessna", "skyhawk", "skylane", "stationair",
            "pa-28", "pa28", "pa-32", "pa-34", "pa-44", "archer", "arrow", "cherokee", "seneca", "seminole",
            "warrior", "malibu", "cub", "super cub", "piper",
            "baron", "bonanza", "king air", "kingair", "beechcraft", "c90", "b200", "b350",
            "sr20", "sr22", "vision jet", "sf50", "cirrus",
            "da20", "da40", "da42", "da62", "diamond",
            "mooney", "robin", "dr400", "extra 300", "pitts", "rv-", "rv6", "rv7", "rv8", "rv10", "tecnam",
            "glider", "aerobatic", "bush"
        ]
        if gaKeywords.contains(where: { combined.contains($0) }) {
            return .generalAviation
        }

        // 5. Deep inspection of .acf file if folderURL is available
        if let url = folderURL, fileManager.fileExists(atPath: url.path) {
            if let acfCat = inspectAircraftFiles(at: url) {
                return acfCat
            }
        }

        return .generalAviation
    }

    private func inspectAircraftFiles(at url: URL) -> AircraftCategory? {
        guard let files = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }

        for file in files where file.pathExtension.lowercased() == "acf" {
            let filename = file.lastPathComponent.lowercased()
            if filename.contains("helo") || filename.contains("rotor") || filename.contains("bell") {
                return .helicopter
            }

            if let data = try? Data(contentsOf: file),
               let content = String(data: data.prefix(10000), encoding: .utf8) {
                let lower = content.lowercased()
                if lower.contains("is_helo 1") || lower.contains("helo_type") {
                    return .helicopter
                }
                if lower.contains("fighter") || lower.contains("military") {
                    return .military
                }
            }
        }
        return nil
    }

    // MARK: - Scenery Heuristic Classification

    func detectSceneryCategory(name: String, folderName: String, folderURL: URL?) -> SceneryTypeCategory {
        let combined = "\(name) \(folderName)".lowercased()

        // 1. Mesh & Ortho check (checked first to prevent simheaven/ortho overlays from matching libraries)
        let orthoKeywords = ["zortho", "yortho", "ortho", "photoreal", "mesh", "dem", "simheaven", "x-world", "w2xp"]
        if orthoKeywords.contains(where: { combined.contains($0) }) {
            return .meshOrtho
        }
        if let url = folderURL {
            let earthNav = url.appendingPathComponent("Earth nav data")
            let aptDat = url.appendingPathComponent("Earth nav data/apt.dat")
            if fileManager.fileExists(atPath: earthNav.path) && !fileManager.fileExists(atPath: aptDat.path) {
                return .meshOrtho
            }
        }

        // 2. Library check (known libraries or library.txt)
        if let url = folderURL {
            let libTxt = url.appendingPathComponent("library.txt")
            if fileManager.fileExists(atPath: libTxt.path) {
                return .library
            }
        }
        for known in AddonDiagnosticsService.knownLibraries {
            if known.identifier == "simheaven_xworld" { continue }
            if known.prefixKeys.contains(where: { combined.contains($0.lowercased()) }) {
                return .library
            }
        }

        // 2. Airport check (apt.dat or ICAO patterns)
        if let url = folderURL {
            let aptDat = url.appendingPathComponent("Earth nav data/apt.dat")
            if fileManager.fileExists(atPath: aptDat.path) {
                return .airport
            }
        }
        let airportKeywords = ["airport", "airfield", "intl", "international", "aerodrome", "flytampa", "orbx", "aerosoft", "justsim"]
        if airportKeywords.contains(where: { combined.contains($0) }) {
            return .airport
        }
        // 4-letter ICAO prefix check (e.g. "LFPG", "KLAX", "EGLL", "EDDF")
        let words = folderName.components(separatedBy: CharacterSet(charactersIn: "_ -"))
        for word in words where word.count == 4 && word == word.uppercased() && word.range(of: "^[A-Z]{4}$", options: .regularExpression) != nil {
            return .airport
        }


        // 4. Landmarks check
        let landmarkKeywords = ["landmark", "landmarks", "city", "bridges", "buildings", "poi", "vfr", "monuments"]
        if landmarkKeywords.contains(where: { combined.contains($0) }) {
            return .landmark
        }

        return .other
    }

    // MARK: - Plugin Heuristic Classification

    func detectPluginCategory(name: String, folderName: String) -> PluginTypeCategory {
        let combined = "\(name) \(folderName)".lowercased()

        // 1. Traffic plugins
        let trafficKeywords = ["xpilot", "ivao", "livetraffic", "traffic", "atc", "vatsim", "poscon", "tc_traffic", "chatter", "radarcontact"]
        if trafficKeywords.contains(where: { combined.contains($0) }) {
            return .traffic
        }

        // 2. Weather & Environment
        let weatherKeywords = ["weather", "activesky", "noaa", "cloud", "clouds", "seasons", "visualxp", "skymaxx", "ultraweather", "xenviro", "shade", "atmosphere"]
        if weatherKeywords.contains(where: { combined.contains($0) }) {
            return .weather
        }

        // 3. Sound plugins
        let soundKeywords = ["fmod", "sound", "bss", "audio", "soundpack", "x-sound", "ftsim", "radio"]
        if soundKeywords.contains(where: { combined.contains($0) }) {
            return .sound
        }

        // 4. Utilities
        let utilityKeywords = [
            "flywithlua", "datareftool", "betterpushback", "autogate", "avitab", "terrainradar",
            "webfmc", "headshake", "autosave", "xorganizer", "utility", "tools", "gizmo", "sasl",
            "plugin", "system", "cockpit", "checklist", "view", "camera"
        ]
        if utilityKeywords.contains(where: { combined.contains($0) }) {
            return .utilities
        }

        return .utilities
    }
}
