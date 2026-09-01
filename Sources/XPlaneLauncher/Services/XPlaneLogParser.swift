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

public final class XPlaneLogParser: Sendable {
    public static let shared = XPlaneLogParser()

    public init() {}

    public func parseFile(at url: URL) throws -> [XPlaneLogEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseString(content)
    }

    public func parseString(_ content: String) -> [XPlaneLogEntry] {
        let rawLines = content.components(separatedBy: .newlines)
        var entries: [XPlaneLogEntry] = []
        entries.reserveCapacity(rawLines.count)

        var lastTimestampSeconds: Double? = nil
        var lastTimestampString: String? = nil

        for (index, line) in rawLines.enumerated() {
            let lineNumber = index + 1
            if line.isEmpty && index == rawLines.count - 1 {
                continue // skip trailing newline empty line
            }

            let entry = parseLine(
                line,
                lineNumber: lineNumber,
                lastTimestampSeconds: &lastTimestampSeconds,
                lastTimestampString: &lastTimestampString
            )
            entries.append(entry)
        }

        return entries
    }

    public func parseLine(
        _ rawLine: String,
        lineNumber: Int,
        lastTimestampSeconds: inout Double?,
        lastTimestampString: inout String?
    ) -> XPlaneLogEntry {
        var remainder = rawLine[...]
        var parsedTimestampSeconds: Double? = nil
        var parsedTimestampString: String? = nil

        // Try extracting timestamp: e.g. "0:00:00.000" or "12:34:56.789"
        if let match = matchTimestamp(in: remainder) {
            parsedTimestampSeconds = match.seconds
            parsedTimestampString = match.string
            lastTimestampSeconds = match.seconds
            lastTimestampString = match.string
            remainder = remainder[match.endIndex...]
            // Skip whitespace after timestamp
            while remainder.first?.isWhitespace == true {
                remainder.removeFirst()
            }
        }

        // Try extracting XP12 tag like "I/PLG:", "E/SYS:", "W/SCN:"
        var tag: String? = nil
        var subsystem: XPlaneLogSubsystem = .general
        var level: XPlaneLogLevel = .info

        if let tagMatch = matchXP12Tag(in: remainder) {
            tag = tagMatch.tag
            subsystem = tagMatch.subsystem
            level = tagMatch.level
            remainder = remainder[tagMatch.endIndex...]
            while remainder.first?.isWhitespace == true {
                remainder.removeFirst()
            }
        }

        let message = String(remainder)

        // Refine subsystem and level based on message content heuristics
        let (refinedSubsystem, refinedLevel) = refineClassification(
            message: message,
            rawLine: rawLine,
            currentSubsystem: subsystem,
            currentLevel: level
        )

        return XPlaneLogEntry(
            lineNumber: lineNumber,
            timestampSeconds: parsedTimestampSeconds ?? lastTimestampSeconds,
            timestampString: parsedTimestampString ?? lastTimestampString,
            subsystem: refinedSubsystem,
            level: refinedLevel,
            tag: tag,
            message: message.isEmpty ? rawLine : message,
            rawLine: rawLine
        )
    }

    // MARK: - Timestamp Matching

    private struct TimestampMatch {
        let seconds: Double
        let string: String
        let endIndex: String.Index
    }

    private func matchTimestamp(in text: Substring) -> TimestampMatch? {
        // Look for pattern ^\d+:\d{2}:\d{2}\.\d{3}
        var index = text.startIndex
        var digitCount = 0
        while index < text.endIndex && text[index].isNumber {
            digitCount += 1
            index = text.index(after: index)
        }
        guard digitCount >= 1, index < text.endIndex, text[index] == ":" else { return nil }

        let hStr = String(text[text.startIndex..<index])
        guard let h = Double(hStr) else { return nil }
        index = text.index(after: index) // skip ':'

        // 2 digits for minutes
        let mStart = index
        for _ in 0..<2 {
            guard index < text.endIndex, text[index].isNumber else { return nil }
            index = text.index(after: index)
        }
        let mStr = String(text[mStart..<index])
        guard let m = Double(mStr), index < text.endIndex, text[index] == ":" else { return nil }
        index = text.index(after: index) // skip ':'

        // 2 digits for seconds
        let sStart = index
        for _ in 0..<2 {
            guard index < text.endIndex, text[index].isNumber else { return nil }
            index = text.index(after: index)
        }
        let sStr = String(text[sStart..<index])
        guard let s = Double(sStr), index < text.endIndex, text[index] == "." else { return nil }
        index = text.index(after: index) // skip '.'

        // 3 digits for ms
        let msStart = index
        for _ in 0..<3 {
            guard index < text.endIndex, text[index].isNumber else { return nil }
            index = text.index(after: index)
        }
        let msStr = String(text[msStart..<index])
        guard let ms = Double(msStr) else { return nil }

        let totalSeconds = (h * 3600.0) + (m * 60.0) + s + (ms / 1000.0)
        let fullString = String(text[text.startIndex..<index])

        return TimestampMatch(seconds: totalSeconds, string: fullString, endIndex: index)
    }

    // MARK: - XP12 Tag Matching

    private struct TagMatch {
        let tag: String
        let subsystem: XPlaneLogSubsystem
        let level: XPlaneLogLevel
        let endIndex: String.Index
    }

    private func matchXP12Tag(in text: Substring) -> TagMatch? {
        // e.g. "I/PLG:", "W/SCN:", "E/SYS:", "D/GFX:", "F/SYS:"
        guard text.count >= 5 else { return nil }
        var index = text.startIndex

        let levelChar = text[index]
        let level: XPlaneLogLevel
        switch levelChar {
        case "I": level = .info
        case "W": level = .warn
        case "E": level = .error
        case "F": level = .fatal
        case "D": level = .info
        default: return nil
        }

        index = text.index(after: index)
        guard index < text.endIndex, text[index] == "/" else { return nil }
        index = text.index(after: index)

        let tagStart = index
        while index < text.endIndex && text[index].isLetter {
            index = text.index(after: index)
        }
        guard index > tagStart else { return nil }
        let tagCode = String(text[tagStart..<index]).uppercased()

        if index < text.endIndex && text[index] == ":" {
            index = text.index(after: index)
        }

        let subsystem: XPlaneLogSubsystem
        switch tagCode {
        case "PLG": subsystem = .plugins
        case "SCN": subsystem = .scenery
        case "SYS": subsystem = .system
        case "GFX": subsystem = .graphics
        case "FLT": subsystem = .flight
        case "ATC": subsystem = .atc
        case "WXR": subsystem = .weather
        case "NET": subsystem = .network
        default: subsystem = .general
        }

        let tagString = "\(levelChar)/\(tagCode)"
        return TagMatch(tag: tagString, subsystem: subsystem, level: level, endIndex: index)
    }

    // MARK: - Heuristic Refinements

    private func refineClassification(
        message: String,
        rawLine: String,
        currentSubsystem: XPlaneLogSubsystem,
        currentLevel: XPlaneLogLevel
    ) -> (XPlaneLogSubsystem, XPlaneLogLevel) {
        var subsystem = currentSubsystem
        var level = currentLevel

        let lower = rawLine.lowercased()

        // Subsystem detection
        if lower.contains("flywithlua") {
            subsystem = .lua
        } else if lower.contains("sasl") {
            subsystem = .sasl
        } else if subsystem == .general {
            if lower.contains("custom scenery") || lower.contains(".dsf") || lower.contains(".obj") {
                subsystem = .scenery
            } else if lower.contains("plugin") || lower.contains(".xpl") {
                subsystem = .plugins
            } else if lower.contains("metal") || lower.contains("vulkan") || lower.contains("vram") || lower.contains("gpu") {
                subsystem = .graphics
            }
        }

        // Severity detection
        if lower.contains("this application has crashed") ||
            lower.contains("sigsegv") ||
            lower.contains("sigbus") ||
            lower.contains("sigabrt") ||
            lower.contains("exc_bad_access") ||
            lower.contains("fatal error") ||
            lower.contains("kernel panic") {
            level = .fatal
        } else if level != .fatal {
            if lower.contains("error:") ||
                lower.contains("error]") ||
                lower.contains("failed to load") ||
                lower.contains("unable to load") ||
                lower.contains("could not find object") ||
                lower.contains("failed to find resource") ||
                lower.contains("out of memory") ||
                lower.contains("device lost") {
                level = .error
            } else if lower.contains("warning:") ||
                lower.contains("warn:") ||
                lower.contains("warning]") ||
                lower.contains("warn]") {
                if level == .info {
                    level = .warn
                }
            }
        }

        return (subsystem, level)
    }
}
