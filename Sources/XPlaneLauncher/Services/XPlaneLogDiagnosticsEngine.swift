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

public final class XPlaneLogDiagnosticsEngine: Sendable {
    public static let shared = XPlaneLogDiagnosticsEngine()

    public init() {}

    public func analyze(entries: [XPlaneLogEntry], fileItem: LogFileItem) -> LogAnalysisReport {
        let crashDiagnostic = detectCrash(in: entries)
        let missingSceneryIssues = detectMissingScenery(in: entries)
        let scriptErrors = detectScriptErrors(in: entries)
        let (startupTimings, totalStartup) = analyzeStartupPerformance(in: entries)
        let detectedPlugins = extractDetectedPlugins(in: entries)
        let detectedSceneryPacks = extractDetectedSceneryPacks(in: entries)

        let errorEntries = entries.filter { $0.level == .error || $0.level == .fatal }
        let warningEntries = entries.filter { $0.level == .warn }

        // Group missing scenery issues by package / library dynamically
        var missingByPackage: [String: [MissingSceneryIssue]] = [:]
        for issue in missingSceneryIssues {
            missingByPackage[issue.inferredPackageOrLibrary, default: []].append(issue)
        }

        // Determine overall session status
        let status = determineSessionStatus(
            entries: entries,
            crashDiagnostic: crashDiagnostic
        )

        return LogAnalysisReport(
            fileItem: fileItem,
            lineCount: entries.count,
            status: status,
            crashDiagnostic: crashDiagnostic,
            missingSceneryIssues: missingSceneryIssues,
            missingSceneryByPackage: missingByPackage,
            scriptErrors: scriptErrors,
            startupTimings: startupTimings,
            totalStartupSeconds: totalStartup,
            detectedPlugins: detectedPlugins,
            detectedSceneryPacks: detectedSceneryPacks,
            allEntries: entries,
            errorEntries: errorEntries,
            warningEntries: warningEntries
        )
    }

    // MARK: - Crash Detection

    private func detectCrash(in entries: [XPlaneLogEntry]) -> CrashDiagnostic? {
        guard !entries.isEmpty else { return nil }

        // Search backward from log tail (last 300 lines) for crash signatures
        let searchRange = entries.suffix(300)

        // 1. Direct X-Plane plugin crash assertion
        // Example: "This application has crashed because of the plugin: <Plugin Name>"
        for entry in searchRange.reversed() {
            let line = entry.rawLine
            if let range = line.range(of: "This application has crashed because of the plugin:", options: .caseInsensitive) {
                let offending = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let backtrace = extractBacktrace(around: entry.lineNumber, in: entries)
                return CrashDiagnostic(
                    category: .pluginCrash,
                    offendingPluginOrSubsystem: offending.isEmpty ? nil : offending,
                    signalOrReason: "Application crashed due to plugin fault.",
                    backtrace: backtrace,
                    crashLineNumber: entry.lineNumber
                )
            }
        }

        // 2. Out of Memory / Metal exhaustion
        for entry in searchRange.reversed() {
            let lower = entry.rawLine.lowercased()
            if lower.contains("out of memory") ||
                lower.contains("vram allocation failed") ||
                lower.contains("metal device error") ||
                lower.contains("device lost") ||
                lower.contains("mtlcommandbuffer") && lower.contains("failed") {
                let backtrace = extractBacktrace(around: entry.lineNumber, in: entries)
                return CrashDiagnostic(
                    category: .memoryExhaustion,
                    offendingPluginOrSubsystem: "Graphics / Metal Subsystem",
                    signalOrReason: entry.message,
                    backtrace: backtrace,
                    crashLineNumber: entry.lineNumber
                )
            }
        }

        // 3. Fatal Signals (SIGSEGV, SIGBUS, SIGABRT, EXC_BAD_ACCESS)
        for entry in searchRange.reversed() {
            let lower = entry.rawLine.lowercased()
            if lower.contains("sigsegv") ||
                lower.contains("sigbus") ||
                lower.contains("sigabrt") ||
                lower.contains("exc_bad_access") ||
                lower.contains("kern_invalid_address") {

                let offendingPlugin = inferOffendingBinaryFromNearby(around: entry.lineNumber, in: entries)
                let backtrace = extractBacktrace(around: entry.lineNumber, in: entries)

                return CrashDiagnostic(
                    category: offendingPlugin != nil ? .pluginCrash : .fatalSignal,
                    offendingPluginOrSubsystem: offendingPlugin,
                    signalOrReason: entry.message,
                    backtrace: backtrace,
                    crashLineNumber: entry.lineNumber
                )
            }
        }

        // 4. Fatal Sim Assertion
        for entry in searchRange.reversed() {
            let lower = entry.rawLine.lowercased()
            if lower.contains("assertion failed:") || lower.contains("sim abort") || lower.contains("unhandled exception") {
                let backtrace = extractBacktrace(around: entry.lineNumber, in: entries)
                return CrashDiagnostic(
                    category: .aborted,
                    offendingPluginOrSubsystem: nil,
                    signalOrReason: entry.message,
                    backtrace: backtrace,
                    crashLineNumber: entry.lineNumber
                )
            }
        }

        return nil
    }

    private func extractBacktrace(around lineNumber: Int, in entries: [XPlaneLogEntry]) -> [String] {
        var backtrace: [String] = []
        let startIndex = max(0, lineNumber - 1)
        let endIndex = min(entries.count, lineNumber + 40)

        var capturing = false
        for i in startIndex..<endIndex {
            let line = entries[i].rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.lowercased().contains("backtrace:") || trimmed.lowercased().contains("stack dump:") {
                capturing = true
                continue
            }

            if capturing {
                // Check if this line looks like a backtrace frame
                if trimmed.hasPrefix("0x") ||
                    trimmed.hasPrefix("frame #") ||
                    trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) != nil ||
                    trimmed.contains(".xpl") ||
                    trimmed.contains("X-Plane") {
                    backtrace.append(trimmed)
                } else if !trimmed.isEmpty && backtrace.count < 30 {
                    backtrace.append(trimmed)
                } else if trimmed.isEmpty && !backtrace.isEmpty {
                    break
                }
            }
        }

        // If no explicit Backtrace tag was found, look for nearby frame lines
        if backtrace.isEmpty {
            for i in max(0, lineNumber - 10)..<min(entries.count, lineNumber + 15) {
                let trimmed = entries[i].rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.range(of: #"^\d+\s+0x[0-9a-fA-F]+"#, options: .regularExpression) != nil ||
                    trimmed.range(of: #"^frame #\d+:"#, options: .regularExpression) != nil {
                    backtrace.append(trimmed)
                }
            }
        }

        return backtrace
    }

    private func inferOffendingBinaryFromNearby(around lineNumber: Int, in entries: [XPlaneLogEntry]) -> String? {
        let start = max(0, lineNumber - 15)
        let end = min(entries.count, lineNumber + 25)
        for i in start..<end {
            let line = entries[i].rawLine
            if let xplRange = line.range(of: #"[A-Za-z0-9_\- ]+\.xpl"#, options: .regularExpression) {
                let name = String(line[xplRange])
                return name.replacingOccurrences(of: ".xpl", with: "")
            }
        }
        return nil
    }

    // MARK: - Missing Scenery & Asset Detection

    private func detectMissingScenery(in entries: [XPlaneLogEntry]) -> [MissingSceneryIssue] {
        var issues: [MissingSceneryIssue] = []
        var seenPaths = Set<String>()

        for entry in entries {
            let line = entry.rawLine
            let lower = line.lowercased()

            guard lower.contains("unable to load") ||
                    lower.contains("failed to find resource") ||
                    lower.contains("failed to open") ||
                    lower.contains("missing object") ||
                    lower.contains("could not find object") ||
                    lower.contains("cannot find object") else {
                continue
            }

            guard lower.contains("custom scenery") ||
                    lower.contains(".obj") ||
                    lower.contains(".dsf") ||
                    lower.contains(".ter") ||
                    lower.contains(".pol") ||
                    lower.contains(".fac") ||
                    lower.contains(".for") ||
                    lower.contains(".dds") ||
                    lower.contains(".png") ||
                    entry.subsystem == .scenery else {
                continue
            }

            if let parsed = parseSceneryIssue(from: entry) {
                if !seenPaths.contains(parsed.assetPath) {
                    seenPaths.insert(parsed.assetPath)
                    issues.append(parsed)
                }
            }
        }

        return issues
    }

    private func parseSceneryIssue(from entry: XPlaneLogEntry) -> MissingSceneryIssue? {
        let line = entry.rawLine

        // Extract path from quotes or after colons
        var extractedPath = ""
        if let quoteStart = line.firstIndex(of: "'"),
           let quoteEnd = line[line.index(after: quoteStart)...].firstIndex(of: "'") {
            extractedPath = String(line[line.index(after: quoteStart)..<quoteEnd])
        } else if let quoteStart = line.firstIndex(of: "\""),
                  let quoteEnd = line[line.index(after: quoteStart)...].firstIndex(of: "\"") {
            extractedPath = String(line[line.index(after: quoteStart)..<quoteEnd])
        } else if let colonRange = line.range(of: "object file:", options: .caseInsensitive) {
            extractedPath = line[colonRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let colonRange = line.range(of: "resource:", options: .caseInsensitive) {
            extractedPath = line[colonRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let colonRange = line.range(of: "failed to open", options: .caseInsensitive) {
            extractedPath = line[colonRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            extractedPath = entry.message
        }

        extractedPath = extractedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extractedPath.isEmpty else { return nil }

        // Determine SceneryAssetType
        let ext = (extractedPath as NSString).pathExtension.lowercased()
        let assetType: SceneryAssetType
        switch ext {
        case "obj": assetType = .object
        case "dsf": assetType = .dsf
        case "ter": assetType = .terrain
        case "pol": assetType = .polygon
        case "fac": assetType = .facade
        case "for": assetType = .forest
        case "png", "dds": assetType = .texture
        default:
            if extractedPath.contains("library") || extractedPath.contains("opensceneryx") {
                assetType = .libraryAsset
            } else {
                assetType = .genericAsset
            }
        }

        // Dynamically infer the package or library name from the path
        let (inferredPackage, referencedSceneryPack) = extractPackageAndSceneryInfo(from: extractedPath, rawLine: line)

        return MissingSceneryIssue(
            assetPath: extractedPath,
            inferredPackageOrLibrary: inferredPackage,
            referencedBySceneryPack: referencedSceneryPack,
            assetType: assetType,
            lineNumber: entry.lineNumber,
            rawMessage: line
        )
    }

    private func extractPackageAndSceneryInfo(from path: String, rawLine: String) -> (String, String?) {
        var referencedPack: String? = nil

        // If path or rawLine contains "Custom Scenery/<pack_name>/"
        if let range = rawLine.range(of: #"Custom Scenery/([^/]+)/"#, options: .regularExpression) {
            let matched = String(rawLine[range])
            let components = matched.split(separator: "/")
            if components.count >= 2 {
                referencedPack = String(components[1])
            }
        }

        // Infer package/library name dynamically:
        // 1. If path starts with "Custom Scenery/<PackName>/..."
        if path.hasPrefix("Custom Scenery/") {
            let comps = path.split(separator: "/")
            if comps.count > 1 {
                let pack = String(comps[1])
                return (pack, referencedPack ?? pack)
            }
        }

        // 2. If path is a library relative path like "opensceneryx/..." or "some_lib/objects/..."
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = cleaned.split(separator: "/")
        if let first = components.first, components.count > 1 {
            let root = String(first)
            // If root is not generic like "Resources" or "objects" or "Custom Scenery"
            if !["resources", "objects", "textures", "custom scenery"].contains(root.lowercased()) {
                return (root, referencedPack)
            } else if components.count > 2 {
                return (String(components[1]), referencedPack)
            }
        }

        if let pack = referencedPack {
            return (pack, referencedPack)
        }

        let fallback = (path as NSString).lastPathComponent
        return (fallback.isEmpty ? "Unknown Scenery Package" : fallback, referencedPack)
    }

    // MARK: - Lua & SASL Script Error Tracing

    private func detectScriptErrors(in entries: [XPlaneLogEntry]) -> [ScriptErrorIssue] {
        var scriptErrors: [ScriptErrorIssue] = []

        for (index, entry) in entries.enumerated() {
            let line = entry.rawLine
            let lower = line.lowercased()

            // 1. FlyWithLua Errors
            if lower.contains("flywithlua error:") ||
                lower.contains("flywithlua: the script") && lower.contains("failed") ||
                lower.contains("[flywithlua] lua error:") ||
                lower.contains("flywithlua: lua runtime error:") {

                var scriptName = "FlyWithLua Script"
                if let scriptRange = line.range(of: #"['\"]([^'\"]+\.lua)['\"]"#, options: .regularExpression) {
                    scriptName = String(line[scriptRange]).trimmingCharacters(in: CharacterSet(charactersIn: "'\" \t\n\r"))
                } else if let luaRange = line.range(of: #"[A-Za-z0-9_\-]+\.lua"#, options: .regularExpression) {
                    scriptName = String(line[luaRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Check for multi-line traceback
                var stack: [String] = []
                for j in (index + 1)..<min(entries.count, index + 15) {
                    let msg = entries[j].message.trimmingCharacters(in: .whitespaces)
                    let msgLower = msg.lowercased()
                    if msgLower.contains("flywithlua error") || msgLower.contains("sasl error") || msgLower.contains("[sasl") {
                        break
                    }
                    if msgLower.contains("stack traceback:") {
                        continue
                    } else if msg.contains(".lua:") || msg.range(of: #"^\d+:"#, options: .regularExpression) != nil || msg.contains("in function") || msg.contains("in main chunk") {
                        stack.append(msg)
                    } else {
                        break
                    }
                }

                scriptErrors.append(
                    ScriptErrorIssue(
                        engine: .flyWithLua,
                        scriptOrModuleName: scriptName,
                        errorMessage: entry.message,
                        stackTrace: stack,
                        lineNumber: entry.lineNumber
                    )
                )
            }

            // 2. SASL Avionics Errors
            else if lower.contains("sasl error") || lower.contains("[sasl error]") || lower.contains("sasl info: [error]") {
                var moduleName = "SASL Component"
                if let moduleRange = line.range(of: #"['\"]([^'\"]+\.lua)['\"]"#, options: .regularExpression) {
                    moduleName = String(line[moduleRange]).trimmingCharacters(in: CharacterSet(charactersIn: "'\" \t\n\r"))
                } else if let moduleRange = line.range(of: #"[A-Za-z0-9_\-]+\.lua"#, options: .regularExpression) {
                    moduleName = String(line[moduleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                var stack: [String] = []
                for j in (index + 1)..<min(entries.count, index + 15) {
                    let msg = entries[j].message.trimmingCharacters(in: .whitespaces)
                    let msgLower = msg.lowercased()
                    if msgLower.contains("flywithlua error") || msgLower.contains("sasl error") || msgLower.contains("[sasl error]") {
                        break
                    }
                    if msgLower.contains("stack traceback:") {
                        continue
                    } else if msg.contains(".lua:") || msg.range(of: #"^\d+:"#, options: .regularExpression) != nil || msg.contains("in function") {
                        stack.append(msg)
                    } else {
                        break
                    }
                }

                scriptErrors.append(
                    ScriptErrorIssue(
                        engine: .sasl,
                        scriptOrModuleName: moduleName,
                        errorMessage: entry.message,
                        stackTrace: stack,
                        lineNumber: entry.lineNumber
                    )
                )
            }
        }

        return scriptErrors
    }

    // MARK: - Startup Performance Profiling

    private func analyzeStartupPerformance(in entries: [XPlaneLogEntry]) -> ([StartupTimingItem], Double?) {
        var timings: [StartupTimingItem] = []
        var previousTimestamp: Double = 0.0
        var simStartTimestamp: Double? = nil
        var simReadyTimestamp: Double? = nil

        for entry in entries {
            guard let ts = entry.timestampSeconds else { continue }
            if simStartTimestamp == nil {
                simStartTimestamp = ts
            }

            let line = entry.rawLine

            // Detect plugin load line
            // Example: "I/PLG: Loaded: /Users/.../Resources/plugins/FlyWithLua/mac_x64/FlyWithLua.xpl (FlyWithLua NG+)."
            if line.contains("Loaded:") && (line.contains(".xpl") || entry.subsystem == .plugins) {
                let duration = max(0.001, ts - previousTimestamp)
                var pluginName = "Plugin"

                // Extract plugin name inside parentheses or last path component
                if let parenStart = line.lastIndex(of: "("),
                   let parenEnd = line.lastIndex(of: ")"),
                   parenStart < parenEnd {
                    let name = String(line[line.index(after: parenStart)..<parenEnd])
                    if !name.isEmpty {
                        pluginName = name
                    }
                } else if let xplRange = line.range(of: #"[A-Za-z0-9_\- ]+\.xpl"#, options: .regularExpression) {
                    pluginName = String(line[xplRange]).replacingOccurrences(of: ".xpl", with: "")
                }

                timings.append(
                    StartupTimingItem(
                        name: pluginName,
                        category: .plugin,
                        startSeconds: previousTimestamp,
                        durationSeconds: duration
                    )
                )
                previousTimestamp = ts
            } else if line.contains("Fetching plugins") || line.contains("Initializing plugins") {
                previousTimestamp = ts
            } else if line.contains("DSFLoad:") && line.contains("Loaded") {
                let duration = max(0.001, ts - previousTimestamp)
                var sceneryName = "Scenery Mesh"
                if let dsfRange = line.range(of: #"[+\-0-9]+[+\-0-9]+\.dsf"#, options: .regularExpression) {
                    sceneryName = "DSF \(line[dsfRange])"
                }

                timings.append(
                    StartupTimingItem(
                        name: sceneryName,
                        category: .scenery,
                        startSeconds: previousTimestamp,
                        durationSeconds: duration
                    )
                )
                previousTimestamp = ts
            }

            // Sim ready indicator
            if line.contains("Fly with X-Plane") || line.contains("Initializing off screen memory") || line.contains("ATC initialized") {
                simReadyTimestamp = ts
            }
        }

        var totalStartup: Double? = nil
        if let ready = simReadyTimestamp, let start = simStartTimestamp {
            totalStartup = max(0, ready - start)
        } else if let last = entries.last?.timestampSeconds, let start = simStartTimestamp {
            totalStartup = max(0, last - start)
        }

        return (timings, totalStartup)
    }

    // MARK: - Addon Discoveries

    private func extractDetectedPlugins(in entries: [XPlaneLogEntry]) -> [String] {
        var plugins: [String] = []
        var seen = Set<String>()

        for entry in entries {
            let line = entry.rawLine
            if line.contains("Loaded:") && (line.contains(".xpl") || entry.subsystem == .plugins) {
                var name = ""
                if let parenStart = line.lastIndex(of: "("),
                   let parenEnd = line.lastIndex(of: ")"),
                   parenStart < parenEnd {
                    name = String(line[line.index(after: parenStart)..<parenEnd])
                } else if let xplRange = line.range(of: #"[A-Za-z0-9_\- ]+\.xpl"#, options: .regularExpression) {
                    name = String(line[xplRange])
                }

                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty && !seen.contains(name) {
                    seen.insert(name)
                    plugins.append(name)
                }
            }
        }
        return plugins
    }

    private func extractDetectedSceneryPacks(in entries: [XPlaneLogEntry]) -> [String] {
        var packs: [String] = []
        var seen = Set<String>()

        for entry in entries {
            let line = entry.rawLine
            if let range = line.range(of: #"Custom Scenery/([^/]+)/"#, options: .regularExpression) {
                let matched = String(line[range])
                let comps = matched.split(separator: "/")
                if comps.count >= 2 {
                    let pack = String(comps[1])
                    if !seen.contains(pack) {
                        seen.insert(pack)
                        packs.append(pack)
                    }
                }
            }
        }
        return packs
    }

    // MARK: - Session Status

    private func determineSessionStatus(
        entries: [XPlaneLogEntry],
        crashDiagnostic: CrashDiagnostic?
    ) -> LogSessionStatus {
        if let crash = crashDiagnostic {
            return .crashed(crash)
        }

        // Check last 50 lines for clean exit signature
        for entry in entries.suffix(50).reversed() {
            let lower = entry.rawLine.lowercased()
            if lower.contains("clean exit") ||
                lower.contains("normal exit") ||
                lower.contains("exiting x-plane") ||
                lower.contains("clean shutdown") {
                return .cleanExit
            }
        }

        // Check if log contains fatal errors without structured crash
        if let lastFatal = entries.last(where: { $0.level == .fatal }) {
            return .abnormalTermination(reason: lastFatal.message)
        }

        return .runningOrIncomplete
    }
}
