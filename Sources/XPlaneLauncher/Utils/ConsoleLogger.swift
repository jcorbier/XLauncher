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
import Observation

enum LogCategory: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case plugins = "Plugins"
    case scenery = "Scenery"
    case aircraft = "Aircraft"
    case lua = "Lua"
    case updates = "Updates"
    case csl = "CSL"
    case launch = "Launch"
    case system = "System"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "square.grid.2x2"
        case .plugins: return "puzzlepiece.extension"
        case .scenery: return "map"
        case .aircraft: return "airplane"
        case .lua: return "scroll"
        case .updates: return "arrow.triangle.2.circlepath"
        case .csl: return "airplane.circle"
        case .launch: return "play.fill"
        case .system: return "gearshape"
        }
    }
}

enum LogLevel: String, CaseIterable, Identifiable, Sendable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"

    var id: String { rawValue }
}

struct LogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: LogCategory
    let level: LogLevel
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: LogCategory = .general,
        level: LogLevel = .info,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
    }

    var timestampString: String {
        timestamp.formatted(date: .numeric, time: .standard)
    }

    var formatted: String {
        if level == .info {
            return "[\(timestampString)] [\(category.rawValue)] \(message)"
        } else {
            return "[\(timestampString)] [\(category.rawValue)] [\(level.rawValue)] \(message)"
        }
    }
}

@MainActor
@Observable
class ConsoleLogger {
    static let shared = ConsoleLogger()

    var entries: [LogEntry] = []
    let maxEntries: Int

    init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }

    func log(
        _ message: String,
        category: LogCategory = .general,
        level: LogLevel = .info
    ) {
        let entry = LogEntry(timestamp: Date(), category: category, level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func info(_ message: String, category: LogCategory = .general) {
        log(message, category: category, level: .info)
    }

    func warn(_ message: String, category: LogCategory = .general) {
        log(message, category: category, level: .warn)
    }

    func error(_ message: String, category: LogCategory = .general) {
        log(message, category: category, level: .error)
    }

    func debug(_ message: String, category: LogCategory = .general) {
        log(message, category: category, level: .debug)
    }

    func clear(category: LogCategory? = nil) {
        if let category = category {
            entries.removeAll { $0.category == category }
        } else {
            entries.removeAll()
        }
    }

    func filteredEntries(category: LogCategory? = nil, searchText: String = "") -> [LogEntry] {
        entries.filter { entry in
            let matchesCategory = (category == nil || entry.category == category)
            let matchesSearch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.rawValue.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }
}
