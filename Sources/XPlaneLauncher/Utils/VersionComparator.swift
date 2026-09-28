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

enum VersionComparator {
    /// Returns true if `versionA` is strictly newer than `versionB`.
    static func isNewer(_ versionA: String, than versionB: String) -> Bool {
        let cleanA = versionA.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanB = versionB.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanA == cleanB { return false }

        if let semA = SemanticVersion(string: cleanA),
           let semB = SemanticVersion(string: cleanB) {
            return semA > semB
        }

        return cleanA.compare(cleanB, options: .numeric) == .orderedDescending
    }

    /// Compares two version strings. Returns .orderedDescending if versionA > versionB,
    /// .orderedAscending if versionA < versionB, and .orderedSame if they are equal.
    static func compare(_ versionA: String, _ versionB: String) -> ComparisonResult {
        let cleanA = versionA.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanB = versionB.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanA == cleanB { return .orderedSame }

        if let semA = SemanticVersion(string: cleanA),
           let semB = SemanticVersion(string: cleanB) {
            if semA > semB { return .orderedDescending }
            if semA < semB { return .orderedAscending }
            return .orderedSame
        }

        return cleanA.compare(cleanB, options: .numeric)
    }
}
