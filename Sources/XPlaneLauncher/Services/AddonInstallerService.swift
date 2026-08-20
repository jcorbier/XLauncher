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

enum AddonCategory: String, CaseIterable, Identifiable, Sendable {
    case aircraft = "Aircraft"
    case scenery = "Custom Scenery"
    case plugins = "Plugins"
    case luaScripts = "FlyWithLua Scripts"

    var id: String { rawValue }

    var subfolder: DataSubfolder {
        switch self {
        case .aircraft: return .aircraft
        case .scenery: return .scenery
        case .plugins: return .plugins
        case .luaScripts: return .luaScripts
        }
    }

    var logCategory: LogCategory {
        switch self {
        case .aircraft: return .aircraft
        case .scenery: return .scenery
        case .plugins: return .plugins
        case .luaScripts: return .lua
        }
    }

    var icon: String {
        switch self {
        case .aircraft: return "airplane"
        case .scenery: return "map"
        case .plugins: return "puzzlepiece.extension"
        case .luaScripts: return "scroll"
        }
    }
}

struct AddonPackageAnalysis: Sendable, Identifiable {
    var id: String { sourceURL.path }
    let sourceURL: URL
    let isArchive: Bool
    let detectedCategory: AddonCategory
    let suggestedPackageName: String
    let entriesCount: Int
    let totalUncompressedSize: UInt64
    let internalRootPrefix: String?
    let detectedIndicators: [String]
}

enum AddonInstallerError: LocalizedError {
    case invalidPackage(String)
    case destinationExists(String)
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage(let reason):
            return "Invalid add-on package: \(reason)"
        case .destinationExists(let path):
            return "An add-on already exists at destination: \(path)"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        }
    }
}

final class AddonInstallerService: Sendable {
    static let shared = AddonInstallerService()

    private var fileManager: FileManager { FileManager.default }

    // MARK: - Analysis

    func analyze(url: URL) async throws -> AddonPackageAnalysis {
        let isZip = url.pathExtension.lowercased() == "zip"
        let isLua = url.pathExtension.lowercased() == "lua"
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)

        guard exists else {
            throw AddonInstallerError.invalidPackage("File or directory does not exist at \(url.path)")
        }

        if isZip {
            return try await analyzeZipArchive(url: url)
        } else if isDirectory.boolValue {
            return try analyzeDirectory(url: url)
        } else if isLua {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            let name = url.deletingPathExtension().lastPathComponent
            return AddonPackageAnalysis(
                sourceURL: url,
                isArchive: false,
                detectedCategory: .luaScripts,
                suggestedPackageName: name,
                entriesCount: 1,
                totalUncompressedSize: size,
                internalRootPrefix: nil,
                detectedIndicators: ["Lua script file (.lua)"]
            )
        } else {
            throw AddonInstallerError.invalidPackage("Unsupported file type: .\(url.pathExtension). Please provide a .zip archive, .lua script, or folder.")
        }
    }

    private func analyzeZipArchive(url: URL) async throws -> AddonPackageAnalysis {
        let entries = try ZipExtractor.listEntries(from: url)
        let validEntries = entries.filter { entry in
            let p = entry.path
            return !p.hasPrefix("__MACOSX/") && !p.contains("/.DS_Store") && !p.hasSuffix(".DS_Store")
        }

        guard !validEntries.isEmpty else {
            throw AddonInstallerError.invalidPackage("Archive is empty or contains only macOS metadata.")
        }

        var indicators: [String] = []
        var detectedCategory: AddonCategory = .plugins

        // 1. Aircraft detection (.acf)
        let acfEntries = validEntries.filter { $0.path.lowercased().hasSuffix(".acf") }
        if !acfEntries.isEmpty {
            detectedCategory = .aircraft
            indicators.append("Found aircraft definition: \(acfEntries.first?.path ?? "*.acf")")
        }

        // 2. Custom Scenery detection (Earth nav data/, earth.wed.xml, apt.dat, library.txt)
        if indicators.isEmpty {
            let scenerySignals = validEntries.filter { entry in
                let p = entry.path.lowercased()
                return p.contains("earth nav data/") || p.hasSuffix("earth.wed.xml") || p.hasSuffix("apt.dat") || p.hasSuffix("library.txt")
            }
            if !scenerySignals.isEmpty {
                detectedCategory = .scenery
                indicators.append("Found scenery files: \(scenerySignals.first?.path ?? "scenery component")")
            }
        }

        // 3. Plugin detection (mac_x64/, win_x64/, lin_x64/, 64/, *.xpl)
        if indicators.isEmpty {
            let pluginSignals = validEntries.filter { entry in
                let p = entry.path.lowercased()
                return p.contains("mac_x64") || p.contains("win_x64") || p.contains("lin_x64") || p.contains("/64/") || p.hasSuffix(".xpl")
            }
            if !pluginSignals.isEmpty {
                detectedCategory = .plugins
                indicators.append("Found plugin binary: \(pluginSignals.first?.path ?? "*.xpl")")
            }
        }

        // 4. Lua Script detection (*.lua)
        if indicators.isEmpty {
            let luaSignals = validEntries.filter { $0.path.lowercased().hasSuffix(".lua") }
            if !luaSignals.isEmpty {
                detectedCategory = .luaScripts
                indicators.append("Found FlyWithLua script: \(luaSignals.first?.path ?? "*.lua")")
            }
        }

        // Fallback default
        if indicators.isEmpty {
            detectedCategory = .plugins
            indicators.append("Generic add-on structure")
        }

        // Determine suggested package name & internal root prefix
        let (rootPrefix, suggestedName) = detectZipRoot(entries: validEntries, fallbackArchiveURL: url)
        let totalSize = validEntries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }

        return AddonPackageAnalysis(
            sourceURL: url,
            isArchive: true,
            detectedCategory: detectedCategory,
            suggestedPackageName: suggestedName,
            entriesCount: validEntries.count,
            totalUncompressedSize: totalSize,
            internalRootPrefix: rootPrefix,
            detectedIndicators: indicators
        )
    }

    private func detectZipRoot(entries: [ZipExtractor.ZipEntry], fallbackArchiveURL: URL) -> (prefix: String?, suggestedName: String) {
        let fallbackName = fallbackArchiveURL.deletingPathExtension().lastPathComponent

        // Check if all non-root paths share a common top-level directory
        let firstComponents = entries.compactMap { entry -> String? in
            let parts = entry.path.split(separator: "/")
            return parts.first.map(String.init)
        }

        guard let first = firstComponents.first else {
            return (nil, fallbackName)
        }

        let isSingleTopLevel = firstComponents.allSatisfy { $0 == first }

        if isSingleTopLevel && entries.contains(where: { $0.path.hasPrefix("\(first)/") && $0.path != "\(first)/" }) {
            return ("\(first)/", first)
        }

        return (nil, fallbackName)
    }

    private func analyzeDirectory(url: URL) throws -> AddonPackageAnalysis {
        var indicators: [String] = []
        var detectedCategory: AddonCategory = .plugins
        var fileCount = 0
        var totalSize: UInt64 = 0

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            throw AddonInstallerError.invalidPackage("Failed to read directory contents.")
        }

        while let fileURL = enumerator.nextObject() as? URL {
            fileCount += 1
            if let attrs = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               attrs.isRegularFile == true {
                totalSize += UInt64(attrs.fileSize ?? 0)
            }

            let pathLower = fileURL.path.lowercased()
            if pathLower.hasSuffix(".acf") && indicators.isEmpty {
                detectedCategory = .aircraft
                indicators.append("Found aircraft definition: \(fileURL.lastPathComponent)")
            } else if (pathLower.contains("earth nav data") || pathLower.hasSuffix("earth.wed.xml") || pathLower.hasSuffix("apt.dat") || pathLower.hasSuffix("library.txt")) && indicators.isEmpty {
                detectedCategory = .scenery
                indicators.append("Found scenery files: \(fileURL.lastPathComponent)")
            } else if (pathLower.contains("mac_x64") || pathLower.contains("win_x64") || pathLower.contains("lin_x64") || pathLower.hasSuffix(".xpl")) && indicators.isEmpty {
                detectedCategory = .plugins
                indicators.append("Found plugin binary: \(fileURL.lastPathComponent)")
            } else if pathLower.hasSuffix(".lua") && indicators.isEmpty {
                detectedCategory = .luaScripts
                indicators.append("Found FlyWithLua script: \(fileURL.lastPathComponent)")
            }
        }

        if indicators.isEmpty {
            detectedCategory = .plugins
            indicators.append("Directory structure")
        }

        return AddonPackageAnalysis(
            sourceURL: url,
            isArchive: false,
            detectedCategory: detectedCategory,
            suggestedPackageName: url.lastPathComponent,
            entriesCount: fileCount,
            totalUncompressedSize: totalSize,
            internalRootPrefix: nil,
            detectedIndicators: indicators
        )
    }

    // MARK: - Installation Execution

    func install(
        analysis: AddonPackageAnalysis,
        category: AddonCategory,
        packageName: String,
        launcherDataFolder: URL,
        progressHandler: (@Sendable (_ fraction: Double, _ message: String) -> Void)? = nil
    ) async throws -> URL {
        let sanitizedName: String
        do {
            sanitizedName = try PathSecurity.sanitizePathComponent(packageName)
        } catch {
            throw AddonInstallerError.invalidPackage("Invalid package name '\(packageName)': names cannot contain slashes or traversal sequences.")
        }

        let subfolderURL = PathService.shared.dataFolder(category.subfolder, in: launcherDataFolder)
        try fileManager.createDirectory(at: subfolderURL, withIntermediateDirectories: true)

        let destinationURL = try PathSecurity.validateSubpath(relativePath: sanitizedName, within: subfolderURL)

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw AddonInstallerError.destinationExists(destinationURL.path)
        }

        progressHandler?(0.1, "Preparing destination...")

        if analysis.isArchive {
            // Temporary extraction directory
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent("XLauncher_Extract_\(UUID().uuidString)")
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }

            progressHandler?(0.2, "Extracting archive...")
            try ZipExtractor.extract(archiveAt: analysis.sourceURL, to: tempDir) { extracted, total, file in
                let fraction = 0.2 + (0.6 * Double(extracted) / Double(max(total, 1)))
                progressHandler?(fraction, "Extracting: \(file)")
            }

            progressHandler?(0.85, "Organizing files...")

            if let rootPrefix = analysis.internalRootPrefix,
               let innerFolder = try? PathSecurity.validateSubpath(relativePath: rootPrefix, within: tempDir),
               fileManager.fileExists(atPath: innerFolder.path) {
                try fileManager.moveItem(at: innerFolder, to: destinationURL)
            } else {
                try fileManager.moveItem(at: tempDir, to: destinationURL)
            }
        } else {
            // Directory or single file copy
            progressHandler?(0.5, "Copying add-on files...")
            try fileManager.copyItem(at: analysis.sourceURL, to: destinationURL)
        }

        // Set executable permissions on binaries within plugins if needed
        if category == .plugins {
            setExecutablePermissions(in: destinationURL)
        }

        progressHandler?(1.0, "Installation complete")
        return destinationURL
    }

    private func setExecutablePermissions(in folderURL: URL) {
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: nil) else { return }
        while let fileURL = enumerator.nextObject() as? URL {
            let path = fileURL.path
            if path.hasSuffix(".xpl") || path.contains("/mac_x64/") || path.contains("/64/") {
                try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }
    }
}
