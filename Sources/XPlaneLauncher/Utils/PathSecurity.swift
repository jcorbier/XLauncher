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

public enum PathSecurityError: LocalizedError, Equatable {
    case pathTraversalAttempt(String)
    case invalidPathComponent(String)
    case outsideSandbox(path: String, root: String)

    public var errorDescription: String? {
        switch self {
        case .pathTraversalAttempt(let path):
            return "Insecure relative path or traversal attempt detected: \(path)"
        case .invalidPathComponent(let name):
            return "Invalid path component: '\(name)'. Path separators and traversal sequences are not allowed."
        case .outsideSandbox(let path, let root):
            return "Path '\(path)' escapes sandbox root '\(root)'."
        }
    }
}

public enum PathSecurity {

    /// Sanitizes a single file or directory name, ensuring it contains no path separators (`/`, `\`),
    /// no `..` or `.` traversal elements, and is non-empty.
    @discardableResult
    public static func sanitizePathComponent(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PathSecurityError.invalidPathComponent(name)
        }

        if trimmed == "." || trimmed == ".." {
            throw PathSecurityError.invalidPathComponent(name)
        }

        if trimmed.contains("/") || trimmed.contains("\\") {
            throw PathSecurityError.invalidPathComponent(name)
        }

        if trimmed.contains("\0") {
            throw PathSecurityError.invalidPathComponent(name)
        }

        return trimmed
    }

    /// Validates and resolves a relative subpath within a root folder, guaranteeing
    /// that the resulting URL is strictly contained within `rootURL`.
    ///
    /// - Parameters:
    ///   - relativePath: The relative path (e.g. from an archive, remote manifest, or user input).
    ///   - rootURL: The base directory that must contain the resolved path.
    /// - Returns: The standardized target URL within `rootURL`.
    public static func validateSubpath(relativePath: String, within rootURL: URL) throws -> URL {
        let rawSanitized = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawSanitized.isEmpty else {
            throw PathSecurityError.pathTraversalAttempt(relativePath)
        }

        // Absolute paths or drive letters are rejected
        if rawSanitized.hasPrefix("/") || rawSanitized.hasPrefix("~") || rawSanitized.contains(":") {
            throw PathSecurityError.pathTraversalAttempt(relativePath)
        }

        // Check path components for traversal attempts
        let parts = rawSanitized.components(separatedBy: "/")
        for part in parts {
            if part == ".." {
                throw PathSecurityError.pathTraversalAttempt(relativePath)
            }
        }

        // Build target URL and standardize
        var targetURL = rootURL
        for part in parts where !part.isEmpty && part != "." {
            targetURL.appendPathComponent(part)
        }

        // Ensure strict containment
        guard isStrictlyContained(url: targetURL, within: rootURL) else {
            throw PathSecurityError.outsideSandbox(path: targetURL.path, root: rootURL.path)
        }

        return targetURL
    }

    /// Checks whether `url` is strictly contained within (or equal to) `parentURL`.
    public static func isStrictlyContained(url: URL, within parentURL: URL) -> Bool {
        let childStandardized = url.standardized.path
        let parentStandardized = parentURL.standardized.path

        if childStandardized == parentStandardized {
            return true
        }

        // 1. Lexical prefix check
        let parentPrefix = parentStandardized.hasSuffix("/") ? parentStandardized : parentStandardized + "/"
        guard childStandardized.hasPrefix(parentPrefix) else {
            return false
        }

        // 2. Canonical parent directory check
        // Resolves parent directories so root symlinks (like /var -> /private/var) match,
        // without following leaf symlinks if the target item itself is a managed symlink.
        let childParentCanonical = url.deletingLastPathComponent().standardized.resolvingSymlinksInPath().path
        let parentCanonical = parentURL.standardized.resolvingSymlinksInPath().path

        if childParentCanonical == parentCanonical {
            return true
        }

        let canonicalParentPrefix = parentCanonical.hasSuffix("/") ? parentCanonical : parentCanonical + "/"
        return childParentCanonical.hasPrefix(canonicalParentPrefix)
    }

    /// Validates that a symlink being created or removed resides strictly within the given `parentFolder`.
    public static func validateSymlinkLocation(linkURL: URL, within parentFolder: URL) throws {
        let linkParent = linkURL.deletingLastPathComponent().standardized.resolvingSymlinksInPath().path
        let expectedParent = parentFolder.standardized.resolvingSymlinksInPath().path

        guard linkParent == expectedParent || linkParent.hasPrefix(expectedParent + "/") else {
            throw PathSecurityError.outsideSandbox(path: linkURL.path, root: parentFolder.path)
        }

        try sanitizePathComponent(linkURL.lastPathComponent)
    }
}
