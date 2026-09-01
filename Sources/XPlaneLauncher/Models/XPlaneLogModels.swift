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

// MARK: - Log Source

public enum LogFileSourceType: String, Sendable, Codable {
    case current = "Current Log"
    case archive = "Archived Session"
    case custom = "Custom File"
}

public struct LogFileItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let displayName: String
    public let sourceType: LogFileSourceType
    public let modificationDate: Date?
    public let fileSize: Int64

    public init(
        url: URL,
        displayName: String,
        sourceType: LogFileSourceType,
        modificationDate: Date? = nil,
        fileSize: Int64 = 0
    ) {
        self.url = url
        self.displayName = displayName
        self.sourceType = sourceType
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var formattedDate: String {
        guard let modificationDate = modificationDate else { return "Unknown Date" }
        return modificationDate.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Subsystems and Severity

public enum XPlaneLogLevel: String, CaseIterable, Identifiable, Sendable, Codable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case fatal = "FATAL"

    public var id: String { rawValue }
}

public enum XPlaneLogSubsystem: String, CaseIterable, Identifiable, Sendable, Codable {
    case general = "General"
    case plugins = "Plugins"
    case scenery = "Scenery"
    case lua = "FlyWithLua"
    case sasl = "SASL / Avionics"
    case graphics = "Graphics / Metal"
    case system = "System / Sim"
    case flight = "Flight Model"
    case atc = "ATC / AI"
    case weather = "Weather"
    case network = "Network"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .general: return "doc.text"
        case .plugins: return "puzzlepiece.extension"
        case .scenery: return "map"
        case .lua: return "scroll"
        case .sasl: return "airplane"
        case .graphics: return "display"
        case .system: return "gearshape.2"
        case .flight: return "paperplane"
        case .atc: return "antenna.radiowaves.left.and.right"
        case .weather: return "cloud.sun"
        case .network: return "network"
        }
    }
}

// MARK: - Log Entry

public struct XPlaneLogEntry: Identifiable, Equatable, Sendable {
    public let id: Int // Line number as unique ID
    public let lineNumber: Int
    public let timestampSeconds: Double?
    public let timestampString: String?
    public let subsystem: XPlaneLogSubsystem
    public let level: XPlaneLogLevel
    public let tag: String?
    public let message: String
    public let rawLine: String

    public init(
        lineNumber: Int,
        timestampSeconds: Double? = nil,
        timestampString: String? = nil,
        subsystem: XPlaneLogSubsystem = .general,
        level: XPlaneLogLevel = .info,
        tag: String? = nil,
        message: String,
        rawLine: String
    ) {
        self.id = lineNumber
        self.lineNumber = lineNumber
        self.timestampSeconds = timestampSeconds
        self.timestampString = timestampString
        self.subsystem = subsystem
        self.level = level
        self.tag = tag
        self.message = message
        self.rawLine = rawLine
    }
}

// MARK: - Crash Diagnostics

public enum CrashCategory: String, Sendable, Codable {
    case pluginCrash = "Plugin Fault"
    case memoryExhaustion = "Out of Memory / VRAM Exhaustion"
    case fatalSignal = "Fatal Signal / Access Violation"
    case aborted = "Sim Abort / Assertion"
    case unknown = "Unknown Crash"
}

public struct CrashDiagnostic: Equatable, Sendable {
    public let category: CrashCategory
    public let offendingPluginOrSubsystem: String?
    public let signalOrReason: String
    public let backtrace: [String]
    public let crashLineNumber: Int?

    public init(
        category: CrashCategory,
        offendingPluginOrSubsystem: String? = nil,
        signalOrReason: String,
        backtrace: [String] = [],
        crashLineNumber: Int? = nil
    ) {
        self.category = category
        self.offendingPluginOrSubsystem = offendingPluginOrSubsystem
        self.signalOrReason = signalOrReason
        self.backtrace = backtrace
        self.crashLineNumber = crashLineNumber
    }
}

// MARK: - Missing Scenery & Assets

public enum SceneryAssetType: String, Sendable, Codable {
    case object = "3D Object (.obj)"
    case dsf = "Terrain Mesh / DSF"
    case polygon = "Polygon (.pol)"
    case facade = "Facade (.fac)"
    case forest = "Forest (.for)"
    case terrain = "Terrain (.ter)"
    case texture = "Texture / Image"
    case libraryAsset = "Library Resource"
    case genericAsset = "Scenery Asset"
}

public struct MissingSceneryIssue: Identifiable, Equatable, Sendable {
    public var id: String { "\(lineNumber):\(assetPath)" }
    public let assetPath: String
    public let inferredPackageOrLibrary: String
    public let referencedBySceneryPack: String?
    public let assetType: SceneryAssetType
    public let lineNumber: Int
    public let rawMessage: String

    public init(
        assetPath: String,
        inferredPackageOrLibrary: String,
        referencedBySceneryPack: String? = nil,
        assetType: SceneryAssetType = .object,
        lineNumber: Int,
        rawMessage: String
    ) {
        self.assetPath = assetPath
        self.inferredPackageOrLibrary = inferredPackageOrLibrary
        self.referencedBySceneryPack = referencedBySceneryPack
        self.assetType = assetType
        self.lineNumber = lineNumber
        self.rawMessage = rawMessage
    }
}

// MARK: - Lua & SASL Script Errors

public enum ScriptEngine: String, Sendable, Codable {
    case flyWithLua = "FlyWithLua"
    case sasl = "SASL Avionics"
    case generic = "Script"
}

public struct ScriptErrorIssue: Identifiable, Equatable, Sendable {
    public var id: String { "\(lineNumber):\(scriptOrModuleName):\(errorMessage.prefix(40))" }
    public let engine: ScriptEngine
    public let scriptOrModuleName: String
    public let errorMessage: String
    public let stackTrace: [String]
    public let lineNumber: Int

    public init(
        engine: ScriptEngine,
        scriptOrModuleName: String,
        errorMessage: String,
        stackTrace: [String] = [],
        lineNumber: Int
    ) {
        self.engine = engine
        self.scriptOrModuleName = scriptOrModuleName
        self.errorMessage = errorMessage
        self.stackTrace = stackTrace
        self.lineNumber = lineNumber
    }
}

// MARK: - Startup Performance Profiling

public enum StartupCategory: String, Sendable, Codable {
    case plugin = "Plugin"
    case scenery = "Scenery DSF"
    case core = "Sim Subsystem"
}

public struct StartupTimingItem: Identifiable, Equatable, Sendable {
    public var id: String { "\(category.rawValue):\(name):\(startSeconds)" }
    public let name: String
    public let category: StartupCategory
    public let startSeconds: Double
    public let durationSeconds: Double

    public init(
        name: String,
        category: StartupCategory,
        startSeconds: Double,
        durationSeconds: Double
    ) {
        self.name = name
        self.category = category
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }

    public var formattedDuration: String {
        if durationSeconds < 1.0 {
            return String(format: "%.0f ms", durationSeconds * 1000)
        } else {
            return String(format: "%.2f s", durationSeconds)
        }
    }
}

// MARK: - Session Status & Full Analysis Report

public enum LogSessionStatus: Equatable, Sendable {
    case cleanExit
    case crashed(CrashDiagnostic)
    case abnormalTermination(reason: String)
    case runningOrIncomplete

    public var title: String {
        switch self {
        case .cleanExit:
            return "Clean Flight Session"
        case .crashed:
            return "Fatal Crash Detected"
        case .abnormalTermination:
            return "Abnormal Sim Termination"
        case .runningOrIncomplete:
            return "Session Ended or In Progress"
        }
    }

    public var systemImage: String {
        switch self {
        case .cleanExit:
            return "checkmark.seal.fill"
        case .crashed:
            return "exclamationmark.octagon.fill"
        case .abnormalTermination:
            return "exclamationmark.triangle.fill"
        case .runningOrIncomplete:
            return "hourglass"
        }
    }
}

public struct LogAnalysisReport: Equatable, Sendable {
    public let fileItem: LogFileItem
    public let lineCount: Int
    public let status: LogSessionStatus
    public let crashDiagnostic: CrashDiagnostic?
    public let missingSceneryIssues: [MissingSceneryIssue]
    public let missingSceneryByPackage: [String: [MissingSceneryIssue]]
    public let scriptErrors: [ScriptErrorIssue]
    public let startupTimings: [StartupTimingItem]
    public let totalStartupSeconds: Double?
    public let detectedPlugins: [String]
    public let detectedSceneryPacks: [String]
    public let allEntries: [XPlaneLogEntry]
    public let errorEntries: [XPlaneLogEntry]
    public let warningEntries: [XPlaneLogEntry]

    public init(
        fileItem: LogFileItem,
        lineCount: Int,
        status: LogSessionStatus,
        crashDiagnostic: CrashDiagnostic?,
        missingSceneryIssues: [MissingSceneryIssue],
        missingSceneryByPackage: [String: [MissingSceneryIssue]],
        scriptErrors: [ScriptErrorIssue],
        startupTimings: [StartupTimingItem],
        totalStartupSeconds: Double?,
        detectedPlugins: [String],
        detectedSceneryPacks: [String],
        allEntries: [XPlaneLogEntry],
        errorEntries: [XPlaneLogEntry],
        warningEntries: [XPlaneLogEntry]
    ) {
        self.fileItem = fileItem
        self.lineCount = lineCount
        self.status = status
        self.crashDiagnostic = crashDiagnostic
        self.missingSceneryIssues = missingSceneryIssues
        self.missingSceneryByPackage = missingSceneryByPackage
        self.scriptErrors = scriptErrors
        self.startupTimings = startupTimings
        self.totalStartupSeconds = totalStartupSeconds
        self.detectedPlugins = detectedPlugins
        self.detectedSceneryPacks = detectedSceneryPacks
        self.allEntries = allEntries
        self.errorEntries = errorEntries
        self.warningEntries = warningEntries
    }

    public var errorCount: Int { errorEntries.count }
    public var warningCount: Int { warningEntries.count }
    public var missingSceneryCount: Int { missingSceneryIssues.count }
    public var scriptErrorCount: Int { scriptErrors.count }

    public func generateMarkdownReport() -> String {
        var md = "# X-Plane Log Diagnostics Report\n\n"
        md += "- **Log File**: `\(fileItem.displayName)`\n"
        md += "- **Source**: \(fileItem.sourceType.rawValue)\n"
        md += "- **Total Lines**: \(lineCount)\n"
        md += "- **Overall Status**: \(status.title)\n\n"

        if let crash = crashDiagnostic {
            md += "## 🔴 Crash Diagnostics\n\n"
            md += "- **Category**: \(crash.category.rawValue)\n"
            if let plugin = crash.offendingPluginOrSubsystem {
                md += "- **Offending Plugin / System**: `\(plugin)`\n"
            }
            if let line = crash.crashLineNumber {
                md += "- **Log Line**: #\(line)\n"
            }
            md += "- **Reason / Signal**: \(crash.signalOrReason)\n\n"

            if !crash.backtrace.isEmpty {
                md += "### Stack Backtrace\n```text\n"
                md += crash.backtrace.joined(separator: "\n")
                md += "\n```\n\n"
            }
        }

        if !missingSceneryIssues.isEmpty {
            md += "## 🟡 Missing Scenery Assets (\(missingSceneryIssues.count) issues)\n\n"
            for (pkg, issues) in missingSceneryByPackage.sorted(by: { $0.key < $1.key }) {
                md += "### Package / Library: `\(pkg)` (\(issues.count) missing)\n"
                for issue in issues.prefix(10) {
                    md += "- [L\(issue.lineNumber)] `\(issue.assetPath)` (\(issue.assetType.rawValue))\n"
                }
                if issues.count > 10 {
                    md += "- ... and \(issues.count - 10) more\n"
                }
                md += "\n"
            }
        }

        if !scriptErrors.isEmpty {
            md += "## 📜 Script & Avionics Errors (\(scriptErrors.count) issues)\n\n"
            for err in scriptErrors {
                md += "### [\(err.engine.rawValue)] `\(err.scriptOrModuleName)` (Line \(err.lineNumber))\n"
                md += "```text\n\(err.errorMessage)\n```\n"
                if !err.stackTrace.isEmpty {
                    md += "**Traceback:**\n```text\n\(err.stackTrace.joined(separator: "\n"))\n```\n"
                }
                md += "\n"
            }
        }

        if !startupTimings.isEmpty {
            md += "## ⏱️ Slowest Add-ons During Startup\n\n"
            let sorted = startupTimings.sorted(by: { $0.durationSeconds > $1.durationSeconds }).prefix(10)
            md += "| Component | Category | Duration |\n"
            md += "|---|---|---|\n"
            for item in sorted {
                md += "| `\(item.name)` | \(item.category.rawValue) | \(item.formattedDuration) |\n"
            }
            md += "\n"
        }

        return md
    }
}
