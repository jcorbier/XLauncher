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

struct AddonUpdateCheckResult: Sendable {
    let latestVersion: String?
    let isUpdateAvailable: Bool
    let statusMessage: String
}

protocol AddonUpdater: Sendable {
    func checkStatus(
        for addon: UpdateManager.UpdatableAddon,
        logHandler: @Sendable @escaping @MainActor (String) -> Void
    ) async throws -> AddonUpdateCheckResult

    func applyUpdates(
        for addon: UpdateManager.UpdatableAddon,
        logHandler: @Sendable @escaping @MainActor (String) -> Void,
        progressHandler: @Sendable @escaping @MainActor (String, Double) -> Void
    ) async throws

    func fetchReleaseNotes(
        for addon: UpdateManager.UpdatableAddon,
        logHandler: @Sendable @escaping @MainActor (String) -> Void
    ) async throws -> String?
}

// MARK: - ChangelogFinder Helper

enum ChangelogFinder {
    private static let validExtensions: Set<String> = [
        "txt", "md", "markdown", "rst", "html", "htm"
    ]

    private static let excludedDirectoryComponents: Set<String> = [
        "plugins", "modules", "libs", "lib", "vendor", "third-party", "third_party",
        "thirdparty", "bin", "lin", "mac", "win", "64", "src", "source", "tools",
        "build", "node_modules", "custom avionics", "objects", "textures", "sounds",
        "liveries", "fms plans", "fms_plans"
    ]

    private static let docFolders: Set<String> = [
        "doc", "docs", "documentation", "manual", "manuals", ".xupdater", ".x-updater", "x-updater", "xupdater"
    ]

    /// Evaluates if a given relative path or filename looks like a changelog / release notes file.
    static func isChangelogPath(_ path: String) -> Bool {
        scoreChangelogPath(path) > 0
    }

    /// Computes a score for a file path. Higher score means better match. 0 means not a changelog.
    static func scoreChangelogPath(_ path: String) -> Int {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        let components = normalizedPath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return 0 }

        // Exclude internal/code/submodule directories (e.g. plugins, modules, libs, vendor)
        if components.count > 1 {
            let parentComponents = components.dropLast()
            if parentComponents.contains(where: { excludedDirectoryComponents.contains($0) }) {
                return 0
            }
        }

        let filename = components.last!
        let ext = (filename as NSString).pathExtension.lowercased()
        let stem = (filename as NSString).deletingPathExtension

        // Reject obvious non-changelog files
        let excludedExtensions: Set<String> = [
            "png", "dds", "obj", "wav", "mp3", "json", "cfg", "cnf", "ini", "conf",
            "lua", "xpl", "dylib", "so", "dll", "zip", "tar", "gz", "blend", "xcf", "psd",
            "dat", "sit", "acf", "air"
        ]
        if excludedExtensions.contains(ext) {
            return 0
        }

        // Extension check: allow empty extension or text/doc extensions
        if !ext.isEmpty && !validExtensions.contains(ext) {
            return 0
        }

        var baseScore = 0
        let primaryStems = ["changelog", "release-notes", "release_notes", "releasenotes"]
        let secondaryStems = ["changes", "history", "news", "whatsnew", "whats-new", "whats_new"]

        if primaryStems.contains(where: { stem == $0 || stem.hasPrefix($0) }) {
            baseScore = 1000
        } else if secondaryStems.contains(stem) {
            baseScore = 700
        } else if secondaryStems.contains(where: { stem.hasPrefix($0) || stem.hasSuffix($0) }) {
            baseScore = 500
        } else if (primaryStems + secondaryStems).contains(where: { stem.contains($0) }) {
            baseScore = 300
        } else {
            return 0
        }

        // Markdown or txt bonus
        if ext == "md" || ext == "markdown" {
            baseScore += 50
        } else if ext == "txt" {
            baseScore += 40
        }

        // Depth and directory bonus
        let depth = components.count - 1
        if depth == 0 {
            baseScore += 100 // Root file bonus
        } else if depth == 1, let firstDir = components.first, docFolders.contains(firstDir) {
            baseScore += 80 // First-level documentation folder bonus
        } else {
            baseScore -= depth * 150 // Heavy depth penalty for deeper paths
        }

        return max(1, baseScore)
    }

    /// Selects the best candidate path among a collection of paths.
    static func bestChangelogMatch(in paths: [String]) -> String? {
        paths
            .map { (path: $0, score: scoreChangelogPath($0)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .first?
            .path
    }

    /// Searches local folder for a changelog file.
    static func findLocalChangelog(in folderURL: URL) -> URL? {
        let fm = FileManager.default
        var candidateURLs: [URL] = []

        let subDirs = ["", ".xupdater", ".x-updater", "doc", "docs", "documentation"]
        for sub in subDirs {
            let searchDir = sub.isEmpty ? folderURL : folderURL.appendingPathComponent(sub)
            guard let contents = try? fm.contentsOfDirectory(at: searchDir, includingPropertiesForKeys: nil, options: []) else {
                continue
            }
            for item in contents {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue {
                    if isChangelogPath(item.lastPathComponent) {
                        candidateURLs.append(item)
                    }
                }
            }
        }

        return candidateURLs
            .map { (url: $0, score: scoreChangelogPath($0.lastPathComponent)) }
            .sorted { $0.score > $1.score }
            .first?
            .url
    }
}

