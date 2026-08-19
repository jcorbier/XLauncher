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

// MARK: - CSL Lights Data & Definitions

final class CSLLightsData: Sendable {
    static let shared = CSLLightsData()

    let spillReduceFactors: [String: Double] = [
        "airplane_landing": 1.0,
        "airplane_taxi": 0.75,
        "airplane_nav": 0.30,
        "airplane_beacon": 0.35,
        "airplane_strobe": 0.50
    ]

    let airbusICAOIdentifiers: Set<String> = [
        "A19N", "A20N", "A21N", "A306", "A30B", "A310",
        "A318", "A319", "A320", "A321", "A332", "A333",
        "A337", "A338", "A339", "A342", "A343", "A345",
        "A346", "A359", "A35K", "A388", "A3ST", "BCS1", "BCS3"
    ]

    private let aircraftCategories: [String: Set<String>]
    private let flashingBeaconAircraft: Set<String>
    private let lightParamsPerCategory: [String: [String: [String: String]]]

    init() {
        // Load aircraft categories from embedded JSON
        if let aircraftData = CSLLightsData.embeddedAircraftsJSON.data(using: .utf8),
           let rawCategories = try? JSONDecoder().decode([String: [String]].self, from: aircraftData) {
            var categories: [String: Set<String>] = [:]
            var flashing: Set<String> = []
            for (key, list) in rawCategories {
                if key == "aircraft_with_flashing_beacons" {
                    flashing = Set(list)
                } else {
                    categories[key] = Set(list)
                }
            }
            self.aircraftCategories = categories
            self.flashingBeaconAircraft = flashing
        } else {
            self.aircraftCategories = [:]
            self.flashingBeaconAircraft = []
        }

        // Load light parameters from embedded JSON
        if let lightData = CSLLightsData.embeddedLightParamsJSON.data(using: .utf8),
           let params = try? JSONDecoder().decode([String: [String: [String: String]]].self, from: lightData) {
            self.lightParamsPerCategory = params
        } else {
            self.lightParamsPerCategory = [:]
        }
    }

    func category(for icao: String) -> String {
        for (cat, list) in aircraftCategories {
            if list.contains(icao) {
                return cat
            }
        }
        return "default"
    }

    func hasFlashingBeacons(icao: String) -> Bool {
        flashingBeaconAircraft.contains(icao) || airbusICAOIdentifiers.contains(icao)
    }

    func lightParams(for icao: String) -> [String: [String: String]] {
        let cat = category(for: icao)
        return lightParamsPerCategory[cat] ?? lightParamsPerCategory["default"] ?? [:]
    }
}

// MARK: - Native CSL Lights Updater Engine

final class CSLLightsUpdater: Sendable {
    static let shared = CSLLightsUpdater()
    private var fileManager: FileManager { .default }
    private let data = CSLLightsData.shared

    static let backupExtension = "bak"
    static let tempSuffix = ".TEMP"

    private let ignoreObjects: Set<String> = [
        "glass", "prop", "propdisc", "zzz", "contrail", "fan", "rotor", "car", "blur", "engineprop"
    ]

    // MARK: - Object Conversion

    func convertObjectContent(content: String, icao: String, flashingBeacons: Bool = true) -> String? {
        guard !content.isEmpty else { return nil }

        // Split at ANIM_begin
        let animMarker = "ANIM_begin"
        guard let range = content.range(of: animMarker) else {
            return nil
        }

        let objectDefinitions = String(content[..<range.lowerBound])
        let animationsSection = String(content[range.lowerBound...])

        let newAnimations = processAnimationsSection(
            animations: animationsSection,
            icao: icao,
            flashingBeacons: flashingBeacons
        )

        return objectDefinitions + newAnimations
    }

    private func processAnimationsSection(animations: String, icao: String, flashingBeacons: Bool) -> String {
        let lightParams = data.lightParams(for: icao)
        let isAirbus = data.airbusICAOIdentifiers.contains(icao)
        let useFlashingBeacon = flashingBeacons && (data.hasFlashingBeacons(icao: icao) || isAirbus)

        // Match all ANIM_begin ... ANIM_end blocks
        let pattern = #"(?s)ANIM_begin.*?ANIM_end"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return animations }

        let nsString = animations as NSString
        let matches = regex.matches(in: animations, range: NSRange(location: 0, length: nsString.length))

        var result = animations

        for match in matches.reversed() {
            let animBlock = nsString.substring(with: match.range)

            if animBlock.contains("libxplanemp/controls/landing_lites_on") {
                let params = lightParams["airplane_landing"] ?? [:]
                let converted = convertLandingLights(animation: animBlock, params: params)
                result = (result as NSString).replacingCharacters(in: match.range, with: converted) as String
            } else if animBlock.contains("libxplanemp/controls/taxi_lites_on") {
                let params = lightParams["airplane_taxi"] ?? [:]
                let converted = convertTaxiLights(animation: animBlock, params: params)
                result = (result as NSString).replacingCharacters(in: match.range, with: converted) as String
            } else if animBlock.contains("libxplanemp/controls/nav_lites_on") {
                let params = lightParams["airplane_nav"] ?? [:]
                let converted = convertNavLights(animation: animBlock, params: params)
                result = (result as NSString).replacingCharacters(in: match.range, with: converted) as String
            } else if animBlock.contains("libxplanemp/controls/strobe_lites_on") {
                let params = lightParams["airplane_strobe"] ?? [:]
                let converted = convertStrobeLights(animation: animBlock, params: params, isAirbus: isAirbus)
                result = (result as NSString).replacingCharacters(in: match.range, with: converted) as String
            } else if animBlock.contains("libxplanemp/controls/beacon_lites_on") {
                let params = lightParams["airplane_beacon"] ?? [:]
                let converted = convertBeaconLights(animation: animBlock, params: params, flashing: useFlashingBeacon, isAirbus: isAirbus)
                result = (result as NSString).replacingCharacters(in: match.range, with: converted) as String
            }
        }

        return result
    }

    // MARK: - Light Type Converters

    private func convertLandingLights(animation: String, params: [String: String]) -> String {
        var anim = convertCommonLights(animation: animation, params: params, lightType: "airplane_landing")

        if !anim.contains("libxplanemp/controls/gear_ratio") {
            anim = fixLandingGearHide(animation: anim)
        }
        return anim
    }

    private func convertTaxiLights(animation: String, params: [String: String]) -> String {
        var anim = animation.replacingOccurrences(of: "landing_lites_on", with: "taxi_lites_on")
        anim = convertCommonLights(animation: anim, params: params, lightType: "airplane_taxi")

        if !anim.contains("libxplanemp/controls/gear_ratio") {
            anim = fixTaxiGearHide(animation: anim)
        }
        return anim
    }

    private func convertNavLights(animation: String, params: [String: String]) -> String {
        convertCommonLights(animation: animation, params: params, lightType: "airplane_nav")
    }

    private func convertStrobeLights(animation: String, params: [String: String], isAirbus: Bool) -> String {
        var anim = animation
        if anim.contains("sim/time/total_running_time_sec") {
            anim = removeFlashingSequences(animation: anim, lightType: "airplane_strobe")
        }

        let flashSeq = isAirbus ? randomAirbusStrobeSequence() : randomStrobeSequence()
        let newAnimHide = """
            ANIM_hide    -1.0    0    libxplanemp/controls/strobe_lites_on
        \(flashSeq)
            ANIM_keyframe_loop 1.5
        """

        var converted = convertCommonLights(animation: anim, params: params, lightType: "airplane_strobe")

        let pattern = #"ANIM_hide[^\n]+libxplanemp/controls/strobe_lites_on"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: converted, range: NSRange(location: 0, length: (converted as NSString).length)) {
            converted = (converted as NSString).replacingCharacters(in: match.range, with: newAnimHide) as String
        }

        converted = converted.replacingOccurrences(of: "airplane_strobe", with: "airplane_generic")
        return cleanEmptyLines(converted)
    }

    private func convertBeaconLights(animation: String, params: [String: String], flashing: Bool, isAirbus: Bool) -> String {
        var anim = animation
        if anim.contains("sim/time/total_running_time_sec") {
            anim = removeFlashingSequences(animation: anim, lightType: "airplane_beacon")
        }

        var converted = convertCommonLights(animation: anim, params: params, lightType: "airplane_beacon")

        if flashing {
            let loopDuration = isAirbus ? 1.0 : 2.0
            let flashSeq = randomBeaconSequence(loopDuration: loopDuration)
            let newAnimHide = """
                ANIM_hide	-1.0 0.0	libxplanemp/controls/beacon_lites_on
            \(flashSeq)
                ANIM_keyframe_loop \(String(format: "%.1f", loopDuration))
            """

            let pattern = #"ANIM_hide[^\n]+libxplanemp/controls/beacon_lites_on"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: converted, range: NSRange(location: 0, length: (converted as NSString).length)) {
                converted = (converted as NSString).replacingCharacters(in: match.range, with: newAnimHide) as String
            }

            converted = converted.replacingOccurrences(of: "airplane_beacon", with: "airplane_generic")
            converted = increaseBeaconIntensity(animation: converted)
        }

        return cleanEmptyLines(converted)
    }

    // MARK: - Common Lights Converter

    private func convertCommonLights(animation: String, params: [String: String], lightType: String) -> String {
        var anim = animation
        anim = anim.replacingOccurrences(of: "LIGHT_NAMED", with: "LIGHT_PARAM")
        anim = anim.replacingOccurrences(of: "\t", with: "    ")
        anim = anim.replacingOccurrences(of: "_pm", with: "")

        // Remove ANIM_show
        let animShowPattern = #"ANIM_show[^\n]+lites_on"#
        if let regex = try? NSRegularExpression(pattern: animShowPattern) {
            anim = regex.stringByReplacingMatches(in: anim, range: NSRange(location: 0, length: (anim as NSString).length), withTemplate: "")
        }

        var knownCoordinates = Set<String>()
        var lines = anim.components(separatedBy: .newlines)
        var extraTailAnim = ""

        for (i, line) in lines.enumerated() {
            if line.contains("headlight") || line.contains("airplane_beacon_rotate_sp") {
                lines[i] = ""
                continue
            }

            guard line.contains(lightType) else { continue }
            guard line.rangeOfCharacter(from: .decimalDigits) != nil else { continue }
            if line.contains("_size") || line.contains("#~") {
                lines[i] = ""
                continue
            }

            let cleanedLine = line.replacingOccurrences(of: "#", with: "")
            let tokens = cleanedLine.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 5 else { continue }

            // Tokens: [0] = LIGHT_PARAM, [1] = light_name, [2] = X, [3] = Y, [4] = Z
            let xStr = tokens[2]
            let yStr = tokens[3]
            let zStr = tokens[4]
            let coordinates = "\(xStr)    \(yStr)    \(zStr)"

            if knownCoordinates.contains(coordinates) {
                lines[i] = ""
                continue
            }
            knownCoordinates.insert(coordinates)

            let leadingSpaces = line.prefix(while: \.isWhitespace)
            let currentLightType = lightType
            var positionSuffix = ""

            let xVal = Double(xStr) ?? 0.0
            let yVal = Double(yStr) ?? 0.0
            let zVal = Double(zStr) ?? 0.0

            if lightType == "airplane_nav" {
                if xVal > -0.50 && xVal < 0.50 {
                    positionSuffix = "_tail"
                } else if xVal < -0.50 {
                    positionSuffix = "_left"
                } else {
                    positionSuffix = "_right"
                }

                if positionSuffix == "_tail" {
                    lines[i] = ""
                    let tailParam = params["airplane_nav_tail"] ?? ""
                    let tailBB = "LIGHT_PARAM airplane_nav_bb \(coordinates) \(tailParam)"
                    var tailPM = tailBB.replacingOccurrences(of: "_bb", with: "_pm")
                    tailPM = reduceSpillIntensity(line: tailPM, lightType: "airplane_nav")

                    extraTailAnim += """

                    # New animation created for tail lights by lights_updater
                    ANIM_begin
                        ANIM_hide    -1.0    0    libxplanemp/controls/nav_lites_on
                            \(tailBB)
                            \(tailPM)
                    ANIM_end
                    """
                    continue
                }
            } else if lightType == "airplane_strobe" {
                if xVal == 0 && yVal > 1.0 && zVal < 20 {
                    positionSuffix = "_upper"
                } else if xVal == 0 && yVal < 1.0 && zVal < 20 {
                    positionSuffix = "_lower"
                } else if xVal < -0.50 {
                    positionSuffix = "_left"
                } else if xVal > 0.50 {
                    positionSuffix = "_right"
                } else {
                    positionSuffix = "_tail"
                }
            }

            let lookupKey = "\(currentLightType)\(positionSuffix)"
            let lineEnd = params[lookupKey] ?? params[currentLightType] ?? ""

            let billboardLine = "LIGHT_PARAM    \(currentLightType)_bb   \(coordinates)   \(lineEnd)"
            var spillLine = billboardLine.replacingOccurrences(of: "_bb", with: "_pm")
            spillLine = reduceSpillIntensity(line: spillLine, lightType: currentLightType)

            lines[i] = "\(leadingSpaces)\(billboardLine)\n\(leadingSpaces)\(spillLine)"
        }

        var combined = cleanEmptyLines(lines.joined(separator: "\n"))
        if !extraTailAnim.isEmpty {
            combined += extraTailAnim
        }
        return combined
    }

    // MARK: - Helpers

    private func reduceSpillIntensity(line: String, lightType: String) -> String {
        let factor = data.spillReduceFactors[lightType] ?? 0.5

        let pattern = #"\b(\d+)cd\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return line
        }

        let cdStr = (line as NSString).substring(with: match.range(at: 1))
        guard let val = Double(cdStr) else { return line }
        let reduced = Int(val * factor)

        return (line as NSString).replacingCharacters(in: match.range, with: "\(reduced)cd") as String
    }

    private func increaseBeaconIntensity(animation: String) -> String {
        let pattern = #"\b(\d+)cd\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return animation }

        let nsStr = animation as NSString
        let matches = regex.matches(in: animation, range: NSRange(location: 0, length: nsStr.length))
        var result = animation

        for match in matches.reversed() {
            let cdStr = (result as NSString).substring(with: match.range(at: 1))
            if let val = Double(cdStr) {
                let increased = Int(val * 2.0)
                result = (result as NSString).replacingCharacters(in: match.range, with: "\(increased)cd") as String
            }
        }
        return result
    }

    private func removeFlashingSequences(animation: String, lightType: String) -> String {
        let pattern = #"(?s)(ANIM_hide.+?sim/time/total_running_time_sec.+?ANIM_keyframe_loop\s+\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return animation }

        let lightName = lightType.split(separator: "_").last.map(String.init) ?? lightType
        let replacement = "ANIM_hide -1.000000 0.000000 libxplanemp/controls/\(lightName)_lites_on"

        return regex.stringByReplacingMatches(in: animation, range: NSRange(location: 0, length: (animation as NSString).length), withTemplate: replacement)
    }

    private func fixLandingGearHide(animation: String) -> String {
        let lightParamPattern = #"LIGHT_PARAM\s+airplane_landing\S*\s+([-\d\.]+)"#
        guard let regex = try? NSRegularExpression(pattern: lightParamPattern),
              let match = regex.firstMatch(in: animation, range: NSRange(location: 0, length: (animation as NSString).length)) else {
            return animation
        }

        let xStr = (animation as NSString).substring(with: match.range(at: 1))
        guard let xVal = Double(xStr), abs(xVal) < 0.40 else { return animation }

        let hidePattern = #"ANIM_hide[^\n]+libxplanemp/controls/landing_lites_on"#
        guard let hideRegex = try? NSRegularExpression(pattern: hidePattern),
              let hideMatch = hideRegex.firstMatch(in: animation, range: NSRange(location: 0, length: (animation as NSString).length)) else {
            return animation
        }

        let hideLine = (animation as NSString).substring(with: hideMatch.range)
        let extraHide = "ANIM_hide -1.000000 0.800000 libxplanemp/controls/gear_ratio"
        let replacement = "\(hideLine)\n\t\(extraHide)"

        return (animation as NSString).replacingCharacters(in: hideMatch.range, with: replacement) as String
    }

    private func fixTaxiGearHide(animation: String) -> String {
        let hidePattern = #"ANIM_hide[^\n]+libxplanemp/controls/taxi_lites_on"#
        guard let hideRegex = try? NSRegularExpression(pattern: hidePattern),
              let hideMatch = hideRegex.firstMatch(in: animation, range: NSRange(location: 0, length: (animation as NSString).length)) else {
            return animation
        }

        let hideLine = (animation as NSString).substring(with: hideMatch.range)
        let extraHide = "ANIM_hide -1.000000 0.800000 libxplanemp/controls/gear_ratio"
        let replacement = "\(hideLine)\n\t\(extraHide)"

        return (animation as NSString).replacingCharacters(in: hideMatch.range, with: replacement) as String
    }

    private func cleanEmptyLines(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Flash Sequence Generators

    private func randomStrobeSequence() -> String {
        let offsets = [0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00, 1.10, 1.20, 1.30, 1.40]
        let offset = offsets.randomElement() ?? 0.30
        let end1 = offset + 0.05
        return """
            ANIM_hide    0.0 \(String(format: "%.2f", offset))   sim/time/total_running_time_sec
            ANIM_keyframe_loop 1.5
            ANIM_hide    \(String(format: "%.2f", end1)) 1.5   sim/time/total_running_time_sec
        """
    }

    private func randomAirbusStrobeSequence() -> String {
        let offsets = [0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00, 1.10, 1.20, 1.30]
        let offset = offsets.randomElement() ?? 0.30
        let gapStart = offset + 0.05
        let pulse2Start = offset + 0.10
        let pulse2End = pulse2Start + 0.05
        return """
            ANIM_hide    0.0 \(String(format: "%.2f", offset))   sim/time/total_running_time_sec
            ANIM_keyframe_loop 1.5
            ANIM_hide    \(String(format: "%.2f", gapStart)) \(String(format: "%.2f", pulse2Start))   sim/time/total_running_time_sec
            ANIM_keyframe_loop 1.5
            ANIM_hide    \(String(format: "%.2f", pulse2End)) 1.5   sim/time/total_running_time_sec
        """
    }

    private func randomBeaconSequence(loopDuration: Double) -> String {
        let step = loopDuration / 10.0
        let idx = Int.random(in: 1...9)
        let t1 = Double(idx) * step
        let t2 = t1 + (step * 0.5)
        return """
            ANIM_hide    0.0 \(String(format: "%.2f", t1))   sim/time/total_running_time_sec
            ANIM_keyframe_loop \(String(format: "%.1f", loopDuration))
            ANIM_hide    \(String(format: "%.2f", t2)) \(String(format: "%.1f", loopDuration))   sim/time/total_running_time_sec
        """
    }

    // MARK: - Package Processing & Reverting

    func processPackage(packageURL: URL, flashingBeacons: Bool = true, onLog: ((String) -> Void)? = nil) {
        let xsbFile = packageURL.appendingPathComponent("xsb_aircraft.txt")
        guard fileManager.fileExists(atPath: xsbFile.path) else { return }

        guard let content = try? String(contentsOf: xsbFile, encoding: .utf8) else { return }

        // Remove xpmp2 cache files
        removeXPMP2Files(in: packageURL)

        // Parse xsb_aircraft.txt for aircraft objects
        let aircraftObjects = parseXSB(content: content, parentDir: packageURL)
        for obj in aircraftObjects {
            let fileURL = obj.fileURL
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }

            // Backup to .bak if not already backed up
            let bakURL = fileURL.deletingPathExtension().appendingPathExtension(CSLLightsUpdater.backupExtension)
            if !fileManager.fileExists(atPath: bakURL.path) {
                try? fileManager.copyItem(at: fileURL, to: bakURL)
            }

            guard let objContent = try? String(contentsOf: bakURL, encoding: .utf8) else { continue }
            if let converted = convertObjectContent(content: objContent, icao: obj.icao, flashingBeacons: flashingBeacons) {
                try? converted.write(to: fileURL, atomically: true, encoding: .utf8)
                onLog?("[XP12 Lights] Converted \(fileURL.lastPathComponent) (\(obj.icao))")
            }
        }
    }

    func revertPackage(packageURL: URL, onLog: ((String) -> Void)? = nil) {
        removeXPMP2Files(in: packageURL)

        guard let enumerator = fileManager.enumerator(at: packageURL, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == CSLLightsUpdater.backupExtension {
                let targetObjURL = fileURL.deletingPathExtension().appendingPathExtension("obj")
                try? fileManager.removeItem(at: targetObjURL)
                try? fileManager.moveItem(at: fileURL, to: targetObjURL)
                onLog?("[XP12 Lights] Restored original \(targetObjURL.lastPathComponent)")
            }
        }
    }

    func removeXPMP2Files(in folderURL: URL) {
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.lowercased().hasSuffix("xpmp2.obj") {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private struct XSBObject {
        let icao: String
        let fileURL: URL
    }

    private func parseXSB(content: String, parentDir: URL) -> [XSBObject] {
        var results: [XSBObject] = []
        let blocks = content.components(separatedBy: "OBJ8_AIRCRAFT")

        for block in blocks {
            var icao = "default"
            var objPaths: [String] = []

            let lines = block.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
                if tokens.count >= 2 && (tokens[0] == "ICAO" || tokens[0] == "MATCHES" || tokens[0] == "AIRLINE" || tokens[0] == "LIVERY") {
                    icao = tokens[1]
                } else if tokens.count >= 4 && tokens[0] == "OBJ8" {
                    let rawPath = tokens[3]
                    // Path format: PackageName/subpath.obj
                    let subParts = rawPath.split(whereSeparator: { $0 == "/" || $0 == "\\" || $0 == ":" })
                    if subParts.count > 1 {
                        let pathWithoutPkg = subParts.dropFirst().joined(separator: "/")
                        let lower = pathWithoutPkg.lowercased()
                        if !ignoreObjects.contains(where: { lower.contains($0) }) {
                            objPaths.append(pathWithoutPkg)
                        }
                    }
                }
            }

            for p in objPaths {
                var fileURL = parentDir.appendingPathComponent(p)
                if !fileManager.fileExists(atPath: fileURL.path) {
                    fileURL = parentDir.appendingPathComponent(p.replacingOccurrences(of: ".OBJ", with: ".obj"))
                }
                results.append(XSBObject(icao: icao, fileURL: fileURL))
            }
        }
        return results
    }
}
